#!/usr/bin/env python3
"""Exercise real mainnet block-download timeout/recovery without test mining.

Starts one isolated daemon, supplies original blocks 0..129 from two local
P2P peers, and waits for the real request deadline. No production RPC/datadir
is used. Logs and the temporary test datadir are retained in --output.
"""
import argparse
import hashlib
import json
import os
import pathlib
import socket
import struct
import subprocess
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
MAGIC = bytes.fromhex("24e92764")


def hash256(data):
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()


def compact(data, offset=0):
    tag = data[offset]
    if tag < 253:
        return tag, offset + 1
    width = {253: 2, 254: 4, 255: 8}[tag]
    end = offset + width + 1
    if end > len(data):
        raise ValueError("short compact size")
    return int.from_bytes(data[offset + 1:end], "little"), end


def fixture(path=None, checksum="4ae8e7c4a2b2fb5b925ecc18752bf517dad39dd0a965a8c44d4fee29360ba2b6"):
    data = (path or ROOT / "src/test/data/zclassic-download-130.dat").read_bytes()
    if hashlib.sha256(data).hexdigest() != checksum:
        raise ValueError("fixture checksum mismatch")
    blocks, headers, offset = {}, [], 0
    height = 0
    while offset < len(data):
        if data[offset:offset + 4] != MAGIC:
            raise ValueError("fixture network mismatch")
        size = struct.unpack_from("<I", data, offset + 4)[0]
        block = data[offset + 8:offset + 8 + size]
        solution_size, start = compact(block, 140)
        header = block[:start + solution_size]
        blocks[hash256(header)] = (height, block)
        headers.append(header)
        offset += size + 8
        height += 1
    if offset != len(data):
        raise ValueError("fixture framing mismatch")
    return blocks, headers


