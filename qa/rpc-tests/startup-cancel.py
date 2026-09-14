#!/usr/bin/env python3
"""Cancel verification of a copied test chain, then check a normal restart.

--fixture-output must name a completed og-header-discovery.py test output, whose
datadir is copied without modifying the source. Only the new copy is started.
Wallets, mining, listening and external peers remain disabled.
"""
import argparse
import json
import pathlib
import shutil
import socket
import subprocess
import time

from maxconnections import wait_for_rpc
from pidfile import finish


def cancel_verification(command, logpath):
    cancelled = False
    error = None
    with logpath.open("x") as log:
        process = subprocess.Popen(command + ["-server=0"], stdout=log,
                                   stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 90
            while process.poll() is None and time.monotonic() < deadline:
                if "init message: Verifying blocks..." in logpath.read_text():
                    cancelled = True
                    process.terminate()
                    break
                time.sleep(0.01)
            process.wait(timeout=60)
        except Exception as failure:
            error = repr(failure)
        finally:
            finish(process)
    text = logpath.read_text()
    _, _, shutdown = text.partition("Shutdown: In progress...")
    result = {"exit": process.returncode, "error": error, "cancelled": cancelled,
              "partial_init_stopped": "Shutdown requested. Exiting." in text,
              "clean_shutdown": "Shutdown: done" in shutdown,
              "late_workers": [line for line in shutdown.splitlines()
                               if "scheduler thread" in line],
              "sanitizer_error": sanitizer_error(text)}
    result["pass"] = (cancelled and error is None and result["exit"] == 1
                      and result["partial_init_stopped"] and result["clean_shutdown"]
                      and not result["late_workers"] and not result["sanitizer_error"])
    return result


def sanitizer_error(text):
    return any(marker in text for marker in
               ("ERROR: AddressSanitizer", "runtime error:", "ERROR: LeakSanitizer"))


def restart(command, cli, datadir, expected, logpath):
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    rpccommand = [str(cli), "-datadir=" + str(datadir), "-rpcport=" + str(port),
                  "-rpcclienttimeout=5"]
    report = {"pass": False}
    with logpath.open("x") as log:
        process = subprocess.Popen(command + ["-server=1", "-rpcbind=127.0.0.1",
                                              "-rpcport=" + str(port)],
                                   stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_for_rpc(process, rpccommand)
            result = subprocess.run(rpccommand + ["getblockchaininfo"], capture_output=True,
                                    text=True, check=True, timeout=8)
            chain = json.loads(result.stdout)
            report["height"] = chain["blocks"]
            report["tip"] = chain["bestblockhash"]
            report["downloads"] = chain["blockdownload"]
            subprocess.run(rpccommand + ["stop"], capture_output=True, check=True, timeout=8)
            process.wait(timeout=60)
            report["exit"] = process.returncode
            report["pass"] = (chain["blocks"] == expected["blocks"]
                              and chain["bestblockhash"] == expected["bestblockhash"]
                              and all(chain["blockdownload"][field] == 0 for field in
                                      ("blocks_in_flight", "validated_blocks_in_flight",
                                       "header_sync_peers")) and process.returncode == 0)
        except Exception as failure:
            report["error"] = repr(failure)
        finally:
            finish(process)
    text = logpath.read_text()
    report["sanitizer_error"] = sanitizer_error(text)
    report["pass"] &= "Shutdown: done" in text and not report["sanitizer_error"]
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=pathlib.Path, required=True)
    parser.add_argument("--cli", type=pathlib.Path, required=True)
    parser.add_argument("--fixture-output", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    source = args.fixture_output.resolve(strict=True)
    fixture = json.loads((source / "result.json").read_text())
    if not fixture["pass"] or fixture["exit"] != 0 or fixture["chain"]["blocks"] != 129:
        parser.error("fixture output must contain a successful, stopped 129-block test")
    daemon = args.daemon.resolve(strict=True)
    cli = args.cli.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True)
    datadir = output / "datadir"
    shutil.copytree(source / "datadir", datadir)
    command = [str(daemon), "-datadir=" + str(datadir), "-daemon=0",
               "-disablewallet=1", "-gen=0", "-bootstrap=0", "-listen=0",
               "-connect=127.0.0.1:1", "-dnsseed=0", "-listenonion=0",
               "-upnp=0", "-natpmp=0", "-dbcache=4", "-par=2",
               "-printtoconsole=1", "-checkblocks=0", "-checklevel=4"]
    report = {"cancel": cancel_verification(command, output / "cancel.log")}
    report["restart"] = restart(command, cli, datadir, fixture["chain"], output / "restart.log")
    report["pass"] = report["cancel"]["pass"] and report["restart"]["pass"]
    with (output / "result.json").open("x") as result_file:
        json.dump(report, result_file, indent=2)
        result_file.write("\n")
    print(json.dumps(report, indent=2))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
