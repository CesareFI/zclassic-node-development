#!/usr/bin/env python3
"""Check block-request deadlines across peer disconnects with a real daemon.

Uses only loopback fixtures and 100 captured mainnet blocks. Every received
block is validated normally. Artifacts remain in a new private output directory.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import signal
import subprocess
import sys
import time


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=Path, required=True)
    parser.add_argument("--blocks", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    root = args.output_dir.resolve()
    root.mkdir(mode=0o700, parents=True, exist_ok=False)
    directory = Path(__file__).resolve().parent
    bench = load_module("ibd_benchmark", directory / "benchmark-ibd.py")
    helpers = load_module("header_test", directory / "test-header-progress.py")
    fixtures, logs, ports = [], [], {}
    process = None
    try:
        for name in ("stalled", "healthy"):
            ports[name] = helpers.free_port()
            log = (root / (name + ".log")).open("w")
            logs.append(log)
            command = [sys.executable, str(directory / "ibd-local-replay.py"),
                       "--blocks", str(args.blocks.resolve()), "--height", "100",
                       "--port", str(ports[name])]
            if name == "stalled":
                command.append("--stall-blocks")
            fixtures.append(subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT))
            helpers.wait_for(lambda: helpers.listening(ports[name]), 20)
        rpc_port = helpers.free_port()
        results = (root / "measurements.jsonl").open("w")
        errors = (root / "benchmark-errors.log").open("w")
        logs.extend((results, errors))
        process = subprocess.Popen(
            [sys.executable, str(directory / "benchmark-ibd.py"),
             "--daemon", str(args.daemon.resolve()), "--datadir", str(root / "node"),
             "--rpcport", str(rpc_port), "--seconds", "90", "--stop-height", "100",
             "--connect", "0"], stdout=results, stderr=errors)

        def rpc(method, params=None):
            return bench.rpc(rpc_port, root / "node" / ".cookie", method, params)

        def ready():
            try:
                rpc("getblockchaininfo")
                return True
            except (OSError, RuntimeError, ValueError):
                return False

        helpers.wait_for(ready, 60)
        deadlines = []
        stalled_address = "127.0.0.1:" + str(ports["stalled"])
        for cycle in range(3):
            rpc("addnode", [stalled_address, "onetry"])

            def full_queue():
                peers = rpc("getpeerinfo")
                return len(peers) == 1 and len(peers[0].get("inflight", [])) == 100

            helpers.wait_for(full_queue, 15)
            peer = rpc("getpeerinfo")[0]
            assert len(set(peer["inflight"])) == 100
            remaining = peer["blockdownloadtimeout"] - time.time()
            deadlines.append(remaining)
            print(json.dumps({"cycle": cycle, "requests_inflight": 100,
                              "deadline_seconds_remaining": remaining}), flush=True)
            rpc("disconnectnode", [stalled_address])
            helpers.wait_for(lambda: not rpc("getpeerinfo"), 15)

        # All abandoned requests must remain eligible for normal reassignment.
        rpc("addnode", ["127.0.0.1:" + str(ports["healthy"]), "onetry"])
        if process.wait() != 0:
            raise RuntimeError("benchmark failed; inspect retained measurements and logs")
        summary = json.loads((root / "measurements.jsonl").read_text().splitlines()[-1])
        expected = json.loads((root / "healthy.log").read_text().splitlines()[0])["tip"]
        assert summary["target_reached"]
        assert summary["last_sample"]["blocks"] == 100
        assert summary["last_sample"]["bestblockhash"] == expected
        assert summary["log_metrics"]["block_requests"] == 400
        assert summary["log_metrics"]["block_download_timeouts"] == 0
        # One live peer, no other requests: the existing policy allows two
        # 150-second block intervals. Disconnected requests must not extend it.
        assert all(280 < remaining <= 305 for remaining in deadlines), deadlines
        print(json.dumps({"passed": True, "deadlines_seconds": deadlines,
                          "validated_tip": expected}), flush=True)
    finally:
        if process is not None and process.poll() is None:
            process.send_signal(signal.SIGINT)
            process.wait(timeout=135)
        for fixture in fixtures:
            if fixture.poll() is None:
                fixture.terminate()
                fixture.wait(timeout=5)
        for log in logs:
            log.close()


if __name__ == "__main__":
    main()
