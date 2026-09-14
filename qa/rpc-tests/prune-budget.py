#!/usr/bin/env python3
"""Check pruning-budget validation before any block database is opened.

Each case uses a fresh datadir. An invalid local -onlynet option deliberately
stops valid budgets later in startup, before networking or database loading.
No block files, wallets, mining, or production data are involved.
"""
import argparse
import json
import pathlib
import re
import subprocess

from pidfile import finish


def run_case(daemon, datadir, value, expected_error, expected_target):
    datadir.mkdir()
    command = [str(daemon), "-datadir=" + str(datadir), "-regtest=1", "-daemon=0",
               "-server=0", "-disablewallet=1", "-txindex=0", "-gen=0", "-bootstrap=0",
               "-listen=0", "-connect=127.0.0.1:1", "-dnsseed=0", "-listenonion=0",
               "-upnp=0", "-natpmp=0", "-dbcache=4", "-par=1",
               "-printtoconsole=1", "-onlynet=invalid", "-prune=" + str(value)]
    logpath = datadir / "console.log"
    error = None
    with logpath.open("x") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            process.wait(timeout=60)
        except subprocess.TimeoutExpired as failure:
            error = repr(failure)
        finally:
            finish(process)
    text = logpath.read_text()
    targets = [int(item) for item in re.findall(r"Prune configured to target (\d+)MiB", text)]
    expected_targets = [] if expected_target is None else [expected_target]
    result = {"value": value, "exit": process.returncode, "error": error,
              "expected_error": expected_error in text, "targets": targets,
              "expected_targets": expected_targets,
              "blocks_unopened": not (datadir / "regtest" / "blocks").exists(),
              "sanitizer_error": any(marker in text for marker in
                                     ("ERROR: AddressSanitizer", "runtime error:",
                                      "ERROR: LeakSanitizer"))}
    result["pass"] = (result["exit"] == 1 and error is None and result["expected_error"]
                      and targets == expected_targets and result["blocks_unopened"]
                      and not result["sanitizer_error"])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    daemon = args.daemon.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True)
    valid = "Unknown network specified in -onlynet"
    negative = "Prune cannot be configured with a negative value"
    too_large = "Prune configured above the maximum"
    maximum = ((1 << 63) - 1) // (1024 * 1024)
    cases = [("disabled", 0, valid, None),
             ("minimum", 550, valid, 550),
             ("below-minimum", 549, "Prune configured below the minimum", None),
             ("negative", -1, negative, None),
             ("negative-wrap", -(1 << 44) + 550, negative, None),
             ("maximum", maximum, valid, maximum),
             ("overflow", 1 << 43, too_large, None),
             ("positive-wrap", (1 << 44) + 550, too_large, None),
             ("signed-maximum", (1 << 63) - 1, too_large, None),
             ("signed-minimum", -(1 << 63), negative, None)]
    report = {"runs": []}
    for name, value, expected_error, expected_target in cases:
        result = run_case(daemon, output / name, value, expected_error, expected_target)
        report["runs"].append(result)
        print(json.dumps(result), flush=True)
    report["pass"] = all(case["pass"] for case in report["runs"])
    with (output / "result.json").open("x") as result_file:
        json.dump(report, result_file, indent=2)
        result_file.write("\n")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
