#!/usr/bin/env python3
"""Check PID-file ownership with a primary node and failed duplicate startups.

Only fresh regtest datadirs and loopback RPC are used; wallets and mining are off.
The output directory must not already exist. PID files are a Unix-only feature.
"""
import argparse
import json
import os
import pathlib
import socket
import subprocess

from maxconnections import wait_for_rpc


def finish(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)


def failed_start(command, logpath, expected_error):
    with logpath.open("x") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            process.wait(timeout=30)
        finally:
            finish(process)
    text = logpath.read_text()
    return {"exit": process.returncode, "expected_error": expected_error in text,
            "clean_shutdown": "Shutdown: done" in text,
            "sanitizer_error": any(marker in text for marker in
                                   ("ERROR: AddressSanitizer", "runtime error:",
                                    "ERROR: LeakSanitizer"))}


def clean_rejection(result):
    return (result["exit"] == 1 and result["expected_error"]
            and result["clean_shutdown"] and not result["sanitizer_error"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=pathlib.Path, required=True)
    parser.add_argument("--cli", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if os.name != "posix":
        parser.error("PID files are only supported on Unix platforms")
    output = args.output.resolve()
    output.mkdir(parents=True)
    datadir = output / "datadir"
    datadir.mkdir()
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    command = [str(args.daemon.resolve(strict=True)), "-datadir=" + str(datadir),
               "-regtest=1", "-daemon=0", "-server=1", "-rpcport=" + str(port),
               "-rpcbind=127.0.0.1", "-disablewallet=1", "-gen=0", "-bootstrap=0",
               "-connect=127.0.0.1:1", "-listen=0", "-dnsseed=0", "-listenonion=0",
               "-upnp=0", "-natpmp=0", "-dbcache=4", "-par=1", "-printtoconsole=1"]
    rpccommand = [str(args.cli.resolve(strict=True)), "-datadir=" + str(datadir),
                  "-regtest=1", "-rpcport=" + str(port), "-rpcclienttimeout=5"]
    pidpath = datadir / "regtest" / "zclassicd.pid"
    report = {"pass": False, "duplicates": []}
    with (output / "primary.log").open("x") as log:
        primary = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_for_rpc(primary, rpccommand)
            original = pidpath.read_text()
            assert int(original) == primary.pid
            cases = [("locked", [], "Cannot obtain a lock on data directory"),
                     ("invalid", ["-maxblocksinflight=0"],
                      "-maxblocksinflight must be an integer")]
            for name, extra, expected_error in cases:
                result = failed_start(command + extra, output / (name + ".log"), expected_error)
                result["pid_preserved"] = pidpath.exists() and pidpath.read_text() == original
                result["primary_alive"] = primary.poll() is None
                report["duplicates"].append(result)
            subprocess.run(rpccommand + ["getblockchaininfo"], capture_output=True,
                           check=True, timeout=8)
            subprocess.run(rpccommand + ["stop"], capture_output=True, check=True, timeout=8)
            primary.wait(timeout=60)
            report["primary_exit"] = primary.returncode
            report["pid_removed_by_owner"] = not pidpath.exists()
            invalid_pid = output / "pid-directory"
            invalid_pid.mkdir()
            report["write_failure"] = failed_start(
                command + ["-pid=" + str(invalid_pid)], output / "write-failure.log",
                "Unable to create PID file")
            report["directory_preserved"] = invalid_pid.is_dir()
            report["pass"] = (primary.returncode == 0 and report["pid_removed_by_owner"]
                              and clean_rejection(report["write_failure"])
                              and report["directory_preserved"]
                              and all(clean_rejection(case) and case["pid_preserved"]
                                      and case["primary_alive"] for case in report["duplicates"]))
        except Exception as error:
            report["error"] = repr(error)
        finally:
            finish(primary)
    with (output / "result.json").open("x") as result_file:
        json.dump(report, result_file, indent=2)
        result_file.write("\n")
    print(json.dumps(report, indent=2))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
