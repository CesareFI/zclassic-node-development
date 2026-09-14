#!/usr/bin/env python3
"""Import and reindex the original 129-block fixture in a newly created datadir.

Each file operation is followed by an ordinary RPC restart to verify the exact
validated tip and empty download accounting. Reindex is confined to this test's
new datadir. Wallets, mining, listening and external peers remain disabled.
"""
import argparse
import hashlib
import importlib.util
import json
import pathlib
import subprocess

SPEC = importlib.util.spec_from_file_location(
    "startup_cancel", pathlib.Path(__file__).with_name("startup-cancel.py"))
STARTUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STARTUP)

FIXTURE_SHA = "4ae8e7c4a2b2fb5b925ecc18752bf517dad39dd0a965a8c44d4fee29360ba2b6"
EXPECTED = {"blocks": 129,
            "bestblockhash": "0000d77872aabab70015f08e2d138a35293ad0e5b671a5b6e8cad38c1b63aff4"}


def import_and_stop(command, logpath, marker):
    error = None
    with logpath.open("x") as log:
        process = subprocess.Popen(command + ["-server=0", "-stopafterblockimport=1"],
                                   stdout=log, stderr=subprocess.STDOUT)
        try:
            process.wait(timeout=120)
        except subprocess.TimeoutExpired as failure:
            error = repr(failure)
        finally:
            STARTUP.finish(process)
    text = logpath.read_text()
    _, _, shutdown = text.partition("Shutdown: In progress...")
    result = {"exit": process.returncode, "error": error, "import_finished": marker in text,
              "import_stopped": "Stopping after block import" in text,
              "clean_shutdown": "Shutdown: done" in shutdown,
              "late_workers": [line for line in shutdown.splitlines()
                               if "thread start" in line or "thread interrupt" in line],
              "sanitizer_error": STARTUP.sanitizer_error(text)}
    result["pass"] = (result["exit"] == 0 and error is None and result["import_finished"]
                      and result["import_stopped"] and result["clean_shutdown"]
                      and not result["late_workers"] and not result["sanitizer_error"])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=pathlib.Path, required=True)
    parser.add_argument("--cli", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    daemon = args.daemon.resolve(strict=True)
    cli = args.cli.resolve(strict=True)
    fixture = pathlib.Path(__file__).resolve().parents[2] / "src/test/data/zclassic-download-130.dat"
    if hashlib.sha256(fixture.read_bytes()).hexdigest() != FIXTURE_SHA:
        parser.error("Unexpected block fixture digest")
    output = args.output.resolve()
    output.mkdir(parents=True)  # Refuse to reuse an output or an existing datadir.
    datadir = output / "datadir"
    datadir.mkdir()
    command = [str(daemon), "-datadir=" + str(datadir), "-daemon=0", "-disablewallet=1",
               "-gen=0", "-bootstrap=0", "-listen=0", "-connect=127.0.0.1:1",
               "-dnsseed=0", "-listenonion=0", "-upnp=0", "-natpmp=0", "-dbcache=4",
               "-par=2", "-maxconnections=0", "-printtoconsole=1", "-checkblocks=0",
               "-checklevel=4"]
    report = {"fixture_sha256": FIXTURE_SHA, "runs": []}
    for name, options, marker in (
            ("import", ["-loadblock=" + str(fixture)], "Loaded 129 blocks from external file"),
            ("reindex", ["-reindex=1"], "Reindexing finished")):
        result = import_and_stop(command + options, output / (name + ".log"), marker)
        result["case"] = name
        report["runs"].append(result)
        print(json.dumps(result), flush=True)
        if not result["pass"]:
            break
        result = STARTUP.restart(command, cli, datadir, EXPECTED, output / (name + "-restart.log"))
        result["case"] = name + "-restart"
        report["runs"].append(result)
        print(json.dumps(result), flush=True)
        if not result["pass"]:
            break
    report["pass"] = len(report["runs"]) == 4 and all(item["pass"] for item in report["runs"])
    with (output / "result.json").open("x") as result_file:
        json.dump(report, result_file, indent=2)
        result_file.write("\n")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
