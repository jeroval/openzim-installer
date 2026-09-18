"""Tests offline : aucune instance Ollama, Hermes ou archive requise."""
import asyncio
import importlib.util
import io
import json
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


measure = load("measure_localcodex", "Measure-LocalCodex.py")
certify = load("certify_localcodex", "Test-LocalCodexAcp.py")


class CertificationTests(unittest.TestCase):
    def test_terminal_exit_code_survives_appended_hermes_warning(self):
        row = {'content': '{"output":"FAILED (failures=2)","exit_code":1,"error":null}\n\n[Tool loop warning]'}
        self.assertEqual(certify.tool_payload(row)['exit_code'], 1)

    def test_non_json_result_does_not_invent_an_exit_code(self):
        self.assertNotIn('exit_code', certify.tool_payload({'content': 'not JSON'}))

    def test_archive_listing_proves_openzim_access_without_document_retrieval(self):
        tools = [{'tool_name': 'mcp__openzim__openzim_list_archives',
                  'content': '{"result":"docs.python.org_en_2024-05.zim"}'}]
        self.assertEqual(certify.openzim_checks(tools), (True, False))

    def test_archive_search_proves_document_retrieval(self):
        tools = [{'tool_name': 'mcp__openzim__openzim_search_archive',
                  'content': '<retrieved_archive_content>TestCase</retrieved_archive_content>'}]
        self.assertEqual(certify.openzim_checks(tools), (True, True))

    def test_unrelated_tool_does_not_prove_openzim_access(self):
        tools = [{'tool_name': 'read_file', 'content': 'fixture'}]
        self.assertEqual(certify.openzim_checks(tools), (False, False))

    def test_local_delegation_is_not_misreported_as_external_network(self):
        tools = [{'tool_name': 'delegate_task', 'content': 'local Ollama subagent'}]
        self.assertTrue(certify.has_no_external_network(tools))

    def test_web_tool_is_reported_as_external_network(self):
        tools = [{'tool_name': 'web_search', 'content': 'external result'}]
        self.assertFalse(certify.has_no_external_network(tools))

    def test_diagnosis_requires_both_file_names(self):
        complete = ('calculator.py subtracts instead of adding; replace subtraction with addition. '
                    'shipping.py reverses the free-shipping threshold; invert that condition.')
        incomplete = 'I inspected the working directory and I will now explain the failures in detail.'
        self.assertTrue(certify.has_two_file_diagnosis(complete))
        self.assertFalse(certify.has_two_file_diagnosis(incomplete))


class BenchmarkTests(unittest.TestCase):
    def test_rejects_remote_endpoint(self):
        with self.assertRaises(ValueError):
            measure.measure("https://example.com", "fixture", 65536, 10, 1)

    def test_incomplete_stream_is_not_success(self):
        stream = io.BytesIO(b'{"response":"partial","done":false}\n')
        with patch.object(measure.urllib.request, "urlopen", return_value=stream), \
                patch.object(measure.shutil, "which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "incomplet"):
                measure.measure("http://127.0.0.1", "fixture", 65536, 10, 1)

    def test_server_error_is_propagated(self):
        stream = io.BytesIO(b'{"error":"not enough memory"}\n')
        with patch.object(measure.urllib.request, "urlopen", return_value=stream), \
                patch.object(measure.shutil, "which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "not enough memory"):
                measure.measure("http://127.0.0.1", "fixture", 65536, 10, 1)

    def test_stream_metrics_use_server_counts_and_duration(self):
        stream = io.BytesIO(b'{"response":"hello","done":false}\n' +
                           b'{"done":true,"eval_count":12,"eval_duration":2000000000,"load_duration":500000000}\n')
        with patch.object(measure.urllib.request, "urlopen", return_value=stream), \
                patch.object(measure.shutil, "which", return_value=None), \
                patch.object(measure, "request_json", return_value={"models": []}):
            result = measure.measure("http://127.0.0.1", "fixture", 65536, 12, 1)
        self.assertEqual(result["tokensPerSecond"], 6)
        self.assertEqual(result["loadSeconds"], .5)
        self.assertIsNotNone(result["ttftSeconds"])
        self.assertIsNone(result["vramPeakMiB"])
        self.assertFalse(result["coldStartGuaranteed"])


class BridgeTests(unittest.TestCase):
    def setUp(self):
        class Server:
            def __init__(self, *args, **kwargs):
                self.tools = {}

            def tool(self, **kwargs):
                def register(function):
                    self.tools[function.__name__] = function
                    return function
                return register

        stubs = {}
        for name, attribute, value in (
                ("mcp.server.mcpserver", "MCPServer", Server),
                ("openzim_mcp.config", "OpenZimMcpConfig", object),
                ("openzim_mcp.server", "OpenZimMcpServer", object)):
            stub = types.ModuleType(name)
            setattr(stub, attribute, value)
            stubs[name] = stub
        with patch.dict(sys.modules, stubs):
            bridge_module = load("bridge_fixture", "OpenZimCompatServer.py")
        self.calls = []

        async def query(*args):
            self.calls.append(args)
            return "fixture result"

        self.server = bridge_module.build_server(types.SimpleNamespace(query=query))

    def test_generic_question_explicitly_searches_all_archives(self):
        asyncio.run(self.server.tools["openzim_search"]("  unittest  "))
        self.assertEqual(self.calls, [("search all files for unittest",)])

    def test_empty_question_never_reaches_backend(self):
        with self.assertRaises(ValueError):
            asyncio.run(self.server.tools["openzim_search"]("   "))
        self.assertEqual(self.calls, [])

    def test_named_archive_path_is_preserved(self):
        asyncio.run(self.server.tools["openzim_search_archive"]("TestCase", "C:/local/python.zim"))
        self.assertEqual(self.calls, [("TestCase", "C:/local/python.zim")])


if __name__ == "__main__":
    unittest.main()
