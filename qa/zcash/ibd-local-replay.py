#!/usr/bin/env python3
"""Serve a finite prefix of captured mainnet blocks to localhost benchmarks.

Read only blk*.dat files from a stopped scratch node. The receiving daemon
validates every header and block normally. This fixture is not a node, does not
validate the source, and must never serve external interfaces.
"""
import argparse
import hashlib
import json
from pathlib import Path
import socket
import struct
import time

MAGIC = bytes.fromhex("24e92764")
GENESIS = bytes.fromhex("0007104ccda289427919efc39dc9e4d499804b7bebc22df55f8b834301260602")[::-1]
MAX_MESSAGE = 4 * 1024 * 1024


def hash256(data):
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()


def compact(value):
    if value < 253:
        return bytes([value])
    if value <= 65535:
        return b"\xfd" + struct.pack("<H", value)
    return b"\xfe" + struct.pack("<I", value)


def read_compact(data, offset):
    first = data[offset]
    if first < 253:
        return first, offset + 1
    size = {253: 2, 254: 4, 255: 8}[first]
    end = offset + 1 + size
    if end > len(data):
        raise ValueError("truncated compact size")
    return int.from_bytes(data[offset + 1:end], "little"), end


def load_blocks(directory, height):
    # Store offsets, not complete block bodies, to bound fixture memory.
    entries = {}
    successors = {}
    for path in sorted(directory.glob("blk*.dat")):
        with path.open("rb") as source:
            while True:
                prefix = source.read(8)
                if not prefix or prefix == bytes(8):
                    break
                if len(prefix) != 8 or prefix[:4] != MAGIC:
                    raise ValueError("invalid block-file framing")
                size = struct.unpack("<I", prefix[4:])[0]
                if not 141 <= size <= MAX_MESSAGE:
                    raise ValueError("invalid block size")
                offset = source.tell()
                block = source.read(size)
                if len(block) != size:
                    raise ValueError("truncated block")
                solution_size, header_end = read_compact(block, 140)
                header_end += solution_size
                if header_end > size:
                    raise ValueError("truncated header")
                header = block[:header_end]
                block_hash = hash256(header)
                previous = block[4:36]
                if previous in successors and successors[previous] != block_hash:
                    raise ValueError("fixture contains forks; select a single-chain capture")
                successors[previous] = block_hash
                entries[block_hash] = (path, offset, size, header)
    chain = [GENESIS]
    while len(chain) <= height:
        chain.append(successors[chain[-1]])
    selected = {h: entries[h] for h in chain}
    return chain, selected


def receive(connection, length):
    data = bytearray()
    while len(data) < length:
        part = connection.recv(length - len(data))
        if not part:
            raise EOFError()
        data.extend(part)
    return bytes(data)


def send(connection, command, payload=b""):
    connection.sendall(MAGIC + command.encode().ljust(12, b"\0") +
                       struct.pack("<I", len(payload)) + hash256(payload)[:4] + payload)


def serve(connection, chain, entries, stall_headers=False, withhold_verack=False, stall_blocks=False):
    heights = {h: i for i, h in enumerate(chain)}
    # The fault fixture must not disconnect itself before the node can detect
    # the lack of progress. It remains reachable and answers the node's pings.
    connection.settimeout(None if stall_headers else 180)
    while True:
        header = receive(connection, 24)
        size = struct.unpack("<I", header[16:20])[0]
        if header[:4] != MAGIC or size > MAX_MESSAGE:
            raise ValueError("invalid message framing")
        payload = receive(connection, size)
        if hash256(payload)[:4] != header[20:24]:
            raise ValueError("invalid checksum")
        command = header[4:16].rstrip(b"\0")
        if command == b"version":
            address = struct.pack("<Q", 1) + bytes(10) + b"\xff\xff\x7f\0\0\x01" + struct.pack(">H", 8033)
            agent = b"/local-ibd-replay/"
            version = (struct.pack("<iQq", 170011, 1, int(time.time())) + address + address +
                       struct.pack("<Q", 123456789) + compact(len(agent)) + agent +
                       struct.pack("<i?", len(chain) - 1, False))
            send(connection, "version", version)
            if not withhold_verack:
                send(connection, "verack")
        elif command == b"ping" and len(payload) == 8:
            send(connection, "pong", payload)
        elif command == b"getheaders":
            if stall_headers:
                # Controlled local availability fault: stay responsive to ping
                # while withholding headers. Never enabled on the normal fixture.
                print(json.dumps({"headers_withheld": True, "time": time.time()}), flush=True)
                continue
            count, offset = read_compact(payload, 4)
            if count > 101 or len(payload) != offset + 32 * count + 32:
                raise ValueError("invalid locator")
            start = 0
            for i in range(count):
                locator = payload[offset + 32 * i:offset + 32 * (i + 1)]
                if locator in heights:
                    start = heights[locator]
                    break
            stop = payload[-32:]
            end = min(start + 160, len(chain) - 1)
            if stop in heights and heights[stop] > start:
                end = min(end, heights[stop])
            hashes = chain[start + 1:end + 1]
            send(connection, "headers", compact(len(hashes)) +
                 b"".join(entries[h][3] + b"\0" for h in hashes))
        elif command == b"getdata":
            count, offset = read_compact(payload, 0)
            if count > 50000 or len(payload) != offset + 36 * count:
                raise ValueError("invalid inventory")
            if stall_blocks:
                print(json.dumps({"blocks_withheld": count, "time": time.time()}), flush=True)
                continue
            for i in range(count):
                kind = struct.unpack_from("<I", payload, offset + 36 * i)[0]
                block_hash = payload[offset + 36 * i + 4:offset + 36 * (i + 1)]
                if kind == 2 and block_hash in entries:
                    path, position, size, _ = entries[block_hash]
                    with path.open("rb") as source:
                        source.seek(position)
                        block = source.read(size)
                    if len(block) != size:
                        raise ValueError("fixture changed during replay")
                    send(connection, "block", block)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blocks", type=Path, required=True)
    parser.add_argument("--height", type=int, default=5000)
    parser.add_argument("--port", type=int, default=18444)
    parser.add_argument("--stall-headers", action="store_true",
                        help="local fault test: answer pings but withhold headers")
    parser.add_argument("--withhold-verack", action="store_true",
                        help="local fault test: leave the version handshake incomplete")
    parser.add_argument("--stall-blocks", action="store_true",
                        help="local fault test: serve headers but withhold block bodies")
    args = parser.parse_args()
    if not 1 <= args.height <= 100000 or not 1 <= args.port <= 65535:
        parser.error("height must be 1..100000 and port must be valid")
    chain, entries = load_blocks(args.blocks, args.height)
    print(json.dumps({"height": args.height, "tip": chain[-1][::-1].hex(),
                      "bind": "127.0.0.1", "port": args.port}), flush=True)
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", args.port))
        listener.listen(1)
        while True:
            connection, _ = listener.accept()
            with connection:
                try:
                    serve(connection, chain, entries, args.stall_headers, args.withhold_verack, args.stall_blocks)
                except (EOFError, OSError, ValueError, IndexError) as error:
                    print(json.dumps({"connection_closed": type(error).__name__}), flush=True)


if __name__ == "__main__":
    main()
