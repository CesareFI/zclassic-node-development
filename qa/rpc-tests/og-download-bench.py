#!/usr/bin/env python3
"""Controlled OG-block download benchmark in new datadirs, with mining disabled.

The P2P fixture must be supplied with its checksum. Peers simulate a per-getdata
service delay or pipelined response latency and per-peer payload bandwidth.
These are laboratory conditions, not estimates of Internet performance. All blocks undergo normal validation.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import os
import pathlib
import queue
import socket
import threading
import subprocess
import time

SPEC = importlib.util.spec_from_file_location("og_stall", pathlib.Path(__file__).with_name("og-download-stall.py"))
WIRE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WIRE)


class RPCUnavailable(RuntimeError):
    """A bounded local RPC transport timeout, distinct from an RPC error reply."""


class BenchPeer(WIRE.Peer):
    def __init__(self, *args, latency, bandwidth, delay_mode, tcp_nodelay, **kwargs):
        super().__init__(*args, **kwargs)
        self.initial_tcp_nodelay = self.sock.getsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY)
        if tcp_nodelay:
            self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.tcp_nodelay = self.sock.getsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY)
        self.latency, self.bandwidth = latency, bandwidth
        self.delay_mode = delay_mode
        self.send_lock = threading.Lock()
        self.pending = queue.Queue(maxsize=256)
        self.first_request = None
        self.first_block = None
        self.bytes_sent = 0
        self.wire_requests = []

    def send(self, command, payload=b""):
        if command == "block":
            if self.stop_event.wait(len(payload) / self.bandwidth):
                raise InterruptedError("peer stopping")
            if self.first_block is None:
                self.first_block = time.monotonic()
        with self.send_lock:
            super().send(command, payload)
            self.bytes_sent += len(payload) + 24

    def process(self, command, payload):
        if command == b"getdata":
            count, offset = WIRE.compact(payload)
            if count > 50000 or len(payload) != offset + count * 36:
                raise ValueError("invalid getdata")
            for index in range(count):
                begin = offset + index * 36
                if int.from_bytes(payload[begin:begin + 4], "little") == 2:
                    self.wire_requests.append(self.blocks[payload[begin + 4:begin + 36]][0])
            if self.first_request is None:
                self.first_request = time.monotonic()
            if self.deliver:
                if self.delay_mode == "latency":
                    self.pending.put_nowait((time.monotonic() + self.latency, payload))
                    return
                if self.stop_event.wait(self.latency):
                    return
        super().process(command, payload)

    def serve_pending(self):
        try:
            while not self.stop_event.is_set():
                try:
                    due, payload = self.pending.get(timeout=0.2)
                except queue.Empty:
                    continue
                if self.stop_event.wait(max(0, due - time.monotonic())):
                    break
                super().process(b"getdata", payload)
        except Exception as error:
            if not self.stop_event.is_set() and not self.disconnected.is_set():
                self.errors.append(repr(error))

    def run(self):
        worker = None
        if self.deliver and self.delay_mode == "latency":
            worker = threading.Thread(target=self.serve_pending, daemon=True)
            worker.start()
        try:
            super().run()
        finally:
            self.stop_event.set()
            if worker is not None:
                worker.join(timeout=6)
                if worker.is_alive():
                    self.errors.append("response worker did not stop")


def resources(pid):
    fields = pathlib.Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    cpu = (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")
    status = pathlib.Path(f"/proc/{pid}/status").read_text().splitlines()
    memory = {line.split(":", 1)[0]: int(line.split()[1]) for line in status
              if line.startswith(("VmRSS:", "VmHWM:", "VmSwap:"))}
    return {"cpu_seconds": cpu, **memory}


def host_cpu():
    values = [int(value) for value in pathlib.Path("/proc/stat").read_text().splitlines()[0].split()[1:9]]
    total = sum(values)
    return {"total": total, "busy": total - values[3] - values[4] - values[7], "steal": values[7]}


def check_complete(chain, peers, headers, stall, limit):
    assert chain["bestblockhash"] == WIRE.hash256(headers[-1])[::-1].hex()
    counters = chain["blockdownload"]
    assert counters["blocks_in_flight"] == 0, counters
    assert counters["validated_blocks_in_flight"] == 0, counters
    requests = [height for peer in peers for height in peer.wire_requests]
    assert set(requests) == set(range(1, len(headers)))
    duplicates = len(requests) - len(set(requests))
    assert duplicates == (limit if stall else 0), duplicates
    if stall:
        assert peers[0].disconnected.wait(5), "stalled peer remained connected"
        assert peers[0].wire_requests == list(range(1, limit + 1))
        assert not peers[0].delivered
    return duplicates


def window_stall_before_deadline(report):
    initial = (report.get("initial_stalled_peers") or [{}])[0]
    request_timeout = initial.get("block_download_deadline", 0) - initial.get("oldest_request_time", 0)
    disconnected = report.get("a_disconnect_seconds")
    window_stall = any("is stalling block download" in line for line in report["disconnect_events"])
    return bool(window_stall and disconnected is not None and disconnected < request_timeout)


def run(args, blocks, headers, limit, repeat):
    output = args.output / f"limit-{limit}-run-{repeat}"
    output.mkdir(parents=True)
    datadir = output / "datadir"
    datadir.mkdir()
    cli = [str(args.cli), "-datadir=" + str(datadir), f"-rpcport={args.rpcport}"]

    def rpc(method, timeout=5):
        try:
            result = subprocess.run(cli + [f"-rpcclienttimeout={timeout}", method],
                                    capture_output=True, text=True, timeout=timeout + 3)
        except subprocess.TimeoutExpired as error:
            raise RPCUnavailable(method + ": local RPC client exceeded its deadline") from error
        if result.returncode:
            if "couldn't connect to server" in result.stderr:
                raise RPCUnavailable(method + ": " + result.stderr.strip())
            raise RuntimeError(method + ": " + result.stderr.strip())
        return result.stdout.strip() if method == "stop" else json.loads(result.stdout)

    command = [str(args.daemon), "-datadir=" + str(datadir), "-daemon=0", "-server=1",
               "-disablewallet=1", "-gen=0", "-bootstrap=0", "-connect=127.0.0.1:1",
               "-dnsseed=0", "-listenonion=0", "-upnp=0", "-natpmp=0", "-maxconnections=32",
               f"-rpcport={args.rpcport}", f"-port={args.port}", "-bind=127.0.0.1",
               f"-maxblocksinflight={limit}", "-printtoconsole=1"]
    report = {"limit": limit, "repeat": repeat, "stall": args.stall, "pass": False,
              "command": command, "rpc_unavailable_samples": []}
    peers, samples = [], []
    with (output / "daemon.log").open("w") as log:
        daemon = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        report["pid"] = daemon.pid
        try:
            deadline = time.monotonic() + 90
            while True:
                try:
                    assert rpc("getmininginfo")["generate"] is False
                    break
                except RuntimeError:
                    if daemon.poll() is not None or time.monotonic() >= deadline:
                        raise
                    time.sleep(0.2)
            assert rpc("getnetworkinfo")["maxblocksinflight"] == limit
            before = resources(daemon.pid)
            host_before = host_cpu()
            started = time.monotonic()
            for name in ("A", "B"):
                peer = BenchPeer(args.port, name, blocks, headers,
                                 not (args.stall and name == "A"),
                                 latency=args.latency_ms / 1000, bandwidth=args.bandwidth_kib * 1024,
                                 delay_mode=args.delay_mode, tcp_nodelay=args.tcp_nodelay)
                peers.append(peer)
                peer.start()
                if args.stall and name == "A":
                    assert peer.requested.wait(20), "A never received requests"
                    assert len(peer.requests) == limit
                    report["initial_stalled_peers"] = rpc("getpeerinfo")
            deadline = started + args.timeout
            peak_gap, last_progress, longest_no_progress, previous_height = 0, started, 0, 0
            while time.monotonic() < deadline:
                try:
                    chain = rpc("getblockchaininfo")
                except RPCUnavailable as error:
                    report["rpc_unavailable_samples"].append({"elapsed": time.monotonic() - started,
                                                              "error": str(error)})
                    if daemon.poll() is not None or any(peer.errors for peer in peers):
                        raise
                    time.sleep(args.sample_ms / 1000)
                    continue
                now, usage = time.monotonic(), resources(daemon.pid)
                samples.append({"elapsed": now - started, "height": chain["blocks"],
                                "download": chain["blockdownload"], **usage})
                delivered_tip = max((max(peer.delivered, default=0) for peer in peers), default=0)
                peak_gap = max(peak_gap, delivered_tip - chain["blocks"])
                if chain["blocks"] != previous_height:
                    longest_no_progress = max(longest_no_progress, now - last_progress)
                    previous_height, last_progress = chain["blocks"], now
                if any(peer.errors for peer in peers):
                    raise RuntimeError([peer.errors for peer in peers])
                if chain["blocks"] == len(headers) - 1:
                    duplicates = check_complete(chain, peers, headers, args.stall, limit)
                    assert daemon.poll() is None
                    elapsed = now - started
                    cpu = usage["cpu_seconds"] - before["cpu_seconds"]
                    host_after = host_cpu()
                    host_busy = (host_after["busy"] - host_before["busy"]) / os.sysconf("SC_CLK_TCK")
                    host_total = (host_after["total"] - host_before["total"]) / os.sysconf("SC_CLK_TCK")
                    report.update({"pass": True, "height": chain["blocks"], "elapsed_seconds": elapsed,
                                   "blocks_per_second": chain["blocks"] / elapsed,
                                   "cpu_seconds": cpu, "cpu_percent_one_core": 100 * cpu / elapsed,
                                   "host_busy_percent": 100 * host_busy / host_total,
                                   "host_steal_seconds": (host_after["steal"] - host_before["steal"]) / os.sysconf("SC_CLK_TCK"),
                                   "other_host_cpu_seconds": max(0, host_busy - cpu),
                                   "peak_rss_kib": max(sample.get("VmHWM", 0) for sample in samples),
                                   "peak_swap_kib": max(sample.get("VmSwap", 0) for sample in samples),
                                   "p2p_totals": rpc("getnettotals"),
                                   "duplicate_requests": duplicates,
                                   "abandoned_requests": len(peers[0].wire_requests) if args.stall else 0,
                                   "final_download_counters": chain["blockdownload"],
                                   "max_served_height_ahead_of_active": peak_gap,
                                   "longest_observed_no_progress_seconds": longest_no_progress,
                                   "a_disconnect_seconds": peers[0].disconnect_age,
                                   "no_restart": True})
                    break
                time.sleep(args.sample_ms / 1000)
            else:
                raise TimeoutError("sync did not finish before benchmark deadline")
        except Exception as error:
            report["error"] = repr(error)
            try:
                report["last_chain"] = rpc("getblockchaininfo")
                report["last_peers"] = rpc("getpeerinfo")
            except Exception as diagnostic_error:
                report["diagnostic_error"] = repr(diagnostic_error)
        finally:
            for peer in peers:
                peer.finish()
            if any(peer.errors or peer.is_alive() for peer in peers):
                report["pass"] = False
                report["peer_shutdown_error"] = "peer errors or unfinished thread"
            try:
                report["stop"] = rpc("stop", timeout=60)
                report["exit"] = daemon.wait(timeout=90)
                report["pass"] = report["pass"] and report["exit"] == 0
            except Exception as error:
                report["pass"], report["shutdown_error"] = False, repr(error)
            report["peers"] = [{"requests": len(peer.wire_requests), "delivered": len(peer.delivered),
                                "bytes_sent": peer.bytes_sent, "errors": peer.errors,
                                "initial_tcp_nodelay": peer.initial_tcp_nodelay,
                                "tcp_nodelay": peer.tcp_nodelay,
                                "header_messages": peer.header_messages,
                                "first_response_seconds": (peer.first_block - peer.first_request
                                    if peer.first_block is not None and peer.first_request is not None else None)}
                               for peer in peers]
    report["disconnect_events"] = [line for line in (output / "daemon.log").read_text().splitlines()
                                   if "is stalling block download, disconnecting" in line
                                   or "Timeout downloading block" in line]
    if args.require_window_stall:
        report["window_stall_before_request_timeout"] = window_stall_before_deadline(report)
        if not report["window_stall_before_request_timeout"]:
            report["pass"] = False
            report["window_stall_error"] = "required window stall did not precede the request deadline"
    (output / "samples.json").write_text(json.dumps(samples, indent=2) + "\n")
    (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key not in ("command", "peers")}), flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--fixture", required=True, type=pathlib.Path)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--daemon", type=pathlib.Path, default=WIRE.ROOT / "src/zclassicd")
    parser.add_argument("--cli", type=pathlib.Path, default=WIRE.ROOT / "src/zclassic-cli")
    parser.add_argument("--limits", nargs="+", type=int, choices=(16, 32, 64, 128), default=[16, 32, 64, 128])
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--stall", action="store_true")
    parser.add_argument("--require-window-stall", action="store_true",
                        help="Require download-window recovery before A's ordinary request deadline")
    parser.add_argument("--tcp-nodelay", action="store_true",
                        help="Disable Nagle on fixture peers, matching the daemon's TCP setting")
    parser.add_argument("--delay-mode", choices=("latency", "service"), default="latency",
                        help="Pipelined block-response latency, or serial per-getdata service delay")
    parser.add_argument("--latency-ms", type=float, default=100)
    parser.add_argument("--bandwidth-kib", type=float, default=1024)
    parser.add_argument("--sample-ms", type=float, default=100)
    parser.add_argument("--timeout", type=float, default=600)
    parser.add_argument("--port", type=int, default=18643)
    parser.add_argument("--rpcport", type=int, default=18653)
    args = parser.parse_args()
    timing = (args.bandwidth_kib, args.latency_ms, args.sample_ms, args.timeout)
    if not all(math.isfinite(value) for value in timing):
        parser.error("timing and bandwidth must be finite")
    if args.repeat < 1 or args.bandwidth_kib <= 0 or args.latency_ms < 0 or args.sample_ms < 20 or args.timeout <= 0:
        parser.error("invalid repeat, bandwidth, latency, sample interval or timeout")
    args.output = args.output.resolve()
    args.output.mkdir(parents=True)
    blocks, headers = WIRE.fixture(args.fixture, args.sha256)
    if args.require_window_stall and (not args.stall or len(headers) <= 4097):
        parser.error("--require-window-stall needs --stall and blocks through at least height 4097")
    manifest = {"fixture_sha256": args.sha256, "blocks": len(headers),
                "daemon_sha256": hashlib.sha256(args.daemon.read_bytes()).hexdigest(),
                "delay_mode": args.delay_mode, "delay_ms_per_getdata": args.latency_ms,
                "bandwidth_kib_per_peer": args.bandwidth_kib,
                "harness_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
                "peer_harness_sha256": hashlib.sha256(pathlib.Path(WIRE.__file__).read_bytes()).hexdigest(),
                "sample_ms": args.sample_ms}
    manifest.update({"limits": args.limits, "repeat": args.repeat, "stall": args.stall,
                     "require_window_stall": args.require_window_stall,
                     "fixture_peer_tcp_nodelay_requested": args.tcp_nodelay,
                     "timeout_seconds": args.timeout, "request_counting": "on getdata receipt"})
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    for repeat in range(args.repeat):
        limits = args.limits if repeat % 2 == 0 else list(reversed(args.limits))
        for limit in limits:
            if not run(args, blocks, headers, limit, repeat)["pass"]:
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
