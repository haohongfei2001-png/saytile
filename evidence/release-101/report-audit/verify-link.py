"""Read-only recheck of the retrospective fixture/library link; never runs either CLI."""
import hashlib
import json
from pathlib import Path
import struct


def normalized(data):
    data = bytearray(data)
    assert struct.unpack_from("<I", data)[0] == 0xFEEDFACF
    commands = struct.unpack_from("<I", data, 16)[0]
    offset, signature, linkedit = 32, None, None
    for _ in range(commands):
        command, size = struct.unpack_from("<II", data, offset)
        assert size >= 8 and offset + size <= len(data)
        if command == 0x1B:  # LC_UUID
            data[offset + 8:offset + 24] = bytes(16)
        if command == 0x1D:  # LC_CODE_SIGNATURE
            signature = struct.unpack_from("<II", data, offset + 8)
            data[offset + 8:offset + 16] = bytes(8)
        if command == 0x19 and bytes(data[offset + 8:offset + 24]).rstrip(b"\0") == b"__LINKEDIT":
            linkedit = offset
        offset += size
    assert signature and linkedit is not None
    end, length = signature
    assert end + length == len(data)
    file_offset = struct.unpack_from("<Q", data, linkedit + 40)[0]
    remaining = end - file_offset
    assert remaining >= 0
    struct.pack_into("<Q", data, linkedit + 48, remaining)
    struct.pack_into("<Q", data, linkedit + 32, (remaining + 16383) // 16384 * 16384)
    return bytes(data[:end])


def sha(data):
    return hashlib.sha256(data).hexdigest()


if __name__ == "__main__":
    receipt = json.loads(Path(__file__).with_name("cohort-link-retrospective.json").read_text())
    assert [row["label"] for row in receipt["arms"]] == ["baseline", "current"]
    for row in receipt["arms"]:
        assert row["exit_code"] == 0
        assert sha(Path(row["library"]).read_bytes()) == row["library_sha256"]
        fixture = next(s for s in row["command"] if s.endswith("/MandarinCohort.swift"))
        assert sha(Path(fixture).read_bytes()) == row["fixture_sha256"]
        original, relinked = (Path(row[k]).read_bytes() for k in ("original", "output"))
        assert sha(original) == row["original_sha256"]
        assert sha(relinked) == row["output_sha256"]
        assert normalized(original) == normalized(relinked)
        assert sha(normalized(original)) == row["normalized_sha256_original"] == row["normalized_sha256_relinked"]
        print(row["label"], "PASS: binary matches preserved library/fixture after metadata-only normalization")
