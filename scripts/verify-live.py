#!/usr/bin/env python3
"""Bounded opt-in real-client verification. Sends one tiny prompt to each installed CLI.

Uses the current user's existing authentication. No credentials are read or copied.
Detailed local process paths stay in gitignored JSONL; the summary is shareable.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "evidence"
EVIDENCE.mkdir(exist_ok=True)
PROBE = ROOT / ".build/release/tide-probe"
if not PROBE.exists():
    raise SystemExit("Build first: swift build -c release")

def main():
    jobs = []
    prompt = "Reply with exactly TIDE_OK. Do not call any tools."
    configurations = [
        ("claudeCode", "claude", ["--print", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--tools", "", "--disable-slash-commands", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}', "--no-session-persistence", "--settings", '{"disableAllHooks":true}', "--max-budget-usd", "0.05"]),
        ("codex", "codex", ["exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", prompt]),
    ]
    raw_path = EVIDENCE / "real-clients.jsonl"
    with tempfile.TemporaryDirectory(prefix="ai-tide-live-") as directory, raw_path.open("w") as raw:
        monitor = subprocess.Popen([str(PROBE), "--seconds", "35", "--interval", "0.6"], stdout=raw, stderr=subprocess.DEVNULL)
        try:
            # Warm initial signature enumeration. Subsequent scans cache unrelated processes.
            time.sleep(5)
            for client, binary, flags in configurations:
                executable = shutil.which(binary)
                if not executable:
                    jobs.append({"client": client, "installed": False})
                    continue
                output = tempfile.TemporaryFile()
                error = tempfile.TemporaryFile()
                environment = os.environ.copy()
                environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
                process = subprocess.Popen([executable, *flags], cwd=directory, stdin=subprocess.PIPE if client == "claudeCode" else subprocess.DEVNULL, stdout=output, stderr=error, env=environment)
                jobs.append({"client": client, "installed": True, "process": process, "output": output, "error": error, "pid": process.pid})
            # Claude's streaming input keeps a real session alive across samples.
            time.sleep(4)
            for job in jobs:
                process = job.get("process")
                if job["client"] == "claudeCode" and process and process.poll() is None:
                    message = {"type": "user", "message": {"role": "user", "content": prompt}}
                    process.stdin.write((json.dumps(message) + "\n").encode())
                    process.stdin.flush()
            deadline = time.monotonic() + 17
            while time.monotonic() < deadline and any(job.get("process") and job["process"].poll() is None for job in jobs):
                time.sleep(0.5)
            for job in jobs:
                process = job.get("process")
                if process and process.stdin and not process.stdin.closed:
                    process.stdin.close()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        pass
                if process and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            monitor.wait(timeout=40)
        finally:
            if monitor.poll() is None:
                monitor.terminate()
                monitor.wait(timeout=3)
            for job in jobs:
                process = job.get("process")
                if process and process.poll() is None:
                    process.terminate()
                    process.wait(timeout=3)
    samples = [json.loads(line) for line in raw_path.read_text().splitlines() if line.strip()]
    report = {"date": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "collector": "production SystemCollector; no proxy or decrypted payloads", "samples": len(samples), "collectionErrors": [sample["error"] for sample in samples if sample.get("error")], "clients": []}
    for job in jobs:
        if not job.get("installed"):
            report["clients"].append({"client": job["client"], "installed": False})
            continue
        pid = job["pid"]
        rows = [row for sample in samples for row in sample["readings"] if row["identity"]["pid"] == pid]
        job["output"].seek(0)
        output = job["output"].read().decode(errors="replace")
        job["output"].close()
        job["error"].close()
        received = sum(row.get("receivedDelta", 0) or 0 for row in rows)
        sent = sum(row.get("sentDelta", 0) or 0 for row in rows)
        counter_received = max((row.get("receivedCounter", 0) or 0 for row in rows), default=0)
        counter_sent = max((row.get("sentCounter", 0) or 0 for row in rows), default=0)
        report["clients"].append({"client": job["client"], "pid": pid, "installed": True,
            "signatureObserved": bool(rows), "observedSamples": len(rows),
            "signingIDs": sorted({row["identity"]["signingID"] for row in rows}),
            "teams": sorted({row["identity"]["team"] for row in rows}),
            "observedReceivedBytes": received, "observedSentBytes": sent,
            "maxObservedProcessReceivedCounter": counter_received, "maxObservedProcessSentCounter": counter_sent,
            "trafficObserved": counter_received + counter_sent > 0,
            "requestSucceeded": job["process"].returncode == 0 and "TIDE_OK" in output,
            "exitCode": job["process"].returncode})
    gui = [row for sample in samples for row in sample["readings"] if row["identity"]["signingID"] == "com.openai.codex.helper"]
    report["codexGUI"] = {"signedHelperObserved": bool(gui), "pids": sorted({row["identity"]["pid"] for row in gui}), "observedReceivedBytes": sum(row.get("receivedDelta", 0) or 0 for row in gui), "observedSentBytes": sum(row.get("sentDelta", 0) or 0 for row in gui), "note": "Existing GUI process traffic; no claim of request-level attribution."}
    (EVIDENCE / "real-clients-summary.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(report, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()
