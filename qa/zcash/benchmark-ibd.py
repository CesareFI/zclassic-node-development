#!/usr/bin/env python3
"""Measure ordinary, fully validating IBD in a new, retained scratch datadir.

JSON lines go to stdout; daemon output and chain data stay in --datadir.
No wallet, snapshot import, or validation overrides are enabled.
"""

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import http.client
import json
import math
import os
import re
from pathlib import Path
import signal
import subprocess
import time


def rpc(port, cookie, method):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        auth = base64.b64encode(cookie.read_bytes().strip()).decode("ascii")
        connection.request("POST", "/", json.dumps({"id": 1, "method": method,
                                                  "params": []}),
                           {"Authorization": "Basic " + auth})
        response = json.loads(connection.getresponse().read())
        if response.get("error"):
            raise RuntimeError("RPC unavailable")
        return response["result"]
    finally:
        connection.close()


def resources(pid):
    """Linux process totals; disk bytes exclude reads satisfied by page cache."""
    result = {}
    try:
        proc = Path("/proc") / str(pid)
        stat = (proc / "stat").read_text().rsplit(")", 1)[1].split()
        result["cpu_seconds"] = (int(stat[11]) + int(stat[12])) / os.sysconf("SC_CLK_TCK")
        result["rss_bytes"] = int(stat[21]) * os.sysconf("SC_PAGE_SIZE")
        for line in (proc / "io").read_text().splitlines():
            key, value = line.split(":")
            if key in ("read_bytes", "write_bytes", "syscr", "syscw"):
                result[key] = int(value)
    except (OSError, ValueError, IndexError):
        pass
    return result


def emit(record):
    print(json.dumps(record, sort_keys=True), flush=True)


