#!/usr/bin/env python3
"""Check HTTP startup resource settings without generating RPC work.

All cases stop at configuration validation in new datadirs. Boundary values are
chosen so the old narrowing bug creates at most four workers, never huge pools.
No block databases, external peers, mining or request campaigns are involved.
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
    parser.add_argument("--case", action="append", default=[], help="Run only this named case (repeatable)")
    args = parser.parse_args()
    daemon = args.daemon.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True)
    cases = [("queue-default", "rpcworkqueue", 16, 16),
             ("queue-zero", "rpcworkqueue", 0, 1),
             ("queue-negative", "rpcworkqueue", -(1 << 63), 1),
             ("queue-int-max", "rpcworkqueue", (1 << 31) - 1, (1 << 31) - 1),
             ("queue-int-over", "rpcworkqueue", 1 << 31, None),
             ("queue-wrap", "rpcworkqueue", (1 << 32) + 2, None),
             ("queue-int64-max", "rpcworkqueue", (1 << 63) - 1, None),
             ("threads-one", "rpcthreads", 1, 1),
             ("threads-negative", "rpcthreads", -(1 << 63), 1),
             ("threads-int-over", "rpcthreads", 1 << 31, None),
             ("threads-wrap", "rpcthreads", (1 << 32) + 2, None),
             ("threads-int64-max", "rpcthreads", (1 << 63) - 1, None)]
    unknown = set(args.case) - {case[0] for case in cases}
    if unknown:
        parser.error("Unknown case: " + ", ".join(sorted(unknown)))
    report = {"runs": []}
    for name, option, value, expected in cases:
        if args.case and name not in args.case:
            continue
        datadir = output / name
        result = STARTUP.run_once(daemon, datadir, True, extra_args=["-" + option + "=" + str(value)])
        text = (datadir / "console.log").read_text()
        pattern = (r"HTTP: creating work queue of depth (-?\d+)" if option == "rpcworkqueue"
                   else r"HTTP: starting (-?\d+) worker threads")
        configured = [int(item) for item in re.findall(pattern, text)]
        result.update(option=option, value=value, configured=configured, expected=expected)
        if expected is None:
            result["expected_error"] = "-" + option + " must not exceed" in text
            result["budget_validated"] = result["expected_error"] and "HTTP: creating work queue" not in text
        else:
            result["budget_validated"] = result["expected_error"] and configured == [expected]
        result["blocks_unopened"] = not (datadir / "regtest" / "blocks").exists()
        result["pass"] = (result["exit"] == 1 and result["error"] is None
                          and result["worker_started"] and result["clean_shutdown"]
                          and result["pid_removed"] and not result["late_threads"]
                          and not result["sanitizer_error"] and result["budget_validated"]
                          and result["blocks_unopened"])
        report["runs"].append(result)
        print(json.dumps(result), flush=True)
    report["pass"] = all(item["pass"] for item in report["runs"])
    with (output / "result.json").open("x") as result_file:
        json.dump(report, result_file, indent=2)
        result_file.write("\n")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
