#!/usr/bin/env python3
"""Encode our PNG iconset when iconutil is unavailable in a restricted build host."""
import pathlib
import struct
import subprocess
import sys
import tempfile

source, output = map(pathlib.Path, sys.argv[1:])
representations = [
    (b"icp4", 16, "icon_16x16.png"),
    (b"ic11", 32, "icon_16x16@2x.png"),
    (b"icp5", 32, "icon_32x32.png"),
    (b"ic12", 64, "icon_32x32@2x.png"),
    (b"ic07", 128, "icon_128x128.png"),
    (b"ic13", 256, "icon_128x128@2x.png"),
    (b"ic08", 256, "icon_256x256.png"),
    (b"ic14", 512, "icon_256x256@2x.png"),
    (b"ic09", 512, "icon_512x512.png"),
    (b"ic10", 1024, "icon_512x512@2x.png"),
]
def small_icon_chunks(path, size):
    # IconServices reads the small 1x images as native color planes with an alpha mask.
    # ImageIO (via sips) can encode these even when iconutil has no window session.
    with tempfile.TemporaryDirectory() as scratch:
        encoded = pathlib.Path(scratch) / "small.icns"
        subprocess.run(["/usr/bin/sips", "-s", "format", "icns", str(path), "--out", str(encoded)],
                       check=True, stdout=subprocess.DEVNULL)
        data = encoded.read_bytes()
    offset = 8
    parts = {}
    while offset < len(data):
        kind, length = struct.unpack_from(">4sI", data, offset)
        if length < 8 or offset + length > len(data):
            raise ValueError(f"Invalid ICNS representation for {path.name}")
        parts[kind] = data[offset:offset + length]
        offset += length
    argb, rgb, mask = (b"ic04", b"is32", b"s8mk") if size == 16 else (b"ic05", b"il32", b"l8mk")
    if argb in parts:
        return [parts[argb]]
    return [parts[rgb], parts[mask]]


chunks = []
for kind, size, name in representations:
    png = (source / name).read_bytes()
    if png[:8] != b"\x89PNG\r\n\x1a\n" or png[12:16] != b"IHDR" or struct.unpack(">II", png[16:24]) != (size, size):
        raise ValueError(f"Invalid PNG dimensions: {name}")
    if kind in (b"icp4", b"icp5"):
        chunks.extend(small_icon_chunks(source / name, size))
        continue
    chunks.append(kind + struct.pack(">I", len(png) + 8) + png)
payload = b"".join(chunks)
output.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
