#!/usr/bin/env python3
"""Compare the two packaged hosts on the same primary screen. Requires macOS and Pillow."""
import argparse
import hashlib
import json
import os
import plistlib
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

STATES = ("panel-paused", "panel-standby", "panel-speaking")


def capture(host, app, repo, dest, tmp, helper):
    dest.mkdir()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    exe = app / "Contents/MacOS" / info["CFBundleExecutable"]
    env = dict(os.environ)
    if host == "Saytile":
        fixture = tmp / host
        fixture.mkdir()
        Image.new("RGB", (2, 2), (140, 156, 232)).save(fixture / "environment.png")
        env.update(SAYTILE_PRODUCT_WINDOWS="1", SAYTILE_PRODUCT_WINDOW_SUBSET=",".join(STATES),
                   SAYTILE_SHARED_VOICE_COMPARISON="1")
        args = ["--data-directory", str(tmp / "saytile-empty"), "--ui-review", str(fixture)]
    else:
        session = str(uuid.uuid4())
        subprocess.run([exe, "--verify-bundled-resources", "--native-acceptance-prepare", session], cwd=repo, check=True)
        fixture = repo / "build/native-acceptance" / session
        args = ["--native-acceptance-shared-voice", session]
    result = {"bundle": info["CFBundleIdentifier"], "exeSHA256": hashlib.sha256(exe.read_bytes()).hexdigest(),
              "scenes": {}}
    with (dest / "run.log").open("w") as log:
        proc = subprocess.Popen([exe, *args], env=env, cwd=repo, stdout=log, stderr=subprocess.STDOUT)
        try:
            for scene in STATES:
                deadline = time.monotonic() + 35
                req = {}
                while time.monotonic() < deadline and proc.poll() is None:
                    file = fixture / "request.json"
                    if file.exists():
                        req = json.loads(file.read_bytes())
                        if req["scene"] == scene and req["pid"] == proc.pid:
                            break
                    time.sleep(.05)
                else:
                    raise RuntimeError(f"{host} {scene} unavailable (exit {proc.poll()}); see {dest}/run.log")
                x, y, w, h = req["glass"]
                rect = "{{%s,%s},{%s,%s}}" % (x, y, w, h)
                png = dest / (scene + "-window.png")
                run = subprocess.run([helper, host, app, str(proc.pid), str(req["window"]), str(req["backdrop"]),
                                      rect, png, scene, fixture.name], text=True, capture_output=True, timeout=18)
                if run.returncode:
                    raise RuntimeError(host + " " + scene + ": " + run.stdout + run.stderr)
                (fixture / (scene + ".done")).write_text("captured")
                meta = json.loads(run.stdout)
                x0, y0, width, height = meta["contentRelativePoints"]
                crop = tuple(round(v * 2) for v in [x0, y0, x0 + width, y0 + height])
                with Image.open(png) as im:
                    if crop[0] < 0 or crop[1] < 0 or crop[2] > im.width or crop[3] > im.height:
                        raise ValueError(f"crop outside real window {crop} : {im.size}")
                    card = im.crop(crop).convert("RGB")
                    if min(ImageStat.Stat(card).stddev) <= 3:
                        raise ValueError("empty native surface")
                    card.save(dest / (scene + ".png"))
                result["scenes"][scene] = {**meta, "glassAppKit": req["glass"], "visibleAppKit": req["visible"]}
            if proc.wait(timeout=18):
                raise RuntimeError("host exited with an error")
        finally:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=10)
    return result


def main():
    arg = argparse.ArgumentParser()
    for name in ("saytile-app", "nearpane-app", "nearpane-repo", "output"):
        arg.add_argument("--" + name, required=True, type=Path)
    c = arg.parse_args()
    say = Path(__file__).resolve().parents[1]
    near = c.nearpane_repo.resolve()
    out = c.output.resolve()
    out.mkdir(exist_ok=False)
    report = {"stateSource": "synthetic capture state and text in separate disposable SQLite stores",
              "capture": "WindowServer, only the two identified windows of each launched fixture, 2 pixels/point"}
    with tempfile.TemporaryDirectory(prefix="shared-voice-proof-") as tmpname:
        tmp = Path(tmpname)
        helper = tmp / "capture"
        subprocess.run(["swiftc", "-parse-as-library", "-swift-version", "6", str(say / "tests/fixtures/SharedVoiceWindowCapture.swift"),
                        "-o", helper], check=True)
        for host, app, repo in [("Saytile", c.saytile_app, say), ("Nearpane", c.nearpane_app, near)]:
            report[host] = capture(host, app.resolve(), repo, out / host, tmp, helper)
            (out / "comparison.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    compare(out, report)


def compare(out, report):
    failures = []
    wanted = dict(zip(STATES, ("暂停", "待命", "正在识别")))
    # Tolerances apply only to these identical synthetic scenes on controlled lavender backdrops.
    report["tolerances"] = {"rgbMeanAbsoluteDifferencePer8BitChannel": 3,
                            "glassAndAXFramePoints": 0.5}
    report["comparison"] = {}
    for state in STATES:
        rows = [report[n]["scenes"][state] for n in ("Saytile", "Nearpane")]
        delta = [abs(x - y) for x, y in zip(rows[0]["glassAppKit"], rows[1]["glassAppKit"])]
        a, b = [Image.open(out / n / (state + ".png")).convert("RGB") for n in ("Saytile", "Nearpane")]
        w, h = min(a.width, b.width), min(a.height, b.height)
        diff = ImageChops.difference(a.crop((0, 0, w, h)), b.crop((0, 0, w, h)))
        mean = ImageStat.Stat(diff).mean
        red, green, blue = diff.split()
        histogram = ImageChops.lighter(ImageChops.lighter(red, green), blue).histogram()
        side = Image.new("RGB", (a.width + b.width, max(a.height, b.height)))
        side.paste(a)
        side.paste(b, (a.width, 0))
        side.save(out / (state + "-pair.png"))
        report["comparison"][state] = dict(geometryDeltaPoints=delta, rasterSizes=[a.size, b.size],
                commonPixelRGBMeanAbsoluteDifference=mean, commonDifferentPixelFraction=1-histogram[0]/(w*h),
                fractionWithAnyChannelDeltaAbove8=sum(histogram[9:])/(w*h))
        if max(delta) > 0.5 or a.size != b.size:
            failures.append(f"{state}: glass or raster geometry")
        if max(mean) > 3:
            failures.append(f"{state}: controlled-backdrop material mismatch (RGB MAE {mean})")
        first, second = [row["accessibility"] for row in rows]
        for host, ax in zip(("Saytile", "Nearpane"), (first, second)):
            if ax.get("status") != "PASS" or ax.get("voiceAXValue") != wanted[state]:
                failures.append(f"{host} {state}: AX state, selection or copy")
        for element in ("panel.transcript", "panel.copy", "panel.capture"):
            frames = [ax.get("framesRelativeToGlassTopLeft", {}).get(element, []) for ax in (first, second)]
            if any(len(frame) != 4 for frame in frames) or any(abs(x-y) > 0.5 for x, y in zip(*frames)):
                failures.append(f"{state}: AX frame {element}")
        for attr in ("observedTextFont", "observedTextPointSize"):
            if not first.get(attr) or first[attr] != second.get(attr):
                failures.append(f"{state}: {attr}")
    report["result"] = "FAIL" if failures else "PASS"
    report["failures"] = failures
    (out / "comparison.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if failures:
        raise SystemExit("\n".join(failures))


if __name__ == "__main__":
    main()
