"""Exercise the installed icon format using macOS ImageIO and IconServices."""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)


def pixels(image, bitmap):
    run("/usr/bin/sips", "-s", "format", "bmp", image, "--out", bitmap)
    data = bitmap.read_bytes()
    offset, = struct.unpack_from("<I", data, 10)
    width, height = struct.unpack_from("<ii", data, 18)
    depth, = struct.unpack_from("<H", data, 28)
    assert depth == 32
    return width, abs(height), data[offset:offset + width * abs(height) * 4]


@unittest.skipUnless(sys.platform == "darwin", "Uses macOS icon tools")
class ProductIcon(unittest.TestCase):
    def test_packaged_face_and_small_finder_sizes(self):
        plate = ROOT / "packaging/brand/SaytilePlate.png"
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            source = tmp / "Saytile.iconset"
            decoded = tmp / "decoded.iconset"
            source.mkdir()
            for size in (16, 32, 128, 256, 512):
                for scale, suffix in ((1, ""), (2, "@2x")):
                    side = str(size * scale)
                    run("/usr/bin/sips", "-z", side, side, plate, "--out", source / f"icon_{size}x{size}{suffix}.png")
            icon = tmp / "Saytile.icns"
            run(sys.executable, ROOT / "scripts/encode-iconset.py", source, icon)
            run("/usr/bin/iconutil", "-c", "iconset", icon, "-o", decoded)
            self.assertEqual({p.name for p in source.iterdir()}, {p.name for p in decoded.iterdir()})
            for rendition in source.iterdir():
                with self.subTest(rendition=rendition.name):
                    w, h, actual = pixels(decoded / rendition.name, tmp / "actual.bmp")
                    for x, y in ((0.30, 0.25), (0.70, 0.75)):
                        offset = 4 * (int(h * y) * w + int(w * x))
                        self.assertEqual(actual[offset:offset + 4], bytes([255] * 4))
                    if rendition.name in ("icon_16x16.png", "icon_32x32.png"):
                        _, _, expected = pixels(rendition, tmp / "expected.bmp")
                        self.assertEqual(actual[3::4], expected[3::4])
                        for i in range(0, len(actual), 4):
                            if actual[i + 3]:
                                self.assertEqual(actual[i:i+3], expected[i:i+3])


if __name__ == "__main__":
    unittest.main()
