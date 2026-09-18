#!/usr/bin/env python3
"""Replay an ordinary tip announcement during initial header synchronization."""
import argparse
import importlib.util
import json
from pathlib import Path
import signal
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=Path, required=True)
    parser.add_argument("--blocks", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--height", type=int, default=640)
    parser.add_argument("--initial-header-limit", type=int, default=160)
    args = parser.parse_args()
    if not 1 <= args.height <= 100000:
        parser.error("height must be 1..100000")
    if not 0 <= args.initial_header_limit <= 160:
        parser.error("initial header limit must be 0..160")
    root = args.output_dir.resolve()
    root.mkdir(mode=0o700, parents=True, exist_ok=False)
    directory = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("header_test", directory / "test-header-progress.py")
    helpers = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helpers)
    port = helpers.free_port()
    process = None
    with (root / "fixture.log").open("w") as log:
        fixture = subprocess.Popen(
            [sys.executable, str(directory / "ibd-local-replay.py"),
             "--blocks", str(args.blocks.resolve()), "--height", str(args.height),
             "--port", str(port), "--announce-tip",
             "--initial-header-limit", str(args.initial_header_limit)], stdout=log, stderr=subprocess.STDOUT)
        try:
            helpers.wait_for(lambda: helpers.listening(port), 20)
            rpc_port = helpers.free_port()
            with (root / "measurements.jsonl").open("w") as results:
                process = subprocess.Popen(
                    [sys.executable, str(directory / "benchmark-ibd.py"),
                     "--daemon", str(args.daemon.resolve()), "--datadir", str(root / "node"),
                     "--rpcport", str(rpc_port), "--seconds", "600", "--stop-height", str(args.height),
                     "--connect", "127.0.0.1:" + str(port)], stdout=results)
                if process.wait() != 0:
                    raise RuntimeError("benchmark failed; inspect retained measurements and logs")
        finally:
            if process is not None and process.poll() is None:
                process.send_signal(signal.SIGINT)
                process.wait(timeout=135)
            if fixture.poll() is None:
                fixture.terminate()
                fixture.wait(timeout=5)
    records = [json.loads(line) for line in (root / "fixture.log").read_text().splitlines()]
    headers_sent = sum(record.get("headers_sent", 0) for record in records)
    requests = sum("headers_sent" in record for record in records)
    summary = json.loads((root / "measurements.jsonl").read_text().splitlines()[-1])
    print(json.dumps({"headers_sent": headers_sent, "header_requests": requests,
                      "bytes_received": summary["last_sample"]["bytes_recv"],
                      "height_seconds": summary["last_sample"]["elapsed"]}), flush=True)
    assert summary["target_reached"]
    assert summary["last_sample"]["bestblockhash"] == records[0]["tip"]
    assert summary["log_metrics"]["block_requests"] == args.height
    assert headers_sent == args.height, "overlapping header streams repeated captured headers"
    assert requests <= args.height // 160 + 2
    print(json.dumps({"passed": True, "validated_tip": records[0]["tip"]}), flush=True)


if __name__ == "__main__":
    main()
