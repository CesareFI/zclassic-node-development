#!/usr/bin/env python3
"""Stress pending OG block requests across real FIN, reset, and RPC teardown.

Uses a fresh isolated datadir and historical fixture, never mining. Alternates
inbound/outbound connections while a second thread reads peer/network RPCs.
"""
import argparse
import importlib.util
import json
import pathlib
import socket
import struct
import subprocess
import threading
import time

SPEC = importlib.util.spec_from_file_location(
    "og_stall", pathlib.Path(__file__).with_name("og-download-stall.py"))
WIRE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WIRE)


class TeardownSocket:
    """Accept reset as closure only after the test requested RPC disconnect."""
    def __init__(self, sock):
        self.sock = sock
        self.expect_reset = False
        self.reset_received = False

    def __getattr__(self, name):
        return getattr(self.sock, name)

    def recv(self, size):
        try:
            return self.sock.recv(size)
        except ConnectionResetError:
            if not self.expect_reset:
                raise
            self.reset_received = True
            return b""


class Observer(threading.Thread):
    def __init__(self, rpc):
        super().__init__(daemon=True)
        self.rpc = rpc
        self.stop_event = threading.Event()
        self.errors = []
        self.samples = 0

    def run(self):
        try:
            while not self.stop_event.is_set():
                for method in ("getpeerinfo", "getnetworkinfo", "getblockchaininfo"):
                    self.rpc(method)
                    self.samples += 1
                self.stop_event.wait(0.02)
        except Exception as error:
            self.errors.append(repr(error))


def wait_until(predicate, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise TimeoutError("condition did not become true")


def connected_peer(rpc, port, index, blocks, headers, deliver=False):
    if index % 2:
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            listener.settimeout(20)
            rpc("addnode", "127.0.0.1:" + str(listener.getsockname()[1]), "onetry")
            connection, _ = listener.accept()
            return WIRE.Peer(port, "teardown" + str(index), blocks, headers, deliver,
                             connection=connection)
    return WIRE.Peer(port, "teardown" + str(index), blocks, headers, deliver)


def check_empty(rpc):
    if rpc("getpeerinfo"):
        return False
    state = rpc("getblockchaininfo")["blockdownload"]
    keys = ("blocks_in_flight", "validated_blocks_in_flight",
            "preferred_peers", "header_sync_peers")
    return state if all(state[key] == 0 for key in keys) else False


def teardown_round(rpc, args, index, blocks, headers, peers):
    peer = connected_peer(rpc, args.port, index, blocks, headers)
    peer.sock = TeardownSocket(peer.sock)
    peers.append(peer)
    peer.start()
    assert peer.requested.wait(20), "peer never received requests"
    assert peer.requests == list(range(1, 129)), peer.requests
    current = rpc("getpeerinfo")
    assert len(current) == 1, current
    assert current[0]["inbound"] == (index % 2 == 0), current
    state = rpc("getblockchaininfo")["blockdownload"]
    assert state["blocks_in_flight"] == 128, state
    assert state["validated_blocks_in_flight"] == 128, state
    mode = ("fin", "reset", "rpc")[index % 3]
    start = time.monotonic()
    if mode == "rpc":
        peer.sock.expect_reset = True
        rpc("disconnectnode", current[0]["addr"])
        assert peer.disconnected.wait(20), "RPC disconnect left socket connected"
    elif mode == "reset":
        peer.sock.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
    peer.finish()
    assert not peer.is_alive(), "fixture peer thread did not stop"
    assert not peer.errors, peer.errors
    empty = wait_until(lambda: check_empty(rpc))
    return {"index": index, "mode": mode, "inbound": current[0]["inbound"],
            "requests": len(peer.requests), "release_seconds": time.monotonic() - start,
            "rpc_close_was_reset": peer.sock.reset_received,
            "after": empty}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--daemon", type=pathlib.Path, default=WIRE.ROOT / "src/zclassicd")
    parser.add_argument("--cli", type=pathlib.Path, default=WIRE.ROOT / "src/zclassic-cli")
    parser.add_argument("--rounds", type=int, default=48)
    parser.add_argument("--rpcport", type=int, default=18723)
    parser.add_argument("--port", type=int, default=18733)
    args = parser.parse_args()
    if not 6 <= args.rounds <= 600:
        parser.error("--rounds must be between 6 and 600")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    datadir = output / "datadir"
    datadir.mkdir()  # Refuse existing state, including production datadirs.
    blocks, headers = WIRE.fixture()
    cli = [str(args.cli), "-datadir=" + str(datadir), "-rpcclienttimeout=30"]

    def rpc(method, *params):
        result = subprocess.run(cli + [method, *params], capture_output=True,
                                text=True, timeout=35)
        if result.returncode:
            raise RuntimeError(result.stderr.strip())
        if method == "stop":
            return result.stdout.strip()
        return json.loads(result.stdout) if result.stdout.strip() else None

    command = [str(args.daemon), "-datadir=" + str(datadir), "-daemon=0", "-server=1",
               "-disablewallet=1", "-gen=0", "-bootstrap=0", "-connect=127.0.0.1:1",
               "-dnsseed=0", "-listenonion=0", "-upnp=0", "-natpmp=0",
               "-rpcport=" + str(args.rpcport), "-port=" + str(args.port),
               "-bind=127.0.0.1", "-printtoconsole=1", "-debug=net"]
    # The CLI reads this only from the newly created test datadir.
    (datadir / "zclassic.conf").write_text("rpcport=" + str(args.rpcport) + "\n")
    report = {"pass": False, "command": command, "rounds": []}
    peers, observer = [], None
    with (output / "daemon.log").open("w") as log:
        daemon = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        report["pid"] = daemon.pid
        try:
            def ready():
                if daemon.poll() is not None:
                    raise RuntimeError("daemon exited during startup")
                try:
                    return rpc("getmininginfo")
                except RuntimeError:
                    return False
            assert wait_until(ready, 90)["generate"] is False
            observer = Observer(rpc)
            observer.start()
            for index in range(args.rounds):
                report["rounds"].append(teardown_round(rpc, args, index, blocks, headers, peers))
                assert not observer.errors, observer.errors
            healthy = connected_peer(rpc, args.port, args.rounds, blocks, headers, True)
            peers.append(healthy)
            healthy.start()
            def reached_tip():
                state = rpc("getblockchaininfo")
                return state if state["blocks"] == 129 else False
            chain = wait_until(reached_tip, 90)
            assert chain["bestblockhash"] == WIRE.hash256(headers[129])[::-1].hex()
            assert sorted(healthy.delivered) == list(range(1, 130)), healthy.delivered
            healthy.finish()
            report["final_accounting"] = wait_until(lambda: check_empty(rpc))
            assert rpc("getmininginfo")["generate"] is False
            assert daemon.poll() is None, "daemon exited during recovery"
            report.update({"pass": True, "height": 129, "no_restart": True})
        except Exception as error:
            report["error"] = repr(error)
        finally:
            if observer:
                observer.stop_event.set()
                observer.join(timeout=110)
                report["observer_samples"] = observer.samples
                report["observer_errors"] = observer.errors
                if observer.is_alive() or observer.errors:
                    report["pass"] = False
            for peer in peers:
                peer.finish()
            report["peer_errors"] = [peer.errors for peer in peers]
            if any(peer.errors or peer.is_alive() for peer in peers):
                report["pass"] = False
            try:
                report["stop"] = rpc("stop")
                report["exit"] = daemon.wait(timeout=90)
                if report["exit"] != 0:
                    report["pass"] = False
            except Exception as error:
                report["shutdown_error"] = repr(error)
                report["pass"] = False
    (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