def log_metrics(path, start_wall):
    result = {"block_requests": 0, "block_download_timeouts": 0,
              "block_stall_disconnects": 0, "header_stall_disconnects": 0}
    markers = {"startup_to_first_version_log": "receive version message:",
               "startup_to_first_header_request_log": "initial getheaders",
               "startup_to_first_block_request_log": "Requesting block "}
    with path.open(errors="replace") as log:
        for line in log:
            for key, marker in markers.items():
                if key not in result and marker in line:
                    try:
                        timestamp = datetime.strptime(line[:19], "%Y-%m-%d %H:%M:%S")
                        result[key] = timestamp.replace(tzinfo=timezone.utc).timestamp() - start_wall
                    except ValueError:
                        pass
            result["block_requests"] += bool(re.search(r"Requesting block [0-9a-f]{64}", line))
            result["block_download_timeouts"] += "Timeout downloading block " in line
            result["block_stall_disconnects"] += "is stalling block download" in line
            result["header_stall_disconnects"] += "is stalling header download" in line
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=Path, required=True)
    parser.add_argument("--datadir", type=Path, required=True,
                        help="new directory; retained for audit/resume")
    parser.add_argument("--rpcport", type=int, default=18232)
    parser.add_argument("--seconds", type=float, default=180)
    parser.add_argument("--interval", type=float, default=1)
    parser.add_argument("--stop-height", type=int, default=0,
                        help="stop early after validating this height (0 disables)")
    parser.add_argument("--connect", action="append", default=[],
                        help="optional ordinary P2P peer; repeat for multiple peers")
    args = parser.parse_args()
    if (not math.isfinite(args.seconds) or not math.isfinite(args.interval) or
            args.seconds <= 0 or args.interval <= 0 or args.stop_height < 0 or
            not 1 <= args.rpcport <= 65535):
        parser.error("duration/interval must be finite and positive; height/port must be valid")
    daemon = args.daemon.resolve(strict=True)
    datadir = args.datadir.resolve()
    # Never reuse or overwrite a wallet, configuration, or existing chainstate.
    datadir.mkdir(mode=0o700, parents=True, exist_ok=False)
    # This legacy daemon otherwise creates a config with a static RPC password.
    (datadir / "zclassic.conf").touch(mode=0o600)
    with daemon.open("rb") as binary:
        digest = hashlib.file_digest(binary, "sha256").hexdigest()
    command = [str(daemon), "-datadir=" + str(datadir), "-server=1", "-daemon=0",
               "-disablewallet=1", "-listen=0", "-discover=0", "-upnp=0",
               "-bootstrap=0", "-bootstrapserve=0", "-printtoconsole=0",
               "-debug=net", "-debuglogfile=1", "-logtimestamps=1", "-rpcbind=127.0.0.1",
               "-rpcport=" + str(args.rpcport)]
    command.extend("-connect=" + peer for peer in args.connect)
    first_peer = first_header = first_block = None
    previous = None
    failures = 0
    start = time.monotonic()
    start_wall = time.time()
    emit({"kind": "start", "binary_sha256": digest, "command": command,
          "wall_time": start_wall, "requested_seconds": args.seconds,
          "stop_height": args.stop_height})
    with (datadir / "console.log").open("wb") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
        try:
            while time.monotonic() - start < args.seconds:
                elapsed = time.monotonic() - start
                record = {"kind": "sample", "elapsed": elapsed,
                          **resources(process.pid)}
                if process.poll() is not None:
                    raise RuntimeError("daemon exited; inspect scratch console.log/debug.log")
                try:
                    chain = rpc(args.rpcport, datadir / ".cookie", "getblockchaininfo")
                    peers = rpc(args.rpcport, datadir / ".cookie", "getpeerinfo")
                    network = rpc(args.rpcport, datadir / ".cookie", "getnettotals")
                    blocks, headers = chain["blocks"], chain["headers"]
                    inflight = [height for p in peers for height in p.get("inflight", [])]
                    record.update(blocks=blocks, headers=headers, peers=len(peers),
                                  bytes_recv=network["totalbytesrecv"],
                                  bytes_sent=network["totalbytessent"],
                                  bestblockhash=chain["bestblockhash"],
                                  inflight=len(inflight),
                                  repeated_inflight_heights=len(inflight) - len(set(inflight)),
                                  peers_with_inflight=sum(bool(p.get("inflight")) for p in peers))
                    if peers and first_peer is None:
                        first_peer = elapsed
                    if headers > 0 and first_header is None:
                        first_header = elapsed
                    if blocks > 0 and first_block is None:
                        first_block = elapsed
                    if previous:
                        dt = elapsed - previous["elapsed"]
                        record.update(headers_per_second=(headers - previous["headers"]) / dt,
                                      blocks_per_minute=60 * (blocks - previous["blocks"]) / dt,
                                      recv_mb_per_second=(record["bytes_recv"] - previous["bytes_recv"]) / dt / 1e6)
                    previous = record
                except (OSError, RuntimeError, ValueError, http.client.HTTPException):
                    failures += 1
                    record["rpc_unavailable"] = True
                emit(record)
                if args.stop_height and record.get("blocks", 0) >= args.stop_height:
                    break
                time.sleep(min(args.interval, max(0, args.seconds - (time.monotonic() - start))))
        finally:
            stop_start = time.monotonic()
            if process.poll() is None:
                process.send_signal(signal.SIGTERM)
                try:
                    process.wait(timeout=120)
                except subprocess.TimeoutExpired:
                    # Leave the node performing its clean shutdown; never SIGKILL a database writer.
                    emit({"kind": "shutdown_pending", "pid": process.pid})
                    raise
            emit({"kind": "summary", "elapsed": time.monotonic() - start,
                  "startup_to_first_peer": first_peer,
                  "startup_to_first_header": first_header,
                  "startup_to_first_block": first_block,
                  "rpc_unavailable_samples": failures,
                  "shutdown_seconds": time.monotonic() - stop_start,
                  "exit_code": process.returncode,
                  "target_reached": bool(previous and previous["blocks"] >= args.stop_height)
                  if args.stop_height else None,
                  "log_metrics": log_metrics(datadir / "debug.log", start_wall)
                  if (datadir / "debug.log").exists() else {},
                  "last_sample": previous})
    if process.returncode:
        raise SystemExit(process.returncode)
    if args.stop_height and (not previous or previous["blocks"] < args.stop_height):
        raise SystemExit("target height was not reached before the deadline")


if __name__ == "__main__":
    main()
