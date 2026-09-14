#!/usr/bin/env python3
"""Check the existing script-worker cap before narrowing startup input to int.

Use fresh datadirs and stop at the ordinary local -onlynet validation error.
No block database is opened, and no script-validation work or mining is done.
"""
import argparse
import importlib.util
import json
import pathlib
import re

SPEC = importlib.util.spec_from_file_location(
    "startup_failure", pathlib.Path(__file__).with_name("startup-failure.py"))
STARTUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STARTUP)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    daemon = args.daemon.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True)
    cases = [("one", 1, 0), ("two", 2, 2), ("cap", 64, 64), ("above-cap", 65, 64),
             ("positive-wrap", (1 << 32) + 2, 64), ("signed-maximum", (1 << 63) - 1, 64),
             ("negative-wrap", -(1 << 32) + 2, 0), ("signed-minimum", -(1 << 63), 0)]
    report = {"runs": []}
    for name, requested, expected in cases:
        datadir = output / name
        result = STARTUP.run_once(daemon, datadir, False, requested)
        matches = re.findall(r"Using (\d+) threads for script verification",
                             (datadir / "console.log").read_text())
        result["requested"] = requested
        result["expected"] = expected
        result["configured"] = [int(value) for value in matches]
        result["blocks_unopened"] = not (datadir / "regtest" / "blocks").exists()
        result["pass"] = (result["pass"] and result["configured"] == [expected]
                          and result["blocks_unopened"])
        report["runs"].append(result)
        print(json.dumps(result), flush=True)
    report["pass"] = all(run["pass"] for run in report["runs"])
    with (output / "result.json").open("x") as result_file:
        json.dump(report, result_file, indent=2)
        result_file.write("\n")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
