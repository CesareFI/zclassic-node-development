#!/usr/bin/env python3
"""Check startup connection budgets using fresh, isolated regtest datadirs.

Each daemon reaches RPC readiness and stops normally. Peer connections are
restricted to loopback, with wallets and mining disabled. The output directory
must not already exist.
"""
import argparse
import hashlib
import json
import pathlib
import re
import socket
import subprocess
import time


def run_budget(daemon, cli, output, name, budget):
    datadir = output / name
    datadir.mkdir()
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        rpcport = reservation.getsockname()[1]
    command = [str(daemon), "-datadir=" + str(datadir),
               "-regtest=1", "-daemon=0", "-server=1", "-disablewallet=1",
               "-gen=0", "-bootstrap=0", "-connect=127.0.0.1:1", "-listen=0",
               "-dnsseed=0", "-listenonion=0", "-upnp=0", "-natpmp=0",
               "-rpcbind=127.0.0.1", "-rpcport=" + str(rpcport), "-dbcache=4", "-par=1",
               "-printtoconsole=1", "-maxconnections=" + str(budget)]
    rpccommand = [str(cli), "-datadir=" + str(datadir), "-regtest=1",
                  "-rpcport=" + str(rpcport), "-rpcclienttimeout=5"]
    error = None
    logpath = datadir / "console.log"
    with logpath.open("x") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_for_rpc(process, rpccommand)
            subprocess.run(rpccommand + ["stop"], capture_output=True, check=True, timeout=8)
            process.wait(timeout=60)
        except Exception as failure:
            error = repr(failure)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=10)
    text = logpath.read_text()
    match = re.search(r"Using at most (\d+) connections", text)
    return {"case": name, "configured": budget,
            "actual": int(match[1]) if match else None,
            "exit": process.returncode, "error": error,
            "clean_shutdown": "Shutdown: done" in text,
            "sanitizer_error": any(marker in text for marker in
                                   ("ERROR: AddressSanitizer", "runtime error:",
                                    "ERROR: LeakSanitizer"))}


def wait_for_rpc(process, rpccommand):
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("daemon exited before RPC readiness")
        result = subprocess.run(rpccommand + ["getmininginfo"], capture_output=True,
                                text=True, timeout=8)
        if result.returncode == 0:
            if json.loads(result.stdout)["generate"] is not False:
                raise RuntimeError("mining unexpectedly enabled")
            return
        time.sleep(0.1)
    raise TimeoutError("RPC readiness")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=pathlib.Path, required=True)
    parser.add_argument("--cli", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    daemon = args.daemon.resolve(strict=True)
    cli = args.cli.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True)  # Refuse all existing output/data directories.
    digest = hashlib.sha256()
    with daemon.open("rb") as binary:
        for chunk in iter(lambda: binary.read(1024 * 1024), b""):
            digest.update(chunk)
    report = {"daemon": str(daemon), "sha256": digest.hexdigest(),
              "pass": False, "cases": []}
    budgets = [("platform_cap", (1 << 31) - 1), ("default", 125),
               ("one", 1), ("zero", 0), ("large", 1 << 32),
               ("maximum", (1 << 63) - 1), ("negative", -1),
               ("negative_wrap", -(1 << 32) + 1), ("minimum", -(1 << 63))]
    cap = None
    for name, budget in budgets:
        result = run_budget(daemon, cli, output, name, budget)
        if name == "platform_cap":
            cap = result["actual"]
        valid_cap = cap is not None and 0 < cap <= (1 << 31) - 1
        result["expected"] = max(0, min(budget, cap)) if valid_cap else None
        result["pass"] = (valid_cap and result["actual"] == result["expected"]
                          and result["exit"] == 0 and result["clean_shutdown"]
                          and result["error"] is None and not result["sanitizer_error"])
        report["cases"].append(result)
        print(json.dumps(result), flush=True)
    report["pass"] = all(result["pass"] for result in report["cases"])
    with (output / "result.json").open("x") as result_file:
        json.dump(report, result_file, indent=2)
        result_file.write("\n")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
