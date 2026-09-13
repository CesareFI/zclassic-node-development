#!/usr/bin/env python3
"""Read-only sync/download report using the local CLI; never restarts the node."""
import argparse
import datetime
import json
import math
import pathlib
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIELDS = (
    "id", "inbound", "services", "version", "subver", "startingheight",
    "synced_headers", "synced_blocks", "header_sync_started", "block_download_stopped",
    "preferred_download", "blocks_in_flight", "validated_blocks_in_flight",
    "inflight", "oldest_block_request", "oldest_request_time", "oldest_request_age",
    "block_download_deadline", "block_download_timeout_remaining", "block_stall_duration",
)


def snapshot(cli):
    def rpc(method):
        result = subprocess.run(cli + [method], capture_output=True, text=True, timeout=15)
        if result.returncode:
            raise RuntimeError(method + ": " + result.stderr.strip())
        return json.loads(result.stdout)

    chain = rpc("getblockchaininfo")
    peers = rpc("getpeerinfo")
    download = chain.get("blockdownload", {})
    peer_counts = next((peer for peer in peers if "global_blocks_in_flight" in peer), {})
    return {
        "time": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "active_height": chain["blocks"], "header_height": chain["headers"],
        "ibd": chain.get("initialblockdownload"),
        "inbound": sum(bool(peer["inbound"]) for peer in peers),
        "outbound": sum(not peer["inbound"] for peer in peers),
        "download_peers": [peer["id"] for peer in peers
                           if peer.get("blocks_in_flight", len(peer.get("inflight", []))) > 0],
        # Prefer counts from the same snapshot as the displayed peer rows.
        # Keep blockchain RPC counters available when no peers are connected.
        "global_blocks_in_flight": peer_counts.get("global_blocks_in_flight", download.get("blocks_in_flight")),
        "global_validated_blocks_in_flight": peer_counts.get("global_validated_blocks_in_flight", download.get("validated_blocks_in_flight")),
        "preferred_download_peers": download.get("preferred_peers"),
        "header_sync_peers": download.get("header_sync_peers"),
        "max_blocks_per_peer": download.get("max_blocks_per_peer"),
        "peers": [{key: peer[key] for key in FIELDS if key in peer} for peer in peers],
    }


def render(state):
    print("{time} active={active_height} headers={header_height} IBD={ibd} "
          "inbound={inbound} outbound={outbound}".format(**state), flush=True)
    print("download peers={} global requests={} validated={}".format(
        state["download_peers"], state["global_blocks_in_flight"],
        state["global_validated_blocks_in_flight"]), flush=True)
    for peer in state["peers"]:
        print("peer={} {} services={} preferred={} headers={} header_sync={} stopped={} "
              "requests={} oldest_age={}s "
              "remaining={}s stall={}s oldest={}".format(
                  peer["id"], "in" if peer["inbound"] else "out", peer.get("services"),
                  peer.get("preferred_download"), peer.get("synced_headers"),
                  peer.get("header_sync_started"), peer.get("block_download_stopped"),
                  peer.get("blocks_in_flight", len(peer.get("inflight", []))),
                  peer.get("oldest_request_age"), peer.get("block_download_timeout_remaining"),
                  peer.get("block_stall_duration"), peer.get("oldest_block_request")), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=pathlib.Path, default=ROOT / "src/zclassic-cli")
    parser.add_argument("--datadir", type=pathlib.Path, default=pathlib.Path.home() / ".zclassic")
    parser.add_argument("--json", action="store_true", help="One JSON object per sample")
    parser.add_argument("--watch", type=float, default=0, help="Repeat every N seconds (minimum 1); default once")
    args = parser.parse_args()
    if not math.isfinite(args.watch) or args.watch < 0 or (0 < args.watch < 1):
        parser.error("--watch must be zero or at least one second")
    cli = [str(args.cli), "-datadir=" + str(args.datadir), "-rpcclienttimeout=10"]
    try:
        while True:
            try:
                state = snapshot(cli)
            except (RuntimeError, subprocess.TimeoutExpired, ValueError, OSError) as error:
                if not args.watch:
                    parser.exit(1, str(error) + "\n")
                failed = {"time": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                          "error": str(error)}
                print(json.dumps(failed) if args.json else
                      "{time} sample unavailable: {error}".format(**failed), flush=True)
            else:
                if args.json:
                    print(json.dumps(state), flush=True)
                else:
                    render(state)
            if not args.watch:
                return 0
            time.sleep(args.watch)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