class Peer(threading.Thread):
    def __init__(self, port, name, blocks, headers, deliver, connection=None,
                 announce_headers=True, answer_headers=True):
        super().__init__(name=name, daemon=True)
        self.sock = connection or socket.create_connection(("127.0.0.1", port), timeout=5)
        self.sock.settimeout(0.5)
        self.blocks, self.headers, self.deliver = blocks, headers, deliver
        self.announce_headers = announce_headers
        self.answer_headers = answer_headers
        self.header_heights = {hash256(header): height for height, header in enumerate(headers)}
        self.requested = threading.Event()
        self.handshaken = threading.Event()
        self.notfound_queued = threading.Event()
        self.disconnected = threading.Event()
        self.stop_event = threading.Event()
        self.requests, self.delivered, self.errors = [], [], []
        self.header_messages = 0
        self.notfound_messages = 0
        self.start_time = time.monotonic()
        self.disconnect_age = None

    def send(self, command, payload=b""):
        self.sock.sendall(MAGIC + command.encode().ljust(12, b"\0") +
                          struct.pack("<I", len(payload)) + hash256(payload)[:4] + payload)

    def send_headers(self, start=1):
        batch = self.headers[start:start + 160]
        payload = bytes([len(batch)]) + b"".join(header + b"\0" for header in batch)
        self.send("headers", payload)
        self.header_messages += 1

    def process(self, command, payload):
        if command == b"version":
            self.send("verack")
        elif command == b"verack":
            self.handshaken.set()
            if self.announce_headers:
                self.send_headers()
        elif command == b"getheaders":
            if not self.answer_headers:
                return
            count, offset = compact(payload, 4)  # Serialized locator starts with version.
            if count > 101 or len(payload) != offset + 32 * (count + 1):
                raise ValueError("invalid getheaders locator")
            start = 1
            for index in range(count):
                locator = payload[offset + index * 32:offset + (index + 1) * 32]
                if locator in self.header_heights:
                    start = self.header_heights[locator] + 1
                    break
            self.send_headers(start)
        elif command == b"ping":
            self.send("pong", payload)
        elif command == b"getdata":
            count, offset = compact(payload)
            if count > 50000 or len(payload) != offset + count * 36:
                raise ValueError("invalid getdata")
            for i in range(count):
                kind = struct.unpack_from("<I", payload, offset)[0]
                block_hash = payload[offset + 4:offset + 36]
                offset += 36
                if kind != 2:
                    continue
                height, block = self.blocks[block_hash]
                self.requests.append(height)
                if self.deliver:
                    self.send("block", block)
                    self.delivered.append(height)
            self.requested.set()
        elif command == b"reject":
            raise ValueError("daemon rejected historical fixture: " + payload.hex())

    def run(self):
        try:
            addr = struct.pack("<Q", 1) + bytes(10) + b"\xff\xff\x7f\0\0\1" + bytes(2)
            agent = ("/OG-download-test-" + self.name + ":1/").encode()
            self.send("version", struct.pack("<iQq", 170011, 1, int(time.time())) +
                      addr + addr + os.urandom(8) + bytes([len(agent)]) + agent +
                      struct.pack("<i?", len(self.headers) - 1, False))
            buffer = bytearray()
            next_headers = time.monotonic() + 30
            while not self.stop_event.is_set():
                if self.notfound_queued.is_set():
                    # Send from this thread so complete P2P frames cannot
                    # interleave with ping or header replies on the socket.
                    height = self.requests[0]
                    self.send("notfound", b"\x01" + struct.pack("<I", 2) +
                              hash256(self.headers[height]))
                    self.notfound_messages += 1
                    self.notfound_queued.clear()
                if not self.deliver and self.requested.is_set() and time.monotonic() >= next_headers:
                    self.send_headers(max(1, len(self.headers) - 159))
                    next_headers = time.monotonic() + 30
                try:
                    data = self.sock.recv(65536)
                    if not data:
                        self.disconnect_age = time.monotonic() - self.start_time
                        self.disconnected.set()
                        break
                    buffer.extend(data)
                except socket.timeout:
                    continue
                while len(buffer) >= 24:
                    size = struct.unpack_from("<I", buffer, 16)[0]
                    if buffer[:4] != MAGIC or size > 4 * 1024 * 1024:
                        raise ValueError("invalid daemon frame")
                    if len(buffer) < size + 24:
                        break
                    payload = bytes(buffer[24:size + 24])
                    if hash256(payload)[:4] != buffer[20:24]:
                        raise ValueError("daemon checksum mismatch")
                    command = bytes(buffer[4:16]).rstrip(b"\0")
                    del buffer[:size + 24]
                    self.process(command, payload)
        except Exception as error:
            if not self.stop_event.is_set():
                self.errors.append(repr(error))
        finally:
            self.sock.close()

    def finish(self):
        self.stop_event.set()
        self.join(timeout=6)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--daemon", type=pathlib.Path, default=ROOT / "src/zclassicd")
    parser.add_argument("--cli", type=pathlib.Path, default=ROOT / "src/zclassic-cli")
    parser.add_argument("--timeout", type=int, default=390)
    direction = parser.add_mutually_exclusive_group()
    direction.add_argument("--outbound", action="store_true", help="Have the daemon dial A and B through addnode")
    direction.add_argument("--preferred-recovery", action="store_true",
                           help="Inbound A stalls; outbound B sends headers only when requested")
    direction.add_argument("--notfound-recovery", action="store_true",
                           help="Outbound A reports a missing block after quiet outbound B connects")
    parser.add_argument("--churn", type=int, default=2, help="Peers torn down with 128 pending requests before A")
    parser.add_argument("--rpcport", type=int, default=18623)
    parser.add_argument("--port", type=int, default=18633)
    args = parser.parse_args()
    both_outbound = args.outbound or args.notfound_recovery
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    datadir = output / "datadir"
    datadir.mkdir()  # Refuse to reuse or modify any pre-existing datadir.
    blocks, headers = fixture()
    cli = [str(args.cli), "-datadir=" + str(datadir), "-rpcport=" + str(args.rpcport), "-rpcclienttimeout=5"]

    def rpc(method):
        result = subprocess.run(cli + [method], capture_output=True, text=True, timeout=8)
        if result.returncode:
            raise RuntimeError(result.stderr.strip())
        return json.loads(result.stdout) if method != "stop" else result.stdout.strip()

    command = [str(args.daemon), "-datadir=" + str(datadir), "-daemon=0", "-server=1",
               "-disablewallet=1", "-gen=0", "-bootstrap=0", "-connect=127.0.0.1:1",
               "-dnsseed=0", "-listenonion=0", "-upnp=0", "-natpmp=0", "-maxconnections=32",
               "-rpcport=" + str(args.rpcport), "-port=" + str(args.port), "-bind=127.0.0.1",
               "-printtoconsole=1", "-debug=net"]
    listeners = []
    if both_outbound or args.preferred_recovery:
        for index in ((1, 2) if both_outbound else (2,)):
            port = args.port + index
            host = "127.0.0." + str(index)
            listener = socket.socket()
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind((host, port))
            listener.listen(4)
            listener.settimeout(20)
            listeners.append(listener)
            command.append("-addnode=" + host + ":" + str(port))
    report = {"command": command, "pass": False, "outbound_test": both_outbound,
              "preferred_recovery": args.preferred_recovery,
              "notfound_recovery": args.notfound_recovery}
    peers = []
    with (output / "daemon.log").open("w") as log:
        daemon = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        report["pid"] = daemon.pid
        try:
            deadline = time.monotonic() + 90
            while True:
                try:
                    mining = rpc("getmininginfo")
                    assert mining["generate"] is False
                    break
                except RuntimeError:
                    if daemon.poll() is not None or time.monotonic() > deadline:
                        raise
                    time.sleep(0.5)
            report["churn"] = []
            for index in range(args.churn):
                name = "churn" + str(index)
                churned = Peer(args.port, name, blocks, headers, False)
                peers.append(churned)
                churned.start()
                assert churned.requested.wait(20), "churn peer never received requests"
                assert churned.requests == list(range(1, 129)), churned.requests
                churned.finish()
                deadline = time.monotonic() + 20
                while any(name in peer["subver"] for peer in rpc("getpeerinfo")):
                    if time.monotonic() > deadline:
                        raise TimeoutError("churn peer did not leave peer list")
                    time.sleep(0.1)
                assert not churned.errors, churned.errors
                report["churn"].append({"name": name, "requests": len(churned.requests)})
            stalled = Peer(args.port, "A", blocks, headers, False,
                           listeners[0].accept()[0] if both_outbound else None,
                           # Retain A's active header role until notfound, so
                           # this case isolates negative-response recovery.
                           answer_headers=not args.notfound_recovery)
            peers.append(stalled)
            stalled.start()
            assert stalled.requested.wait(20), "A never received requests"
            assert stalled.requests == list(range(1, 129)), stalled.requests
            healthy = Peer(args.port, "B", blocks, headers, True,
                           listeners[-1].accept()[0] if listeners else None,
                           announce_headers=not (args.preferred_recovery or args.notfound_recovery))
            peers.append(healthy)
            healthy.start()
            if args.notfound_recovery:
                assert healthy.handshaken.wait(20), "B handshake did not complete"
                report["before_notfound"] = rpc("getpeerinfo")
                assert len(report["before_notfound"]) == 2
                assert all(peer["preferred_download"] for peer in report["before_notfound"])
                assert sorted(peer["blocks_in_flight"] for peer in report["before_notfound"]) == [0, 128]
                stalled.notfound_queued.set()
            assert healthy.requested.wait(20), "B never received requests"
            if args.notfound_recovery:
                assert stalled.disconnected.wait(20), "A retained its failed download connection"
            download_peers = [peer for peer in rpc("getpeerinfo")
                              if peer["subver"] in ("/OGdownloadtestA:1/", "/OGdownloadtestB:1/")]
            assert len(download_peers) == (1 if args.notfound_recovery else 2)
            for peer in download_peers:
                outbound = both_outbound or (args.preferred_recovery and
                                            peer["subver"] == "/OGdownloadtestB:1/")
                assert peer["inbound"] != outbound
                assert peer["preferred_download"] == outbound
            deadline = time.monotonic() + args.timeout
            samples = []
            while time.monotonic() < deadline:
                chain, peerinfo = rpc("getblockchaininfo"), rpc("getpeerinfo")
                samples.append({"time": int(time.time()), "height": chain["blocks"], "peers": peerinfo})
                (output / "samples.json").write_text(json.dumps(samples, indent=2) + "\n")
                if any(peer.errors for peer in peers):
                    raise RuntimeError([peer.errors for peer in peers])
                if chain["blocks"] == 129:
                    assert stalled.disconnected.wait(5), "A was not disconnected"
                    assert len(stalled.requests) == 128
                    assert sorted(healthy.delivered) == list(range(1, 130))
                    if args.notfound_recovery:
                        assert stalled.notfound_messages == 1
                        assert stalled.disconnect_age < 20, "recovery waited for block timeout"
                    else:
                        assert stalled.header_messages >= 3
                    assert chain["bestblockhash"] == hash256(headers[129])[::-1].hex()
                    assert all(peer["global_blocks_in_flight"] == 0 for peer in peerinfo)
                    assert all(peer["global_validated_blocks_in_flight"] == 0 for peer in peerinfo)
                    assert daemon.poll() is None, "daemon exited during recovery"
                    report.update(pass_=True, height=129, no_restart=True,
                                  a_disconnect_seconds=stalled.disconnect_age,
                                  a_header_messages=stalled.header_messages,
                                  a_notfound_messages=stalled.notfound_messages,
                                  b_delivered=healthy.delivered)
                    report["pass"] = report.pop("pass_")
                    break
                time.sleep(2)
            else:
                raise TimeoutError("chain did not recover before test deadline")
        except Exception as error:
            report["error"] = repr(error)
        finally:
            for listener in listeners:
                listener.close()
            for peer in peers:
                peer.finish()
            try:
                report["stop"] = rpc("stop")
                report["exit"] = daemon.wait(timeout=90)
                if report["exit"] != 0:
                    report["pass"] = False
            except Exception as error:
                report["shutdown_error"] = repr(error)
                report["pass"] = False
            report["peer_errors"] = [peer.errors for peer in peers]
    (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
