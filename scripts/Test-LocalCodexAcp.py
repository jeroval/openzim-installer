"""Scenario ACP reel dans un repertoire jetable ; aucune certification simulee."""
import argparse
import json
import os
from pathlib import Path
import queue
import sqlite3
import subprocess
import sys
import threading
import time


def tool_payload(row):
    """Hermes peut ajouter un avertissement apres le JSON du resultat."""
    content = row.get('content') or ''
    try:
        value, _ = json.JSONDecoder().raw_decode(content.lstrip())
        return value if isinstance(value, dict) else {'text': content}
    except (ValueError, TypeError):
        return {'text': content}


class AcpClient:
    def __init__(self, executable, home, workspace, timeout):
        self.workspace = workspace.resolve()
        self.deadline = time.monotonic() + timeout
        self.events = []
        self.inbox = queue.Queue()
        self.sequence = 0
        self.log = (workspace / "hermes.stderr.log").open("w", encoding="utf-8")
        self.process = subprocess.Popen(
            [executable, "acp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=self.log, text=True, encoding="utf-8", bufsize=1,
            env={**os.environ, "HERMES_HOME": home}, cwd=workspace,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

        def reader():
            for line in self.process.stdout:
                try:
                    self.inbox.put(json.loads(line))
                except ValueError:
                    self.inbox.put({"invalidStdout": line})
            self.inbox.put({"closed": True})
        threading.Thread(target=reader, daemon=True).start()

    def send(self, message):
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", **message}) + "\n")
        self.process.stdin.flush()

    def call(self, method, params):
        self.sequence += 1
        identifier = self.sequence
        self.send({"id": identifier, "method": method, "params": params})
        while True:
            remaining = self.deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Scenario ACP : delai total depasse")
            try:
                message = self.inbox.get(timeout=min(remaining, 5))
            except queue.Empty:
                continue
            self.events.append(message)
            if message.get("closed") or "invalidStdout" in message:
                raise RuntimeError("Serveur ACP arrete ou stdout non conforme")
            if "method" in message and "id" in message:
                if message["method"] == "session/request_permission":
                    call = message.get("params", {}).get("toolCall", {})
                    diffs = [item for item in call.get("content", []) if item.get("type") == "diff"]
                    allowed = call.get("kind") == "edit" and bool(diffs)
                    for diff in diffs:
                        target = Path(diff.get("path", ""))
                        if not target.is_absolute():
                            target = self.workspace / target
                        allowed = allowed and target.resolve() in {
                            self.workspace / "calculator.py", self.workspace / "shipping.py"}
                    options = message.get("params", {}).get("options", [])
                    once = next((o["optionId"] for o in options if o.get("kind") == "allow_once"), None)
                    outcome = {"outcome": "selected", "optionId": once} if allowed and once else {"outcome": "cancelled"}
                    self.send({"id": message["id"], "result": {"outcome": outcome}})
                else:
                    self.send({"id": message["id"], "error": {"code": -32601, "message": "Client capability not supported"}})
            elif message.get("id") == identifier:
                if "error" in message:
                    raise RuntimeError(str(message["error"]))
                return message.get("result", {})

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.log.close()
        (self.workspace / "acp-transcript.json").write_text(json.dumps(self.events, indent=2), encoding="utf-8")


def fixture(workspace):
    files = {
        "calculator.py": "def add(a, b):\n    return a - b\n",
        "shipping.py": "def shipping(total):\n    return 5 if total >= 50 else 0\n",
        "test_app.py": (
            "import unittest\nfrom calculator import add\nfrom shipping import shipping\n"
            "class Tests(unittest.TestCase):\n"
            "    def test_add(self):\n        self.assertEqual(add(2, 3), 5)\n"
            "    def test_shipping(self):\n        self.assertEqual(shipping(50), 0)\n"
            "        self.assertEqual(shipping(49), 5)\n"
            "if __name__ == '__main__': unittest.main()\n"),
        "AGENTS.md": (
            "Work only in this fixture directory. Do not change test_app.py. "
            "Do not install dependencies, access credentials, or use the network. "
            "Use the configured OpenZIM MCP for documentation. "
            "Inspect, search, read, plan, run tests, diagnose, patch both modules, retest.\n"),
    }
    for name, content in files.items():
        (workspace / name).write_text(content, encoding="utf-8")
    return files


def run(executable, home, workspace, timeout):
    workspace.mkdir(parents=True, exist_ok=False)
    original = fixture(workspace)
    initial = subprocess.run([sys.executable, "-m", "unittest", "-v"], cwd=workspace,
                             capture_output=True, text=True, timeout=30)
    client = AcpClient(executable, home, workspace, timeout)
    report = {"status": "FAIL", "workspace": str(workspace), "checks": {}, "error": None}
    session = {}
    diagnosed_before_edit = False
    first_messages = ''
    try:
        handshake = client.call("initialize", {"protocolVersion": 1, "clientCapabilities": {},
                                               "clientInfo": {"name": "local-codex-certification", "version": "1"}})
        session = client.call("session/new", {"cwd": str(workspace.resolve()), "mcpServers": []})
        rules = (f"Your working directory is {workspace.resolve()}; use relative paths, never /workspace. "
                 f"Terminal uses Git Bash. Quote Python executable '{Path(sys.executable).as_posix()}'. "
                 "No network, downloads or delegation. ")
        def prompt(text):
            return client.call("session/prompt", {"sessionId": session["sessionId"],
                "prompt": [{"type": "text", "text": rules + text}]})
        prompt("Do not modify files yet. Inspect using search_files and read_file. Use the terminal tool "
               "(not execute_code) to run the given Python executable with -m unittest -v. "
               "Then write a final response naming calculator.py and shipping.py, explaining each failure "
               "and your fix plan. Do not stop with an empty response.")
        first_messages = ''.join(e.get('params', {}).get('update', {}).get('content', {}).get('text', '')
            for e in client.events if e.get('params', {}).get('update', {}).get('sessionUpdate') == 'agent_message_chunk')
        diagnosed_before_edit = all((workspace / name).read_text(encoding="utf-8") == original[name]
                                   for name in ("calculator.py", "shipping.py")) and len(first_messages) > 80
        prompt("Now fix BOTH calculator.py and shipping.py with the patch tool. Do not change test_app.py. "
               "Then use the terminal tool (not execute_code) to execute the given Python executable "
               "with -m py_compile calculator.py shipping.py and then -m unittest -v. "
               "Diagnose and fix any remaining failure, then retest. Stop after a concise summary.")
        result = prompt("Use mcp__openzim__openzim_list_archives. Find docs.python.org in that list. "
                        "Call mcp__openzim__openzim_search_archive with its exact zim_file_path and query "
                        "'What is unittest.TestCase?'. Cite the returned document title, archive and Python "
                        "version. Do not use generic search or web fallback. Stop if the tool is unavailable.")
        report["agentInfo"] = handshake.get("agentInfo")
        report["stopReason"] = result.get("stopReason")
    except (OSError, RuntimeError, TimeoutError) as error:
        report["error"] = str(error)
    finally:
        client.close()
    evidence = []
    if session.get("sessionId"):
        try:
            # Lecture seule de la session creee par ce test. Hermes reste le seul
            # proprietaire de sa memoire ; aucun second historique n'est importe.
            database = (Path(home) / "state.db").resolve().as_uri() + "?mode=ro"
            with sqlite3.connect(database, uri=True) as connection:
                connection.row_factory = sqlite3.Row
                evidence = [dict(row) for row in connection.execute(
                    "SELECT role,tool_name,content,tool_calls,tool_call_id FROM messages WHERE session_id=? ORDER BY id",
                    (session["sessionId"],))]
        except (sqlite3.Error, OSError) as error:
            report["evidenceError"] = str(error)
    (workspace / "session-evidence.json").write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    # Les resultats finaux sont verifies par le controleur, pas par une affirmation du modele.
    final = subprocess.run([sys.executable, "-m", "unittest", "-v"], cwd=workspace,
                           capture_output=True, text=True, timeout=30)
    build = subprocess.run([sys.executable, "-m", "py_compile", "calculator.py", "shipping.py"],
                           cwd=workspace, capture_output=True, text=True, timeout=30)
    tools = [row for row in evidence if row['role'] == 'tool']
    calls = {}
    for row in evidence:
        if row.get('tool_calls'):
            for call in json.loads(row['tool_calls']):
                calls[call['id']] = call.get('function', {}).get('arguments', '')
    successful = [row for row in tools if not tool_payload(row).get('error') and
                  not tool_payload(row).get('is_error') and tool_payload(row).get('exit_code', 0) == 0]
    names = {row['tool_name'] for row in successful}
    terminals = [row for row in successful if row['tool_name'] == 'terminal' and
                 tool_payload(row).get('exit_code') == 0]
    documentation = [row for row in successful if row['tool_name'] == 'mcp__openzim__openzim_search_archive']
    checks = {
        "acp": report.get("agentInfo", {}).get("name") == "hermes-agent",
        "search": 'search_files' in names, "read": 'read_file' in names,
        "plan": diagnosed_before_edit,
        "diagnosis": diagnosed_before_edit and 'calculator' in first_messages and 'shipping' in first_messages,
        "multiFileEdit": all((workspace / name).read_text(encoding="utf-8") != original[name]
                             for name in ("calculator.py", "shipping.py")),
        "patch": any(row['tool_name'] == 'patch' and tool_payload(row).get('success') is True for row in successful),
        "terminal": bool(terminals),
        "observedFailure": initial.returncode != 0 and any(row['tool_name'] == 'terminal' and
            tool_payload(row).get('exit_code', 0) != 0 and 'FAIL' in row['content'] for row in tools),
        "retest": final.returncode == 0 and any('unittest' in calls.get(row['tool_call_id'], '') and
            'OK' in tool_payload(row).get('output', '') for row in terminals),
        "build": build.returncode == 0 and any('py_compile' in calls.get(row['tool_call_id'], '') for row in terminals),
        "testsPreserved": (workspace / "test_app.py").read_text(encoding="utf-8") == original["test_app.py"],
        "openzimCall": bool(documentation),
        "documentationRetrieval": any("retrieved_archive_content" in json.dumps(u) and
                                       "No results" not in json.dumps(u) for u in documentation),
        "completed": report.get("stopReason") == "end_turn" and report["error"] is None,
        "noNetworkOrDelegation": not any(str(row['tool_name']).startswith(('web_', 'browser_', 'delegate_task')) for row in tools),
    }
    report["checks"] = checks
    report["status"] = "PASS" if all(checks.values()) else "FAIL"
    report["initialTests"] = initial.stdout + initial.stderr
    report["finalTests"] = final.stdout + final.stderr
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", required=True)
    parser.add_argument("--home", required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--timeout", type=int, default=900)
    options = parser.parse_args()
    print(json.dumps(run(options.executable, options.home, Path(options.workspace), options.timeout)))
