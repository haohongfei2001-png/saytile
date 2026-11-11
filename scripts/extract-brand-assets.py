#!/usr/bin/env python3
"""Package the confirmed artwork for macOS. No font, redrawn logo or extra icon plate."""
import hashlib
import math
import pathlib
import struct
import subprocess
import tempfile
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
ART = ROOT / "design/approved/app-icon/Saytile-AppIcon-Approved-2026-11-10.webp"
if hashlib.sha256(ART.read_bytes()).hexdigest() != "607fe0dca53a186835a35e82b0c9241975e11b9e3481e6dfb11502fe60d5f35c":
    raise ValueError("The artwork or its geometry changed; recheck the native extractions.")
with tempfile.TemporaryDirectory() as scratch:
    bitmap = pathlib.Path(scratch) / "art.bmp"
    subprocess.run(["/usr/bin/sips", "-s", "format", "bmp", str(ART), "--out", str(bitmap)],
                   check=True, stdout=subprocess.DEVNULL)
    source = bitmap.read_bytes()
offset, = struct.unpack_from("<I", source, 10)
width, height = struct.unpack_from("<ii", source, 18)
bits, = struct.unpack_from("<H", source, 28)
if width != 512 or abs(height) != 512 or bits not in (24, 32):
    raise ValueError("Unexpected source layout")

def rgb(x, y):
    pos = offset + (y if height < 0 else 511-y) * ((width*bits+31)//32*4) + x*(bits//8)
    return source[pos+2], source[pos+1], source[pos]

def clamp(x, hi=1):
    return min(hi, max(0, x))

def rgba(pixel, matte, a):
    if a <= 1/255:
        return (0, 0, 0, 0)
    return (*[round(clamp(m+(c-m)/a, 255)) for c,m in zip(pixel, matte)], round(255*a))

def save(path, w, h, pixels):
    def chunk(tag, data):
        return struct.pack(">I",len(data)) + tag + data + struct.pack(">I",zlib.crc32(tag+data))
    raw = b"".join(b"\0"+bytes(v for x in range(w) for v in pixels(x,y)) for y in range(h))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR",struct.pack(">IIBBBBB",w,h,8,6,0,0,0)) +
                     chunk(b"sRGB",b"\0") + chunk(b"IDAT",zlib.compress(raw,9)) + chunk(b"IEND",b""))

# Follow the actual plate edge in the reference, including its uneven corner radii.
# The rounded box is only a search band for the measured light-to-shadow transition.
cx, cy, count = 254, 251, 720
def approximate_edge(x, y):
    qx, qy = abs(x-cx)-(160-90), abs(y-cy)-(162-90)
    return math.hypot(max(0,qx),max(0,qy)) + min(max(qx,qy),0) - 90

def luma(x, y):
    ix, iy = int(x), int(y)
    fx, fy = x-ix, y-iy
    return sum(a*b*rgb(ix+i,iy+j)[1] for i,a in [(0,1-fx),(1,fx)] for j,b in [(0,1-fy),(1,fy)])

radii = []
for i in range(count):
    angle = i*math.tau/count
    dx, dy = math.cos(angle), math.sin(angle)
    guess = next(t for t in range(145,230) if approximate_edge(cx+t*dx,cy+t*dy)>=0)
    def strength(t):
        return luma(cx+(t-1.5)*dx,cy+(t-1.5)*dy)-luma(cx+(t+1.5)*dx,cy+(t+1.5)*dy)
    radii.append(max((guess+j/4 for j in range(-32,33)), key=strength))
# Subpixel compression noise is not a feature of the silhouette.
edge = [sorted(radii[(i+k)%count] for k in (-1,0,1))[1] for i in range(count)]
back = rgb(0,0)
under = rgb(253,415)
# Estimate the shadow ink from its darkest unobstructed sample. At near-zero alpha,
# unmatting three independently compressed color channels otherwise creates bright blue speckles.
shadow = tuple(round(clamp(b+(s-b)/0.22,255)) for b,s in zip(back,under))
def icon(x, y):
    x, y = x+54, y+51
    sample = rgb(x,y)
    theta = math.atan2(y-cy,x-cx)%math.tau * count/math.tau
    i = int(theta)%count
    radius = edge[i]+(edge[(i+1)%count]-edge[i])*(theta-int(theta))
    coverage = clamp(radius-math.hypot(x-cx,y-cy)+0.5)
    # Unmatte the photograph's own shadow; constant presentation-canvas pixels disappear.
    shade = clamp((back[1]-sample[1]-1)/(back[1]-shadow[1]))
    if coverage == 0:
        return (*shadow,round(255*shade)) if shade > 1/255 else (0,0,0,0)
    return rgba(sample,back,coverage+(1-coverage)*shade)

save(ROOT/"packaging/brand/SaytilePlate.png",400,400,icon)

# Extract colored strokes against the measured face either side of the lettering.
# Local normalization keeps the pale e just as legible as the darker l in template mode.
def face(x,y):
    left,right = rgb(166,y),rgb(326,y)
    return tuple(a + (b-a)*clamp((x-166)/160) for a,b in zip(left,right))
def contrast(x,y):
    return face(x,y)[1]-rgb(x,y)[1]
signal = {(x,y):contrast(x,y) for y in range(154,339) for x in range(165,328)}
def mark(x,y):
    x,y = x+171,y+161
    d = signal[x,y]
    if d<=8:
        return (0,0,0,0)
    peak = max(signal[a,b] for a in range(x-4,x+5) for b in range(y-4,y+5))
    alpha = clamp((d-8)/(max(48,peak*0.97)-8))
    return rgba(rgb(x,y),face(x,y),alpha)

save(ROOT/"Sources/SaytileApp/Resources/SaytileBrandMark.png",152,172,mark)
