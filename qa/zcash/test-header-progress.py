#!/usr/bin/env python3
"""Real-daemon header-progress regression using only loopback replay peers.

Requires a stopped scratch capture containing at least 100 mainnet blocks.
Artifacts remain in --output-dir. No wallets or validation overrides are used.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time


def free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def wait_for(predicate, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise RuntimeError("test setup did not become ready")


def listening(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.2):
            return True
    except OSError:
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=Path, required=True)
    parser.add_argument("--blocks", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--scenario", choices=("failover", "sole", "healthy", "unready"), default="failover")
    args = parser.parse_args()
    root = args.output_dir.resolve()
    root.mkdir(mode=0o700, parents=True, exist_ok=False)
    directory = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("ibd_benchmark", directory / "benchmark-ibd.py")
    benchmark = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(benchmark)
    fixtures = []
    logs = []
    process = None
    try:
        for name in ("silent", "healthy"):
            port = free_port()
            log = (root / (name + ".log")).open("w")
            logs.append(log)
            command = [sys.executable, str(directory / "ibd-local-replay.py"),
                       "--blocks", str(args.blocks.resolve()), "--height", "100", "--port", str(port)]
            if name == "silent":
                command.append("--stall-headers")
            elif args.scenario == "unready":
                command.append("--withhold-verack")
            fixture = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            fixtures.append(fixture)
            wait_for(lambda: listening(port), 20)
            if name == "silent":
                silent_port = port
            else:
                healthy_port = port
        rpc_port = free_port()
        results = (root / "measurements.jsonl").open("w")
        errors = (root / "benchmark-errors.log").open("w")
        logs.extend((results, errors))
        command = [sys.executable, str(directory / "benchmark-ibd.py"),
                   "--daemon", str(args.daemon.resolve()), "--datadir", str(root / "node"),
                   "--rpcport", str(rpc_port), "--seconds", "90",
                   "--connect", "127.0.0.1:" + str(healthy_port if args.scenario == "healthy" else silent_port)]
        if args.scenario not in ("sole", "unready"):
            command.extend(("--stop-height", "100"))
        process = subprocess.Popen(command, stdout=results, stderr=errors)
        if args.scenario in ("failover", "unready"):
            # Establish ownership before adding the healthy peer, avoiding a
            # race between simultaneous version handshakes in the fixture.
            wait_for(lambda: '"headers_withheld": true' in (root / "silent.log").read_text(), 60)
            benchmark.rpc(rpc_port, root / "node" / ".cookie", "addnode",
                          ["127.0.0.1:" + str(healthy_port), "onetry"])
        result = process.wait()
        if result != 0:
            raise RuntimeError("benchmark failed; inspect retained measurements and logs")
        summary = json.loads((root / "measurements.jsonl").read_text().splitlines()[-1])
        stalls = summary["log_metrics"]["header_stall_disconnects"]
        if args.scenario in ("sole", "unready"):
            assert summary["last_sample"]["blocks"] == 0
            assert summary["last_sample"]["peers"] == (1 if args.scenario == "sole" else 2)
            assert stalls == 0
        else:
            expected = json.loads((root / "healthy.log").read_text().splitlines()[0])["tip"]
            assert summary["last_sample"]["blocks"] == 100
            assert summary["last_sample"]["bestblockhash"] == expected
            assert summary["target_reached"]
            assert stalls == (1 if args.scenario == "failover" else 0)
            if args.scenario == "failover":
                assert 60 <= summary["startup_to_first_header"] < 85
        print(json.dumps({"scenario": args.scenario, "passed": True,
                          "first_header_seconds": summary["startup_to_first_header"],
                          "header_stall_disconnects": stalls}), flush=True)
    finally:
        if process is not None and process.poll() is None:
            # SIGINT unwinds the benchmark's finally block, which cleanly stops
            # its daemon; never kill the wrapper and orphan a database writer.
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
