#!/usr/bin/env python3
"""Check worker cleanup when an ordinary startup option fails after threads start.

Use fresh regtest datadirs, no wallets/mining, and only loopback RPC. The invalid
local network-selection option is rejected before peer connections are started.
"""
import argparse
import json
import pathlib
import socket
import subprocess


def run_once(daemon, datadir, rpc_enabled, script_threads=2):
    datadir.mkdir()
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    command = [str(daemon), "-datadir=" + str(datadir), "-regtest=1",
               "-daemon=0", "-server=" + str(int(rpc_enabled)), "-rpcport=" + str(port),
               "-rpcbind=127.0.0.1", "-disablewallet=1", "-gen=0", "-bootstrap=0",
               "-listen=0", "-connect=127.0.0.1:1", "-dnsseed=0", "-listenonion=0",
               "-upnp=0", "-natpmp=0", "-dbcache=4", "-par=" + str(script_threads),
               "-printtoconsole=1", "-onlynet=invalid"]
    error = None
    logpath = datadir / "console.log"
    with logpath.open("x") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            process.wait(timeout=90)
        except subprocess.TimeoutExpired as failure:
            error = repr(failure)
            process.terminate()
            try:
                process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
    text = logpath.read_text()
    _, separator, shutdown = text.partition("Shutdown: In progress...")
    result = {"exit": process.returncode, "error": error, "rpc_enabled": rpc_enabled,
              "expected_error": "Unknown network specified in -onlynet" in text,
              "worker_started": "scheduler thread start" in text,
              "clean_shutdown": bool(separator) and "Shutdown: done" in shutdown,
              "pid_removed": not (datadir / "regtest" / "zclassicd.pid").exists(),
              "late_threads": [line for line in shutdown.splitlines()
                               if "scheduler thread" in line],
              "sanitizer_error": any(marker in text for marker in
                                     ("ERROR: AddressSanitizer", "runtime error:",
                                      "ERROR: LeakSanitizer"))}
    result["pass"] = (result["exit"] == 1 and result["error"] is None
                      and result["expected_error"] and result["worker_started"]
                      and result["clean_shutdown"] and result["pid_removed"]
                      and not result["late_threads"] and not result["sanitizer_error"])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--repeat", type=int, default=2)
    args = parser.parse_args()
    if not 1 <= args.repeat <= 8:
        parser.error("--repeat must be from 1 to 8")
    daemon = args.daemon.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True)
    report = {"runs": []}
    for rpc_enabled in (False, True):
        for index in range(args.repeat):
            result = run_once(daemon, output / (str(int(rpc_enabled)) + "-" + str(index)),
                              rpc_enabled)
            report["runs"].append(result)
            print(json.dumps(result), flush=True)
    report["pass"] = all(result["pass"] for result in report["runs"])
    with (output / "result.json").open("x") as result_file:
        json.dump(report, result_file, indent=2)
        result_file.write("\n")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
