#!/usr/bin/env python3
"""Deterministic bitmap derivatives of the user's selected second image.

No typesetting, new gradient, redraw, or recoloring of the approved lettering.
The WebP is a full-resolution Q95 transport derivative, not the original PNG.
Pillow is required only to regenerate checked-in PNG resources, not at runtime.
"""
from pathlib import Path
import hashlib
import json
import math
import shutil
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'design/approved/app-icon/Saytile-Black-Option2-1254.webp'
SOURCE_SHA = 'addaddcd994a866914da5793e48ac363573319353f93b17d179b3be9efd58057'
ORIGINAL_SHA = 'aed18390cffd1df6333b526d5ba0364f6352ef8313c6035f44cba707a9362024'
RES = ROOT / 'Sources/SaytileApp/Resources'

def clamp(v):
    return min(1.0, max(0.0, v))

def build():
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != SOURCE_SHA:
        raise ValueError('Selected option 2 source does not match its manifest')
    art = Image.open(SOURCE).convert('RGB')
    if art.size != (1254, 1254):
        raise ValueError('Unexpected source dimensions')
    # Tight, measured crop around the uploaded lettering, with a 4 px AA margin.
    crop = (416, 396, 790, 814)
    mark = art.crop(crop)
    g = mark.convert('L')
    minimum = g.filter(ImageFilter.MinFilter(7))
    glyph = Image.new('RGBA', mark.size)
    night = Image.new('RGBA', mark.size)
    for y in range(mark.height):
        for x in range(mark.width):
            pixel = mark.getpixel((x, y))
            gray = g.getpixel((x, y))
            low = minimum.getpixel((x, y))
            # The photograph's almost-white canvas is not logo ink. Local
            # coverage separates edge AA from the much darker letter interior.
            if low >= 155 or gray > 250:
                continue
            alpha = 1.0 if gray < 155 else clamp((255 - gray) / (255 - low))
            if alpha <= 1 / 255:
                continue
            ink = tuple(round(min(255, max(0, 255 + (v - 255) / alpha))) for v in pixel)
            glyph.putpixel((x, y), (*ink, round(alpha * 255)))
            night.putpixel((x, y), (*(255 - v for v in ink), round(alpha * 255)))
    RES.mkdir(parents=True, exist_ok=True)
    glyph.save(RES / 'SaytileBlackBrandMark.png', optimize=True)
    night.save(RES / 'SaytileBlackBrandMarkDark.png', optimize=True)

    # Recover the actual white tile edge, rather than drawing a new rounded box.
    # Coordinates follow this selected image, not the earlier purple source.
    lum = art.convert('L').filter(ImageFilter.GaussianBlur(1.6))
    cx, cy, count = 623, 614, 1440
    def sample(x, y):
        ix, iy = int(x), int(y)
        fx, fy = x - ix, y - iy
        return sum(a * b * lum.getpixel((ix + i, iy + j))
                   for i, a in ((0, 1 - fx), (1, fx))
                   for j, b in ((0, 1 - fy), (1, fy)))
    def distance(x, y):
        qx, qy = abs(x - cx) - (394 - 222), abs(y - cy) - (398 - 222)
        return math.hypot(max(0, qx), max(0, qy)) + min(max(qx, qy), 0) - 222
    radii = []
    for i in range(count):
        angle = i * math.tau / count
        dx, dy = math.cos(angle), math.sin(angle)
        guess = next(t for t in range(370, 560) if distance(cx + t * dx, cy + t * dy) >= 0)
        def strength(t):
            return sample(cx + (t - 2) * dx, cy + (t - 2) * dy) - sample(cx + (t + 2) * dx, cy + (t + 2) * dy)
        radii.append(max((guess + k / 2 for k in range(-30, 31)), key=strength))
    medians = [sorted(radii[(i + k) % count] for k in range(-7, 8))[7] for i in range(count)]
    weights = [(k, math.exp(-k * k / 72)) for k in range(-18, 19)]
    edges = [sum(medians[(i + k) % count] * w for k, w in weights) / sum(w for _, w in weights)
             for i in range(count)]
    # Crop presentation whitespace only. Keep the tile and its own soft shadow.
    box = (123, 114, 1123, 1114)
    plate = Image.new('RGBA', (1000, 1000))
    for yy in range(1000):
        y = yy + box[1]
        for xx in range(1000):
            x = xx + box[0]
            rgb = art.getpixel((x, y))
            theta = math.atan2(y - cy, x - cx) % math.tau * count / math.tau
            i = int(theta) % count
            edge = edges[i] + (edges[(i + 1) % count] - edges[i]) * (theta - int(theta))
            coverage = clamp(edge - math.hypot(x - cx, y - cy) + 0.5)
            if coverage >= 1:
                # Retain every interior pixel, including the original gradient.
                plate.putpixel((xx, yy), (*rgb, 255))
            else:
                shade = clamp((255 - max(rgb) - 1) / 255)
                alpha = coverage + (1 - coverage) * shade
                if alpha > 1 / 255:
                    foreground = tuple(round(min(255, max(0, 255 + (v - 255) / alpha))) for v in rgb)
                    plate.putpixel((xx, yy), (*foreground, round(255 * alpha)))
    plate.save(RES / 'SaytileBlackPlate.png', optimize=True)
    shutil.copyfile(ROOT / 'packaging/brand/SaytilePlate.png', RES / 'SaytilePurplePlate.png')
    manifest = {
        'selection': 'user-uploaded comparison image 2, not a newly generated design',
        'original_png_sha256': ORIGINAL_SHA,
        'original_png_dimensions': [1254, 1254],
        'transport': {'file': str(SOURCE.relative_to(ROOT)), 'sha256': SOURCE_SHA,
                      'encoding': 'full-resolution WebP quality 95; not lossless original',
                      'mean_absolute_rgb_error_8bit_vs_original': 0.39190825403366325,
                      'max_absolute_rgb_error_8bit_vs_original': 8},
        'derivation': {'mark_crop': list(crop), 'plate_crop': list(box),
                       'dark_mark': 'invert glyph RGB only, preserve alpha; white icon unchanged'},
        'resources': {p.name: {'sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
                              'size': list(Image.open(p).size)}
                      for p in sorted(RES.glob('Saytile*png'))}
    }
    path = ROOT / 'design/approved/app-icon/black-option2-manifest.json'
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print('Prepared approved option-2 resources with checked source and provenance')

if __name__ == '__main__':
    build()
