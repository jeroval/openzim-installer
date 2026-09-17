"""Benchmark Ollama en streaming, sans telechargement de modele."""
import argparse
import json
import shutil
import subprocess
import threading
import time
import urllib.request
from urllib.parse import urlparse


def request_json(base_url, path):
    with urllib.request.urlopen(base_url + path, timeout=10) as response:
        return json.load(response)


def measure(base_url, model, context, output_tokens, timeout):
    if urlparse(base_url).hostname not in {"localhost", "127.0.0.1", "::1"}:
        raise ValueError("Le benchmark exige un serveur Ollama local")
    samples, sample_errors = [], []
    stop = threading.Event()
    try:
        import psutil
    except ImportError:
        psutil = None
        sample_errors.append("psutil absent : RAM/CPU non mesures")
    nvidia = shutil.which("nvidia-smi")

    def sample():
        while not stop.is_set():
            point = {}
            try:
                if psutil:
                    point.update(ramUsedBytes=psutil.virtual_memory().used,
                                 cpuPercent=psutil.cpu_percent())
                if nvidia:
                    result = subprocess.run(
                        [nvidia, "--query-gpu=memory.used,utilization.gpu", "--format=csv,noheader,nounits"],
                        capture_output=True, text=True, timeout=3,
                        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0), check=True)
                    rows = [[float(v.strip()) for v in row.split(",")]
                            for row in result.stdout.splitlines()]
                    point.update(vramUsedMiB=sum(row[0] for row in rows),
                                 gpuPercent=max(row[1] for row in rows))
                samples.append(point)
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                sample_errors.append(str(error))
            stop.wait(0.25)

    worker = threading.Thread(target=sample, daemon=True)
    worker.start()
    started = time.perf_counter()
    first_token, final = None, None
    payload = {"model": model, "prompt": "Explain why regression tests are useful in software development.",
               "stream": True, "think": False,
               "options": {"num_ctx": context, "num_predict": output_tokens, "temperature": 0}}
    request = urllib.request.Request(base_url + "/api/generate", json.dumps(payload).encode(),
                                     {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            for raw in response:
                if time.perf_counter() - started > timeout:
                    raise TimeoutError("Duree totale du benchmark depassee")
                event = json.loads(raw)
                if event.get("error"):
                    raise RuntimeError(event["error"])
                if first_token is None and (event.get("response") or event.get("thinking")):
                    first_token = time.perf_counter() - started
                if event.get("done"):
                    final = event
        if not final or not final.get("eval_count") or not final.get("eval_duration"):
            raise RuntimeError("Flux Ollama incomplet ou sans tokens")
    finally:
        stop.set()
        worker.join(timeout=5)
    running = request_json(base_url, "/api/ps")

    def peak(key):
        values = [point[key] for point in samples if key in point]
        return max(values) if values else None

    return {"status": "PASS", "model": model, "contextTokens": context,
            "durationSeconds": time.perf_counter() - started,
            "loadSeconds": final.get("load_duration", 0) / 1e9,
            "ttftSeconds": first_token,
            "tokensPerSecond": final["eval_count"] / (final["eval_duration"] / 1e9),
            "generatedTokens": final["eval_count"], "ramPeakBytes": peak("ramUsedBytes"),
            "vramPeakMiB": peak("vramUsedMiB"), "cpuPeakPercent": peak("cpuPercent"),
            "gpuPeakPercent": peak("gpuPercent"), "resourceScope": "whole-machine sampled at 250ms",
            "sampleCount": len(samples), "measurementErrors": sorted(set(sample_errors)),
            "runningModels": running.get("models", []), "coldStartGuaranteed": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--context", type=int, required=True)
    parser.add_argument("--tokens", type=int, default=128)
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    print(json.dumps(measure(args.url.rstrip("/"), args.model, args.context, args.tokens, args.timeout)))


if __name__ == "__main__":
    main()
