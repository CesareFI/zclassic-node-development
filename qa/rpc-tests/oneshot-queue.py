#!/usr/bin/env python3
"""Keep a queued seed connection while another seed owns the outbound permit.

Two loopback peers exchange ordinary version/addr messages in a fresh datadir.
The first seed completes its address response after several connection-loop
iterations; the second seed must then connect. No blocks, mining, wallets,
external peers, or production datadir are used.
"""
import argparse
import importlib.util
import json
import pathlib
import socket
import subprocess
import threading

SPEC = importlib.util.spec_from_file_location(
    "header_fixture", pathlib.Path(__file__).with_name("og-header-discovery.py"))
FIXTURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIXTURE)


class SeedPeer(FIXTURE.WIRE.Peer):
    def __init__(self, name, connection, genesis):
        super().__init__(0, name, {}, [genesis], True, connection,
                         announce_headers=False)
        self.send_lock = threading.Lock()
        self.address_requested = threading.Event()

    def send(self, command, payload=b""):
        with self.send_lock:
            super().send(command, payload)

    def process(self, command, payload):
        if command == b"getaddr":
            self.address_requested.set()
        else:
            super().process(command, payload)


def exercise(daemon, rpc, listeners, unused_destination, logpath, report, peers):
    _, headers = FIXTURE.WIRE.fixture()
    first = SeedPeer("seedA", listeners[0].accept()[0], headers[0])
    peers.append(first)
    first.start()
    FIXTURE.wait_for(daemon, first.address_requested.is_set, "first seed getaddr")
    FIXTURE.wait_for(daemon, first.handshaken.is_set, "first seed handshake")
    # Each explicit-connect iteration first processes another queued seed.
    # The reserved, non-listening destination gives an observable loop marker.
    marker = "trying connection " + unused_destination
    FIXTURE.wait_for(daemon, lambda: logpath.read_text().count(marker) >= 3,
                     "three connection-loop iterations")
    report["occupied"] = rpc("getpeerinfo")
    assert len(report["occupied"]) == 1
    assert not report["occupied"][0]["preferred_download"]

    first.send("addr", b"\x00")  # Normal completion closes this one-shot connection.
    FIXTURE.wait_for(daemon, first.disconnected.is_set, "first seed completion")
    second = SeedPeer("seedB", listeners[1].accept()[0], headers[0])
    peers.append(second)
    second.start()
    FIXTURE.wait_for(daemon, second.address_requested.is_set, "queued seed getaddr")
    FIXTURE.wait_for(daemon, second.handshaken.is_set, "queued seed handshake")
    report["recovered"] = rpc("getpeerinfo")
    assert len(report["recovered"]) == 1
    assert not report["recovered"][0]["preferred_download"]
    second.send("addr", b"\x00")
    FIXTURE.wait_for(daemon, second.disconnected.is_set, "queued seed completion")
    FIXTURE.wait_for(daemon, lambda: not rpc("getpeerinfo"), "seed permit cleanup")
    report["chain"] = rpc("getblockchaininfo")
    assert report["chain"]["blocks"] == 0
    assert report["chain"]["blockdownload"]["blocks_in_flight"] == 0
    report["pass"] = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=pathlib.Path, required=True)
    parser.add_argument("--cli", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True)
    datadir = output / "datadir"
    datadir.mkdir()
    report = {"pass": False}
    listeners, peers = [], []
    try:
        for _ in range(2):
            listener = socket.socket()
            listeners.append(listener)
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            listener.settimeout(15)
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            rpcport = reservation.getsockname()[1]
        with socket.socket() as unused:
            unused.bind(("127.0.0.1", 0))
            destination = "127.0.0.1:" + str(unused.getsockname()[1])
            command = [str(args.daemon.resolve(strict=True)), "-datadir=" + str(datadir),
                       "-daemon=0", "-server=1", "-disablewallet=1", "-gen=0",
                       "-bootstrap=0", "-connect=" + destination, "-listen=0",
                       "-dnsseed=0", "-listenonion=0", "-upnp=0", "-natpmp=0",
                       "-maxconnections=1", "-dbcache=4", "-par=1", "-rpcbind=127.0.0.1",
                       "-rpcport=" + str(rpcport), "-printtoconsole=1", "-debug=net"]
            command += ["-seednode=127.0.0.1:" + str(item.getsockname()[1])
                        for item in listeners]
            cli = [str(args.cli.resolve(strict=True)), "-datadir=" + str(datadir),
                   "-rpcport=" + str(rpcport), "-rpcclienttimeout=5"]

            def rpc(method):
                result = subprocess.run(cli + [method], capture_output=True, text=True,
                                        check=True, timeout=8)
                return result.stdout.strip() if method == "stop" else json.loads(result.stdout)

            logpath = output / "daemon.log"
            with logpath.open("x") as log:
                daemon = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
                try:
                    def ready():
                        try:
                            return rpc("getmininginfo")
                        except subprocess.CalledProcessError:
                            return None
                    assert FIXTURE.wait_for(daemon, ready, "RPC readiness", 90)["generate"] is False
                    exercise(daemon, rpc, listeners, destination, logpath, report, peers)
                except Exception as error:
                    report["error"] = repr(error)
                finally:
                    for peer in peers:
                        peer.finish()
                    FIXTURE.stop_owned_daemon(daemon, rpc, report)
            report["sanitizer_error"] = any(marker in logpath.read_text() for marker in
                                            ("ERROR: AddressSanitizer", "runtime error:",
                                             "ERROR: LeakSanitizer"))
    finally:
        for listener in listeners:
            listener.close()
    report["peer_errors"] = [peer.errors for peer in peers]
    report["pass"] = report["pass"] and not any(report["peer_errors"]) and not report["sanitizer_error"]
    with (output / "result.json").open("x") as result_file:
        json.dump(report, result_file, indent=2)
        result_file.write("\n")
    print(json.dumps(report, indent=2))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
