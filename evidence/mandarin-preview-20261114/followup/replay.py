"""Reproduce the 120 fixed-event comparison using checked-in public fixtures and the two actual Swift gates."""
import hashlib
import json
from collections import Counter
from pathlib import Path
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
BASE = "ff8f8a014bd6b554a5703971a1139d94da155a6c"
CANDIDATE = "0dc6ed70e873ec41da3b1dd24f47350a91211a43"
EXPECTED = json.loads((HERE / "fixed-events.json").read_text())
score = runpy.run_path(str(ROOT / "scripts/mandarin/compare-preview-cost.py"))

HARNESS = """
struct Event: Codable { let kind: String; let text: String; let t: Double }
let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let traces = try JSONDecoder().decode([String: [Event]].self, from: input)
var results = [String: [Event]]()
for (key, events) in traces {
    var gate = LocalLiveText(model: .qwen)
    var archived = ""
    var output = [Event]()
    for e in events where e.kind == "partial" || e.kind == "final" {
        let final = e.kind == "final"
        if !e.text.isEmpty, gate.accept(e.text, final: final) != nil {
            output.append(Event(kind: e.kind, text: archived + gate.presentation, t: e.t))
        }
        if final {
            archived += e.text
            gate = LocalLiveText(model: .qwen)
        }
    }
    results[key] = output
}
FileHandle.standardOutput.write(try JSONEncoder().encode(results))
"""


def source(revision, file, declaration):
    text = subprocess.check_output(["git", "-C", ROOT, "show", f"{revision}:Sources/SaytileKit/{file}.swift"], text=True)
    return declaration + text.split(declaration, 1)[1].split("\n}", 1)[0] + "\n}\n"


def replay(revision, folder, inputs):
    swift = folder / "main.swift"
    swift.write_text("import Foundation\nenum LocalASRID { case qwen, qwenLarge, sherpa, nemotron }\n"
                     + source(revision, "RecognitionCandidates", "public enum RecognitionUTF16 {")
                     + source(revision, "LocalASRProvider", "struct LocalLiveText {") + HARNESS)
    executable = folder / "gate"
    subprocess.run(["swiftc", "-O", swift, "-o", executable], check=True)
    return json.loads(subprocess.check_output([executable, inputs]))


def main():
    files = {}
    wanted = set(EXPECTED["frozen_trace_files_sha256"])
    for group in ("mandarin-preview-20261114", "mandarin-cadence-20261114", "mandarin-quality-20261114"):
        for path in (ROOT / "evidence" / group).rglob("auto*.json"):
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            if digest in wanted:
                files[digest] = json.loads(data)
    assert files.keys() == wanted
    with tempfile.TemporaryDirectory() as scratch:
        folder = Path(scratch)
        inputs = folder / "raw.json"
        inputs.write_text(json.dumps({key: value["rawWorkerEvents"] for key, value in files.items()}))
        old, new = [replay(revision, folder, inputs) for revision in (BASE, CANDIDATE)]
    for key in files:
        def first(events):
            return next((e["t"], score["norm"](e["text"])) for e in events if score["norm"](e["text"]))
        assert first(old[key]) == first(new[key])
        assert [e for e in old[key] if e["kind"] == "final"] == [e for e in new[key] if e["kind"] == "final"]
    for name, events in [("old", old), ("candidate", new)]:
        totals = Counter()
        for key, stream in events.items():
            totals.update(score["edits"](stream, 0, files[key]["endOfFile"]))
        assert totals == EXPECTED[name], (name, totals)
        print(name, dict(totals))
    print(f"{len(files)} public traces: same first word/time and finals")


if __name__ == "__main__":
    main()
