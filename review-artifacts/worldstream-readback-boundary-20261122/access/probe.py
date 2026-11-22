"""Read prearranged synthetic fixtures using ordinary opens. No host discovery."""
import errno
import json
import os
from pathlib import Path
import sys
p = Path.cwd()
targets = {
    "case-relative": "allowed.txt",
    "case-absolute": str(p / "allowed.txt"),
    "case-linked": "allowed.link",
    "receiver-direct": str(p.parent / "receiver" / "admin.txt"),
    "receiver-relative": "../receiver/admin.txt",
    "receiver-linked": "admin.link",
    "controller-direct": str(p.parent / "controller" / "state.txt"),
    "controller-relative": "../controller/state.txt",
    "controller-linked": "state.link",
    "other-case-direct": str(p.parent / "other-case" / "record.txt"),
    "other-case-relative": "../other-case/record.txt",
    "other-case-linked": "record.link",
    "recorder-relative": "../recorder/pipe",
    "recorder-linked": "recorder.link",
}
for label, name in targets.items():
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NONBLOCK)
        try:
            data = os.read(fd, 32)
        finally:
            os.close(fd)
    except OSError as ex:
        row = {"result": -1, "errno": ex.errno, "symbol": errno.errorcode[ex.errno], "error": ex.strerror}
    else:
        row = {"result": 0, "bytes_read": len(data)}
    print(json.dumps({"target": label, **row}), flush=True)
