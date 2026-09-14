#!/usr/bin/env python3
"""Preserve a config with a local syntax error and load valid list options once.

Only fresh datadirs and loopback RPC/connection destinations are used. Wallets
and mining are disabled. Config contents and authentication data are not logged.
"""
import argparse
import hashlib
import json
import pathlib
import socket
import subprocess

from maxconnections import wait_for_rpc
from pidfile import finish


def command_for(daemon, datadir):
    return [str(daemon), "-datadir=" + str(datadir), "-regtest=1", "-daemon=0",
            "-disablewallet=1", "-gen=0", "-bootstrap=0", "-listen=0", "-dnsseed=0",
            "-listenonion=0", "-upnp=0", "-natpmp=0", "-dbcache=4", "-par=1",
            "-printtoconsole=1"]


def syntax_error(daemon, output):
    output.mkdir()
    config = output / "zclassic.conf"
    original = b"# Retain this operator comment.\nlisten 0\n"
    config.write_bytes(original)
    command = command_for(daemon, output) + ["-server=0", "-onlynet=invalid",
                                              "-connect=127.0.0.1:1"]
    logpath = output / "console.log"
    with logpath.open("x") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            process.wait(timeout=60)
        finally:
            finish(process)
    text = logpath.read_text()
    preserved = config.read_bytes() == original
    result = {"exit": process.returncode, "preserved": preserved,
              "parse_error_reported": "Error reading configuration file" in text,
              "original_sha256": hashlib.sha256(original).hexdigest(),
              "blocks_unopened": not (output / "regtest" / "blocks").exists()}
    result["pass"] = (result["exit"] == 1 and preserved and result["parse_error_reported"]
                      and result["blocks_unopened"])
    return result


def creation(daemon, output, missing_parent=False):
    output.mkdir()
    config = output / "zclassic.conf"
    if missing_parent:
        config = output / "missing-parent" / "zclassic.conf"
    command = command_for(daemon, output) + ["-server=0", "-onlynet=invalid",
                "-connect=127.0.0.1:1", "-conf=" + str(config)]
    logpath = output / "console.log"
    with logpath.open("x") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            process.wait(timeout=60)
        finally:
            finish(process)
    expected = ("Unable to create configuration file" if missing_parent
                else "Unknown network specified in -onlynet")
    result = {"exit": process.returncode, "expected_error": expected in logpath.read_text(),
              "config_created": config.exists(),
              "blocks_unopened": not (output / "regtest" / "blocks").exists()}
    result["pass"] = (result["exit"] == 1 and result["expected_error"]
                      and result["config_created"] != missing_parent and result["blocks_unopened"])
    return result


def list_option(daemon, cli, output):
    output.mkdir()
    report = {"pass": False}
    with socket.socket() as unused:
        unused.bind(("127.0.0.1", 0))
        destination = "127.0.0.1:" + str(unused.getsockname()[1])
        config = output / "zclassic.conf"
        original = ("# A single configured peer.\naddnode=" + destination + "\n").encode()
        config.write_bytes(original)
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            rpcport = reservation.getsockname()[1]
        command = command_for(daemon, output) + ["-server=1", "-rpcbind=127.0.0.1",
                    "-rpcport=" + str(rpcport), "-connect=" + destination, "-maxconnections=1"]
        rpccommand = [str(cli), "-datadir=" + str(output), "-regtest=1",
                      "-rpcport=" + str(rpcport), "-rpcclienttimeout=5"]
        with (output / "console.log").open("x") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            try:
                wait_for_rpc(process, rpccommand)
                response = subprocess.run(rpccommand + ["getaddednodeinfo", "false"],
                                          check=True, capture_output=True, text=True, timeout=8)
                entries = json.loads(response.stdout)
                report["configured_peers"] = [entry["addednode"] for entry in entries]
                report["preserved"] = config.read_bytes() == original
                subprocess.run(rpccommand + ["stop"], check=True, capture_output=True, timeout=8)
                process.wait(timeout=60)
                report["exit"] = process.returncode
                report["pass"] = (report["configured_peers"] == [destination]
                                  and report["preserved"] and report["exit"] == 0)
            except Exception as error:
                report["error"] = repr(error)
            finally:
                finish(process)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=pathlib.Path, required=True)
    parser.add_argument("--cli", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True)
    daemon, cli = args.daemon.resolve(strict=True), args.cli.resolve(strict=True)
    report = {"syntax": syntax_error(daemon, output / "syntax"),
              "list": list_option(daemon, cli, output / "list"),
              "missing": creation(daemon, output / "missing"),
              "write-failure": creation(daemon, output / "write-failure", True)}
    report["sanitizer_error"] = any(marker in (directory / "console.log").read_text()
                                    for directory in (output / "syntax", output / "list",
                                                      output / "missing", output / "write-failure")
                                    for marker in ("ERROR: AddressSanitizer", "runtime error:",
                                                   "ERROR: LeakSanitizer"))
    report["pass"] = (all(report[name]["pass"] for name in ("syntax", "list", "missing", "write-failure"))
                      and not report["sanitizer_error"])
    with (output / "result.json").open("x") as result_file:
        json.dump(report, result_file, indent=2)
        result_file.write("\n")
    print(json.dumps(report, indent=2))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
