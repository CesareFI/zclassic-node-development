#!/usr/bin/env python3
"""Read an OG Zclassic block from independent P2P peers; never submit data.

Frames, checksums, compact sizes and header hashes are bounded and checked.
This tool does not replace consensus validation by zclassicd.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import pathlib
import socket
import struct
import time

MAGIC = bytes.fromhex("24e92764")
MAX_MESSAGE = 4 * 1024 * 1024


def digest(data):
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()


def compact(data, offset):
    tag = data[offset]
    if tag < 253:
        return tag, offset + 1
    width = {253: 2, 254: 4, 255: 8}[tag]
    end = offset + 1 + width
    if end > len(data):
        raise ValueError("truncated compact size")
    value = int.from_bytes(data[offset + 1:end], "little")
    if value < {253: 253, 254: 65536, 255: 4294967296}[tag]:
        raise ValueError("noncanonical compact size")
    return value, end


def header_hash(data):
    size, offset = compact(data, 140)
    end = offset + size
    if size > 1344 or end > len(data):
        raise ValueError("invalid or incomplete header size")
    return digest(data[:end])[::-1].hex()


def send(sock, command, payload=b""):
    sock.sendall(MAGIC + command.encode().ljust(12, b"\0") +
                 struct.pack("<I", len(payload)) + digest(payload)[:4] + payload)


def receive(sock, size, deadline=None):
    if deadline is None:
        deadline = time.monotonic() + 8
    data = bytearray()
    while len(data) < size:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("message deadline exceeded")
        sock.settimeout(min(8, remaining))
        part = sock.recv(size - len(data))
        if not part:
            raise EOFError("peer closed connection")
        data.extend(part)
    return bytes(data)


def probe(host, args):
    result = {"peer": host, "time": int(time.time()), "messages": []}
    try:
        with socket.create_connection((host, args.port), timeout=8) as sock:
            sock.settimeout(8)
            addr = struct.pack("<Q", 0) + bytes(10) + b"\xff\xff" + bytes(4) + struct.pack(">H", args.port)
            agent = b"/Zclassic-block-diagnostic:1/"
            version = (struct.pack("<iQq", 170011, 0, int(time.time())) + addr + addr +
                       os.urandom(8) + bytes([len(agent)]) + agent + struct.pack("<i?", 478543, False))
            send(sock, "version", version)
            requested = False
            deadline = time.monotonic() + args.timeout
            while time.monotonic() < deadline:
                frame = receive(sock, 24, deadline)
                length = struct.unpack_from("<I", frame, 16)[0]
                if frame[:4] != MAGIC or length > MAX_MESSAGE:
                    raise ValueError("wrong chain magic or oversized frame")
                payload = receive(sock, length, deadline)
                if digest(payload)[:4] != frame[20:24]:
                    raise ValueError("bad checksum")
                command = frame[4:16].rstrip(b"\0").decode("ascii")
                result["messages"].append([command, length])
                if len(result["messages"]) > 256:
                    raise ValueError("message budget exhausted")
                if command == "version":
                    version, services = struct.unpack_from("<iQ", payload)
                    size, offset = compact(payload, 80)
                    result.update(version=version, services=services,
                                  agent=payload[offset:offset + size].decode("utf8", "replace"),
                                  height=struct.unpack_from("<i", payload, offset + size)[0])
                    send(sock, "verack")
                elif command == "verack" and not requested:
                    send(sock, "getheaders", struct.pack("<iB", 170011, 1) +
                         bytes.fromhex(args.previous)[::-1] + bytes.fromhex(args.hash)[::-1])
                    send(sock, "getdata", b"\x01" + struct.pack("<I", 2) + bytes.fromhex(args.hash)[::-1])
                    requested = True
                elif command == "ping":
                    send(sock, "pong", payload)
                elif command == "headers":
                    count, offset = compact(payload, 0)
                    result["headers_count"] = count
                    if count:
                        result["first_header"] = header_hash(payload[offset:])
                elif command == "block":
                    found = header_hash(payload)
                    if found != args.hash:
                        raise ValueError("unrequested block")
                    result.update(block_hash=found, block_bytes=length,
                                  payload_sha256=hashlib.sha256(payload).hexdigest())
                    path = args.output / (host.replace(":", "_") + "-" + found + ".block")
                    path.write_bytes(payload)
                    break
                elif command == "notfound":
                    result["notfound"] = payload.hex()
                    break
    except Exception as error:
        result["error"] = str(error)
    path = args.output / (host.replace(":", "_") + ".json")
    path.write_text(json.dumps(result, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("peers", nargs="+")
    parser.add_argument("--hash", required=True)
    parser.add_argument("--previous", required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--port", type=int, default=8033)
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()
    for value in (args.hash, args.previous):
        if len(bytes.fromhex(value)) != 32:
            parser.error("hashes must be 32 bytes")
    args.output.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for result in pool.map(lambda peer: probe(peer, args), args.peers):
            print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
