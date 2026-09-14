#!/usr/bin/env python3
"""Check ordinary stop-after-import startup and shutdown in new regtest datadirs.

An empty import can finish before the startup function returns. Every run must
exit successfully and finish the main thread group before database shutdown.
Wallets, RPC, listening, mining, bootstrap downloads, and external peers are off.
"""
import argparse
import hashlib
import json
import pathlib
import subprocess


def run_once(daemon, datadir, invalid_config=False):
    datadir.mkdir()
    command = [str(daemon), "-datadir=" + str(datadir), "-regtest=1",
               "-daemon=0", "-server=0", "-disablewallet=1", "-gen=0",
               "-bootstrap=0", "-connect=127.0.0.1:1", "-listen=0",
               "-dnsseed=0", "-listenonion=0", "-upnp=0", "-natpmp=0",
               "-dbcache=4", "-par=1", "-maxconnections=0",
               "-printtoconsole=1", "-stopafterblockimport=1"]
    if invalid_config:
        command.append("-maxblocksinflight=0")
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
    late_threads = [line for line in shutdown.splitlines()
                    if "thread start" in line or "thread interrupt" in line]
    result = {"exit": process.returncode, "error": error,
              "invalid_config": invalid_config,
              "import_stopped": "Stopping after block import" in text,
              "initialized": "init message: Done loading" in text,
              "clean_shutdown": bool(separator) and "Shutdown: done" in shutdown,
              "late_threads": late_threads,
              "sanitizer_error": any(marker in text for marker in
                                     ("ERROR: AddressSanitizer", "runtime error:",
                                      "ERROR: LeakSanitizer"))}
    expected_exit = 1 if invalid_config else 0
    if invalid_config:
        expected_state = (not result["initialized"] and not result["import_stopped"]
                          and "-maxblocksinflight must be an integer" in text)
    else:
        expected_state = result["import_stopped"] and result["initialized"]
    result["pass"] = (result["exit"] == expected_exit and result["error"] is None
                      and expected_state
                      and result["clean_shutdown"] and not result["late_threads"]
                      and not result["sanitizer_error"])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--repeat", type=int, default=8)
    args = parser.parse_args()
    if not 1 <= args.repeat <= 32:
        parser.error("--repeat must be from 1 to 32")
    daemon = args.daemon.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True)  # Never reuse an existing output or datadir.
    digest = hashlib.sha256()
    with daemon.open("rb") as binary:
        for chunk in iter(lambda: binary.read(1024 * 1024), b""):
            digest.update(chunk)
    report = {"daemon": str(daemon), "sha256": digest.hexdigest(), "runs": []}
    for index in range(args.repeat):
        result = run_once(daemon, output / str(index))
        report["runs"].append(result)
        print(json.dumps(result), flush=True)
    report["runs"].append(run_once(daemon, output / "invalid-config", invalid_config=True))
    print(json.dumps(report["runs"][-1]), flush=True)
    report["pass"] = all(result["pass"] for result in report["runs"])
    with (output / "result.json").open("x") as result_file:
        json.dump(report, result_file, indent=2)
        result_file.write("\n")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
