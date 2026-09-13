#!/usr/bin/env python3
"""Check ordinary header completion and healthy-peer discovery in a new datadir.

Two loopback peers serve the original 0..129 fixture through normal validation.
A answers with an empty or short header list; quiet preferred B must then be
asked for headers. No production datadir, external peer, or mining is used.
"""
import argparse
import importlib.util
import json
import pathlib
import socket
import subprocess
import time

SPEC = importlib.util.spec_from_file_location(
    "og_stall", pathlib.Path(__file__).with_name("og-download-stall.py"))
WIRE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WIRE)


def wait_for(daemon, predicate, description, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if daemon.poll() is not None:
            raise RuntimeError("daemon exited while waiting for " + description)
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise TimeoutError(description)


def stop_owned_daemon(daemon, rpc, report):
    if daemon.poll() is not None:
        report["pass"] = False
        report["shutdown_error"] = "daemon exited before stop"
    else:
        try:
            report["stop"] = rpc("stop")
            daemon.wait(timeout=60)
        except Exception as error:
            report["pass"] = False
            report["shutdown_error"] = repr(error)
            if daemon.poll() is None:
                daemon.terminate()
                try:
                    daemon.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    daemon.kill()
                    daemon.wait(timeout=10)
    report["exit"] = daemon.returncode
    if daemon.returncode != 0:
        report["pass"] = False


def run(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    datadir = output / "datadir"
    datadir.mkdir()  # Refuse to reuse any existing datadir.
    blocks, headers = WIRE.fixture()
    cli = [str(args.cli.resolve()), "-datadir=" + str(datadir),
           "-rpcport=" + str(args.rpcport), "-rpcclienttimeout=5"]

    def rpc(method):
        result = subprocess.run(cli + [method], capture_output=True, text=True, timeout=8)
        if result.returncode:
            raise RuntimeError(result.stderr.strip())
        return result.stdout.strip() if method == "stop" else json.loads(result.stdout)

    command = [str(args.daemon.resolve()), "-datadir=" + str(datadir),
               "-daemon=0", "-server=1", "-disablewallet=1", "-gen=0",
               "-bootstrap=0", "-connect=127.0.0.1:1", "-dnsseed=0",
               "-listen=0", "-listenonion=0", "-upnp=0", "-natpmp=0",
               "-maxconnections=8", "-rpcport=" + str(args.rpcport),
               "-printtoconsole=1", "-debug=net"]
    report = {"pass": False, "response": args.response}
    listeners, peers = [], []
    try:
        for host in ("127.0.0.1", "127.0.0.2"):
            listener = socket.socket()
            listeners.append(listener)
            listener.bind((host, 0))
            listener.listen(1)
            listener.settimeout(30)
            command.append("-addnode=" + host + ":" + str(listener.getsockname()[1]))
        report["command"] = command
        with (output / "daemon.log").open("x") as log:
            daemon = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            report["pid"] = daemon.pid
            try:
                def ready():
                    try:
                        return rpc("getmininginfo")
                    except RuntimeError:
                        return None
                assert wait_for(daemon, ready, "RPC readiness", 90)["generate"] is False
                first_headers = headers[:1] if args.response == "empty" else headers
                first = WIRE.Peer(0, "A", blocks, first_headers, False,
                                  listeners[0].accept()[0], announce_headers=False)
                peers.append(first)
                first.start()
                wait_for(daemon, lambda: first.header_messages == 1, "A header response")
                if args.response == "short":
                    wait_for(daemon, lambda: len(first.requests) == 128, "A block assignments")
                healthy = WIRE.Peer(0, "B", blocks, headers, True,
                                    listeners[1].accept()[0], announce_headers=False)
                peers.append(healthy)
                healthy.start()
                wait_for(daemon, healthy.requested.is_set, "B requests after A completed headers")
                report["after_discovery"] = rpc("getpeerinfo")
                assert len(report["after_discovery"]) == 2
                for peer in report["after_discovery"]:
                    assert peer["preferred_download"] and not peer["inbound"]
                    assert not peer["header_sync_started"]
                    assert not peer["block_download_stopped"]
                if args.response == "short":
                    assert first.requests == list(range(1, 129))
                    assert healthy.requests == [129]
                    first.finish()  # Ordinary disconnect releases A's assignments.
                else:
                    assert not first.requests
                wait_for(daemon, lambda: rpc("getblockchaininfo")["blocks"] == 129,
                         "fully validated fixture chain")
                report["chain"] = rpc("getblockchaininfo")
                assert report["chain"]["bestblockhash"] == WIRE.hash256(headers[-1])[::-1].hex()
                assert report["chain"]["blockdownload"]["blocks_in_flight"] == 0
                assert report["chain"]["blockdownload"]["validated_blocks_in_flight"] == 0
                assert report["chain"]["blockdownload"]["header_sync_peers"] == 0
                assert sorted(healthy.delivered) == list(range(1, 130))
                assert first.header_messages == 1, "initial header query repeated"
                report["b_delivered"] = healthy.delivered
                report["a_requests"] = first.requests
                report["pass"] = True
            except Exception as error:
                report["error"] = repr(error)
            finally:
                for peer in peers:
                    peer.finish()
                stop_owned_daemon(daemon, rpc, report)
    finally:
        for listener in listeners:
            listener.close()
    report["peer_errors"] = [peer.errors for peer in peers]
    if any(report["peer_errors"]):
        report["pass"] = False
    (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["pass"] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--daemon", type=pathlib.Path, default=WIRE.ROOT / "src/zclassicd")
    parser.add_argument("--cli", type=pathlib.Path, default=WIRE.ROOT / "src/zclassic-cli")
    parser.add_argument("--response", choices=("empty", "short"), default="empty")
    parser.add_argument("--rpcport", type=int, default=18683)
    return run(parser.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
