"""Compare signed-worker checked previews with independent scalar EOS at equal PCM endpoints.

This is a direct worker experiment. It does not run the app, record audio, or
measure native window latency. Every compared hypothesis is bound to a verified
decode at exactly the same input frame as the new scalar EOS.
"""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import plistlib
import runpy
import select
import struct
import subprocess
import time
import unicodedata
import wave

ALLOWED_STDOUT = {
    "Found 1 safetensor files", "Loading: model.safetensors",
    "Applied weights to audio encoder (18 layers, 301 tensors)",
    "Applied weights to text decoder (28 layers, 704 tensors)",
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def difference(a, b):
    return [{"operation": op, "preview": a[i:j], "scalar": b[k:l],
             "preview_range": [i, j], "scalar_range": [k, l]}
            for op, i, j, k, l in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes()
            if op != "equal"]


def read_pcm(path, expected, limit=None):
    assert digest(path.read_bytes()) == expected
    with wave.open(str(path)) as audio:
        assert (audio.getnchannels(), audio.getframerate(), audio.getsampwidth()) == (1, 16000, 2)
        count = audio.getnframes()
        pcm = audio.readframes(count if limit is None else min(count, limit))
    return pcm, count


def inputs(args):
    short = json.loads(args.paired.read_text())["samples"]
    assert len(short) == 15 and len({r["id"] for r in short}) == 15
    extended = json.loads(args.extended_manifest.read_text())["samples"]
    pairs = [(r, args.audio, None) for r in short]
    for ident in ("fleurs-f8646a257c0c4273", "continuous-public-5"):
        case = next(r for r in extended if r["id"] == ident)
        pairs.append((case, args.extended_audio, 480000))
    cases = []
    for row, folder, limit in pairs:
        pcm, original = read_pcm(folder / (row["id"] + ".wav"), row["audio_sha256"], limit)
        total = len(pcm) // 2
        assert 12800 <= total <= 480000
        # Every later packet supplies at least one new 0.5 s stride. The end
        # is the real file end (or exactly 30 s); no silence is synthesized.
        prefixes = [12800]
        for at in (52800, int(total * .60), total - 8000):
            if at >= prefixes[-1] + 8000 and at <= total - 8000:
                prefixes.append(at)
        prefixes.append(total)
        assert all(b - a >= 8000 for a, b in zip(prefixes, prefixes[1:]))
        cases.append({
            "id": row["id"], "audio_sha256": row["audio_sha256"],
            "pcm_sha256": digest(pcm), "frames": total, "seconds": total / 16000,
            "original_frames": original, "full_reference_available": total == original,
            "reference": row["reference"] if total == original else None,
            "prefixes": prefixes, "pcm": pcm,
        })
    return cases


class Pipe:
    def __init__(self, process, deadline):
        self.process, self.deadline = process, deadline
        self.events, self.extra, self.stderr = [], [], bytearray()
        self.pending = bytearray()
        for stream in (process.stdin, process.stdout, process.stderr):
            os.set_blocking(stream.fileno(), False)

    def pump(self, wait=0):
        if time.monotonic() >= self.deadline:
            raise TimeoutError("overall experiment budget exhausted")
        readable, _, _ = select.select([self.process.stdout, self.process.stderr], [], [], wait)
        for stream in readable:
            try:
                block = os.read(stream.fileno(), 65536)
            except BlockingIOError:
                continue
            if stream is self.process.stderr:
                self.stderr.extend(block)
                continue
            self.pending.extend(block)
            while b"\n" in self.pending:
                line, _, self.pending = self.pending.partition(b"\n")
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except ValueError:
                    text = line.decode(errors="replace")
                    if text not in ALLOWED_STDOUT:
                        raise RuntimeError("unexpected worker stdout: " + text)
                    self.extra.append(text)
                else:
                    assert isinstance(event, dict) and "kind" in event
                    self.events.append(event)

    def send(self, payload):
        wire = memoryview(struct.pack("<I", len(payload)) + payload)
        while wire:
            if self.process.poll() is not None:
                raise RuntimeError("worker exited before all PCM was written")
            self.pump()
            _, writable, _ = select.select([], [self.process.stdin], [], .025)
            if writable:
                try:
                    sent = os.write(self.process.stdin.fileno(), wire)
                except BlockingIOError:
                    continue
                wire = wire[sent:]

    def prefix(self, pcm, old, new):
        for begin in range(old, new, 16000):
            self.send(pcm[2 * begin:2 * min(begin + 16000, new)])

    def wait_for(self, predicate, duration):
        until = min(self.deadline, time.monotonic() + duration)
        while not predicate() and time.monotonic() < until:
            self.pump(min(.05, max(0, until - time.monotonic())))
        return bool(predicate())


def assess(case, events, scoring):
    final = next(e for e in reversed(events) if e["kind"] == "final")
    assert final["frames"] == case["frames"]
    traces = [d for e in events for d in e.get("decodes", [])]
    previews = [d for d in traces if not d["final"] and d["frames"] == case["frames"]]
    scalar = [d for d in traces if d["final"] and d["frames"] == case["frames"]]
    out = {k: v for k, v in case.items() if k != "pcm"}
    out.update(events=events, scalar_text=final["text"],
               scalar_text_sha256=digest(final["text"].encode()),
               scalar_reference_CER=scoring["rating"](case["reference"], final["text"])
                   if case["reference"] is not None else None)
    if len(previews) != 1 or len(scalar) != 1:
        out.update(status="NOT_COMPARABLE", reason="exact_endpoint_preview_or_new_scalar_missing",
                   preview_decode_count=len(previews), scalar_decode_count=len(scalar))
        return out
    preview, end = previews[0], scalar[0]
    assert end.get("verifiedPreviewTokens", 0) == 0
    assert end["startUptime"] >= preview["endUptime"]
    partials = [e for e in events if e["kind"] == "partial" and e["frames"] <= case["frames"]]
    emitted = next((e for e in reversed(partials) if e["frames"] == case["frames"]), None)
    if emitted:
        text, origin = emitted["text"], "exact_endpoint_partial"
    elif not preview["changed"] and partials:
        # Worker.swift emits only changed text and leaves last intact. A
        # changed=false decode proves this text for the exact endpoint PCM.
        text, origin = partials[-1]["text"], "unchanged_exact_endpoint_decode_proves_last_partial"
    else:
        out.update(status="NOT_COMPARABLE", reason="endpoint_text_not_observable",
                   endpoint_preview=preview, scalar_decode=end)
        return out
    norm = scoring["norm"]
    punct = lambda value: "".join(c for c in value if unicodedata.category(c).startswith("P"))
    out.update(status="COMPARED_VERIFIED" if preview.get("verifiedPreviewTokens", 0) > 0 else "COMPARED_NO_ACCEPTED_PREFIX",
               preview_text=text, preview_text_source=origin,
               preview_text_sha256=digest(text.encode()),
               preview_decode=preview, scalar_decode=end,
               preview_decode_seconds=preview["endUptime"]-preview["startUptime"],
               scalar_decode_seconds=end["endUptime"]-end["startUptime"],
               exact_text_equal=text == final["text"],
               normalized_text_equal=norm(text) == norm(final["text"]),
               normalized_char_edits=scoring["align"](norm(text), norm(final["text"])),
               raw_differences=difference(text, final["text"]),
               normalized_differences=difference(norm(text), norm(final["text"])),
               punctuation_differences=difference(punct(text), punct(final["text"])),
               preview_reference_CER=scoring["rating"](case["reference"], text)
                   if case["reference"] is not None else None)
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("app", "weights", "paired", "audio", "extended-manifest", "extended-audio", "model-manifest", "scorer", "out"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--max-seconds", type=float, default=120)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    cases = inputs(args)
    info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    assert info["SaytileSourceRevision"] == args.sha
    helper = args.app / "Contents/Helpers/SaytileModelWorker"
    revision = json.loads(args.model_manifest.read_text())["revision"]
    assert (args.weights / "qwen-small" / revision / "model.safetensors").is_file()
    report = dict(source=args.sha, build=info["CFBundleVersion"],
                  helper_sha256=digest(helper.read_bytes()), model_revision=revision,
                  mode="Direct signed worker, same original PCM endpoint, independently recomputed scalar EOS",
                  prepared_cases=[{k:v for k,v in c.items() if k not in ("pcm", "reference")} for c in cases],
                  microphone=False, synthetic_padding=False, original_rate=False, records=[])
    args.out.parent.mkdir(parents=True, exist_ok=True)
    def save():
        args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if args.prepare_only:
        report["status"] = "PREPARED_NOT_RUN"
        save()
        print(json.dumps({"prepared": len(cases), "output": str(args.out)}))
        return
    subprocess.run(["codesign", "--verify", "--deep", "--strict", args.app], check=True)
    scoring = runpy.run_path(str(args.scorer))
    start = time.monotonic()
    worker = subprocess.Popen([helper, "qwen-small", args.weights / "qwen-small" / revision, "8000"],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0,
                              cwd=args.app / "Contents/Resources", env={**os.environ, "SAYTILE_WORKER_TIMING": "1"})
    pipe = Pipe(worker, start + args.max_seconds)
    active = None
    try:
        assert pipe.wait_for(lambda: any(e["kind"] == "ready" for e in pipe.events), 20), "ready timeout"
        for case in cases:
            active = case["id"]
            begin = len(pipe.events)
            offset = 0
            for endpoint in case["prefixes"]:
                pipe.prefix(case["pcm"], offset, endpoint)
                offset = endpoint
                # A duplicate hypothesis produces no event. Bound this wait and
                # recover its exact text only from a later changed=false trace.
                pipe.wait_for(lambda: any(e["kind"] == "partial" and e["frames"] == endpoint
                                          for e in pipe.events[begin:]),
                              1.20 if endpoint == case["frames"] else .25)
            pipe.send(b"")
            if not pipe.wait_for(lambda: any(e["kind"] == "final" for e in pipe.events[begin:]), 20):
                raise TimeoutError("scalar EOS timeout")
            row = assess(case, pipe.events[begin:], scoring)
            report["records"].append(row)
            print(json.dumps({"id": active, "status": row["status"],
                              "equal": row.get("normalized_text_equal")}), flush=True)
            save()
            active = None
        report["status"] = "COMPLETE"
    except (TimeoutError, AssertionError, RuntimeError) as error:
        report.update(status="INCOMPLETE", failed_case=active, failure=str(error),
                      failed_case_raw_events=pipe.events[begin:] if active is not None else pipe.events)
        report["uncompleted_cases"] = [c["id"] for c in cases if c["id"] not in {r["id"] for r in report["records"]}]
    finally:
        worker.stdin.close()
        if report.get("status") != "COMPLETE" and worker.poll() is None:
            worker.terminate()
        try:
            worker.wait(timeout=5)
        except subprocess.TimeoutExpired:
            worker.kill()
            worker.wait()
        try:
            pipe.deadline = time.monotonic() + 1
            pipe.pump(0)
        except (RuntimeError, AssertionError, TimeoutError):
            pass
        report.update(wall_seconds=time.monotonic()-start, worker_exit=worker.returncode,
                      stdout_messages=pipe.extra, stderr=bytes(pipe.stderr).decode(errors="replace"))
        save()
    print(json.dumps({"status": report["status"], "completed": len(report["records"]),
                      "wall_seconds": report["wall_seconds"], "output": str(args.out)}), flush=True)


if __name__ == "__main__":
    main()
