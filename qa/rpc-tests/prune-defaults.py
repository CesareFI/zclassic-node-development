#!/usr/bin/env python3
"""Check fresh pruning/index defaults and restart with genesis-only datadirs.

No existing data is pruned. Wallets, mining and external connections are disabled.
An explicitly configured transaction index must still conflict with pruning.
"""
import argparse
import json
import pathlib
import socket
import subprocess

from maxconnections import wait_for_rpc
from pidfile import finish


def command_for(daemon, datadir, prune):
    return [str(daemon), "-datadir=" + str(datadir), "-regtest=1", "-daemon=0",
            "-disablewallet=1", "-gen=0", "-bootstrap=0", "-listen=0",
            "-connect=127.0.0.1:1", "-dnsseed=0", "-listenonion=0", "-upnp=0",
            "-natpmp=0", "-dbcache=4", "-par=1", "-printtoconsole=1",
            "-prune=" + ("550" if prune else "0")]


def run_mode(daemon, cli, output, prune):
    output.mkdir()
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        rpcport = reservation.getsockname()[1]
    command = command_for(daemon, output, prune) + ["-server=1", "-rpcbind=127.0.0.1",
                                                   "-rpcport=" + str(rpcport)]
    rpccommand = [str(cli), "-datadir=" + str(output), "-regtest=1",
                  "-rpcport=" + str(rpcport), "-rpcclienttimeout=5"]
    report = {"prune": prune, "runs": [], "pass": False}
    config_bytes = None
    for iteration in range(2):
        logpath = output / ("startup-" + str(iteration) + ".log")
        result = {"pass": False}
        with logpath.open("x") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            try:
                wait_for_rpc(process, rpccommand)
                response = subprocess.run(rpccommand + ["getblockchaininfo"], check=True,
                                          capture_output=True, text=True, timeout=8)
                chain = json.loads(response.stdout)
                result["height"], result["pruned"] = chain["blocks"], chain["pruned"]
                config = (output / "zclassic.conf").read_bytes()
                result["implicit_index"] = not any(line.startswith(b"txindex=")
                                                    for line in config.splitlines())
                result["config_preserved"] = config_bytes is None or config_bytes == config
                config_bytes = config
                subprocess.run(rpccommand + ["stop"], check=True, capture_output=True, timeout=8)
                process.wait(timeout=60)
                result["exit"] = process.returncode
                result["pass"] = (result["height"] == 0 and result["pruned"] == prune
                                  and result["implicit_index"] and result["config_preserved"]
                                  and result["exit"] == 0)
            except Exception as error:
                result["error"] = repr(error)
            finally:
                finish(process)
        text = logpath.read_text()
        result["no_blocks_deleted"] = "deleted blk/rev" not in text
        if iteration == 1:
            marker = "transaction index " + ("disabled" if prune else "enabled")
            result["index_restored"] = marker in text
            result["pass"] = result["pass"] and result["index_restored"]
        result["pass"] = result["pass"] and result["no_blocks_deleted"]
        report["runs"].append(result)
        if "error" in result:
            break
    report["pass"] = len(report["runs"]) == 2 and all(run["pass"] for run in report["runs"])
    return report


def explicit_index_conflicts(daemon, output):
    output.mkdir()
    config = output / "zclassic.conf"
    original = b"# Explicit operator choice.\ntxindex=1\n"
    config.write_bytes(original)
    with (output / "startup.log").open("x") as log:
        process = subprocess.Popen(command_for(daemon, output, True) + ["-server=0"],
                                   stdout=log, stderr=subprocess.STDOUT)
        try:
            process.wait(timeout=60)
        finally:
            finish(process)
    text = (output / "startup.log").read_text()
    result = {"exit": process.returncode, "preserved": config.read_bytes() == original,
              "conflict_reported": "Prune mode is incompatible with -txindex" in text}
    result["pass"] = result["exit"] == 1 and result["preserved"] and result["conflict_reported"]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=pathlib.Path, required=True)
    parser.add_argument("--cli", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True)
    daemon, cli = args.daemon.resolve(strict=True), args.cli.resolve(strict=True)
    report = {"pruned": run_mode(daemon, cli, output / "pruned", True),
              "unpruned": run_mode(daemon, cli, output / "unpruned", False),
              "explicit": explicit_index_conflicts(daemon, output / "explicit")}
    report["sanitizer_error"] = any(marker in log.read_text() for log in output.glob("*/*.log")
                                    for marker in ("ERROR: AddressSanitizer", "runtime error:",
                                                   "ERROR: LeakSanitizer"))
    report["pass"] = (all(report[key]["pass"] for key in ("pruned", "unpruned", "explicit"))
                      and not report["sanitizer_error"])
    with (output / "result.json").open("x") as result_file:
        json.dump(report, result_file, indent=2)
        result_file.write("\n")
    print(json.dumps(report, indent=2))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
