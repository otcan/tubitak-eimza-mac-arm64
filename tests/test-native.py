#!/usr/bin/env python3
"""Exercise native architecture detection and fail-closed download verification."""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

executable = Path(sys.argv[1]).resolve()

def check(arguments, expected):
    result = subprocess.run([str(executable), *map(str, arguments)], capture_output=True, text=True)
    if result.returncode != expected:
        raise AssertionError((arguments, result.returncode, result.stdout, result.stderr))

with tempfile.TemporaryDirectory() as temporary:
    directory = Path(temporary)
    for endian, magic, stride in ((">", 0xcafebabe, 20), ("<", 0xcafebabe, 20),
                                  (">", 0xcafebabf, 32), ("<", 0xcafebabf, 32)):
        for cpu, expected in ((0x0100000c, 0), (0x01000007, 2)):
            fixture = directory / "driver"
            fixture.write_bytes(struct.pack(endian + "III", magic, 1, cpu) + bytes(stride - 4))
            check(["--driver-status", fixture], expected)
    for endian in (">", "<"):
        for cpu, expected in ((0x0100000c, 0), (0x01000007, 2)):
            fixture.write_bytes(struct.pack(endian + "II", 0xfeedfacf, cpu))
            check(["--driver-status", fixture], expected)
    for data in (b"", b"not a library", struct.pack(">II", 0xcafebabe, 2),
                 struct.pack(">II", 0xcafebabe, 0xffffffff)):
        fixture.write_bytes(data)
        check(["--driver-status", fixture], 2)
    check(["--driver-status", directory / "missing"], 2)

    bad = directory / "bad-package"
    bad.write_bytes(b"unreviewed code")
    check(["--verify-vendor", bad], 1)
    check(["--verify-driver", bad], 1)
    link = directory / "linked-package"
    link.symlink_to(bad)
    check(["--verify-vendor", link], 1)
    check(["--verify-driver", link], 1)

print("PASS: 21 native architecture and package-integrity checks")
