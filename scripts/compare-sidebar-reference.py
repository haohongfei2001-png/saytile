#!/usr/bin/env python3
"""Compare real paired WindowServer captures with the user-supplied Nearpane artwork.

Every displayed product image is the original capture, uniformly scaled to a common outer width.
The supplied artwork is used only in this offline report and never as a native window's content.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REFERENCE = "c15bc20b8bd33e1f99f21638b81234748d1e17f2c3aefea518d9c2989e750ca2"
OUTER = (1347, 29, 1672, 941)
VOICE = (1362, 54, 1657, 195)
TRAY = (1362, 210, 1657, 389)
SPACES = (1362, 406, 1657, 909)
STATE = "panel-speaking"


def normalized(rect, outer):
    return [(rect[i] - outer[i % 2]) / (outer[2] - outer[0]) for i in range(4)]


def rect(xywh):
    x, y, w, h = xywh
    return (x, y, x + w, y + h)


def scaled(image, width):
    return image.resize((width, round(image.height * width / image.width)), Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", required=True, type=Path)
    parser.add_argument("--capture", required=True, type=Path)
    opt = parser.parse_args()
    ref_hash = hashlib.sha256(opt.reference.read_bytes()).hexdigest()
    if ref_hash != REFERENCE:
        raise ValueError("Measured reference coordinates belong to a different original image")
    capture = opt.capture
    report = json.loads((capture / "comparison.json").read_text())
    with Image.open(opt.reference) as original:
        authority = original.crop(OUTER).convert("RGB")
    rendered = [authority]
    for host in ("Nearpane", "Saytile"):
        with Image.open(capture / host / (STATE + "-window.png")) as native:
            rendered.append(native.convert("RGB"))
    panels = [scaled(img, 325) for img in rendered]
    font = ImageFont.truetype("/System/Library/Fonts/STHeiti Medium.ttc", 20)
    caption = ImageFont.truetype("/System/Library/Fonts/STHeiti Light.ttc", 15)
    gap = 24
    output = Image.new("RGB", (3 * 325 + 4 * gap, max(im.height for im in panels) + 110), "white")
    pen = ImageDraw.Draw(output)
    for i, (image, name, description) in enumerate(zip(panels, ("效果图", "Nearpane 实机", "Saytile 实机"),
            ("原图侧栏裁切", "隔离资料 · 四个测试窗口", "独立语音板 · 相同文字"))):
        x = gap + i * (325 + gap)
        pen.text((x, 12), name, fill="#151722", font=font)
        pen.text((x, 41), description, fill="#4c4e57", font=caption)
        output.paste(image, (x, 72))
    output.save(capture / "reference-and-native.png", optimize=True)

    # This crop preserves the rail edge and both gutters. Only the lower Nearpane modules are omitted.
    full_height = rendered[2].height
    near_slot = rendered[1].crop((0, 0, rendered[1].width, full_height))
    pair = Image.new("RGB", (3 * gap + 2 * rendered[2].width, full_height + 76), "white")
    draw = ImageDraw.Draw(pair)
    for i, (image, label) in enumerate(((rendered[2], "Saytile"), (near_slot, "Nearpane 顶部"))):
        x = gap + i * (gap + rendered[2].width)
        draw.text((x, 12), label, fill="#151722", font=font)
        pair.paste(image, (x, 52))
    pair.save(capture / "default-hosts-top.png", optimize=True)

    # Report screen-, card- and rail-relative proportions independently.
    # The panel and menu bar in the artwork are artist estimates, not a macOS logical point readout.
    data = dict(referenceSHA256=ref_hash, referenceImagePixels=[1672, 941],
                referenceOuterPixelRect=OUTER, referenceVoicePixelRect=VOICE,
                referenceTrayPixelRect=TRAY, referenceWorkspacePixelRect=SPACES,
                referencePaneWidthFraction=(OUTER[2] - OUTER[0]) / 1672,
                referenceVoiceAspect=(VOICE[2] - VOICE[0]) / (VOICE[3] - VOICE[1]),
                referenceInnerRelativeToOuterWidth=normalized(VOICE, OUTER),
                composite="All three images uniformly scaled to 325 pixels outer width",
                nativeHosts={})
    for name in ("Saytile", "Nearpane"):
        scene = report[name]["scenes"][STATE]
        outer = scene["windowCG"]
        glass = scene["contentRelativePoints"]
        data["nativeHosts"][name] = dict(outerCG=outer, innerRelativeCG=glass,
                widthFraction=outer[2] / scene["visibleAppKit"][2],
                relativeToRailWidth=normalized(rect(glass), (0, 0, outer[2], outer[3])),
                voiceAspect=glass[2] / glass[3], imagePixels=[scene["widthPX"], scene["heightPX"]],
                physicalDisplayBackingScale=scene["backingScale"])
    data["nativeHosts"]["Nearpane"]["workspaceThumbnailAXCount"] = report["Nearpane"]["scenes"][STATE].get("workspaceThumbnailAXCount")
    if "artworkWidthNearpane" in report:
        with Image.open(capture / "Nearpane-artwork-width" / (STATE + "-window.png")) as im:
            native = scaled(im.convert("RGB"), 325)
        pair = Image.new("RGB", (3 * gap + 650, max(authority.height, native.height) + 96), "white")
        draw = ImageDraw.Draw(pair)
        for i, (image, label) in enumerate(((authority, "用户效果图"), (native, "Nearpane 原生窗口"))):
            x = gap + i * (gap + 325)
            draw.text((x, 14), label, fill="#151722", font=font)
            draw.text((x, 44), "占屏宽 19.44%", fill="#4c4e57", font=caption)
            pair.paste(image, (x, 71))
        pair.save(capture / "reference-and-artwork-width.png", optimize=True)
        scene = report["artworkWidthNearpane"]["scenes"][STATE]
        data["artworkWidthNearpane"] = {
            "outerCG": scene["windowCG"], "visibleAppKit": scene["visibleAppKit"],
            "voiceAspect": scene["contentRelativePoints"][2] / scene["contentRelativePoints"][3],
            "workspaceThumbnailAXCount": scene.get("workspaceThumbnailAXCount"),
        }
    (capture / "reference-metrics.json").write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(capture / "reference-and-native.png")


if __name__ == "__main__":
    main()
