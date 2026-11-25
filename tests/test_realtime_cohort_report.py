"""Fail-closed reporting with synthetic PCM only; does not start an ASR worker."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("cohort_report", ROOT / "scripts/mandarin/report-realtime-cohort.py")
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


class RealtimeCohortReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="saytile-cohort-report-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "regression-final"
        (self.root / "quality").mkdir(parents=True)
        (self.base / "setup").mkdir()
        self.audio = self.base / "wav"
        self.audio.mkdir()
        self.refs, self.rows = [], []
        for source, count in REPORT.SOURCES.items():
            for index in range(count):
                ident = f"{source}-{index}"
                path = self.audio / (ident + ".wav")
                with wave.open(str(path), "wb") as w:
                    w.setparams((1, 2, 16000, 320, "NONE", "not compressed"))
                    w.writeframes(bytes(640))
                sha = REPORT.digest(path.read_bytes())
                self.refs.append(dict(id=ident, source=source, reference="中文测试", audio_sha256=sha, duration=.02))
                self.rows.append(dict(id=ident, model="qwen-small", path="product", pacing="realtime",
                    text="中文测试", states=["completed"], errors=[], providers=["qwen-small"],
                    audioFrames=320, audioSeconds=.02, feedSeconds=.021,
                    maximumFeedLateness=.001, settledAfterFeedSeconds=.1, audioSHA256=sha))
        self.manifest = self.base / "setup/input440.json"
        self.manifest.write_text(json.dumps(self.refs))
        self.manifest_hash = REPORT.digest(self.manifest.read_bytes())
        self.fixture = self.base / "fixture.swift"
        self.fixture.write_text("// synthetic metadata\n")
        for label, name in (("baseline", "baseline"), ("candidate", "current")):
            self.write_arm(label, self.rows)
            exe = self.base / (label + "-executable")
            exe.write_bytes(label.encode())
            metadata = dict(executable=str(exe), sha256=REPORT.digest(exe.read_bytes()),
                input_manifest_sha256=self.manifest_hash,
                fixture_source_sha256=REPORT.digest(self.fixture.read_bytes()),
                pacing="realtime", original_samples=420, derived_samples=20)
            (self.base / "setup" / ("cohort-" + name + ".json")).write_text(json.dumps(metadata))
        self.progress = [dict(phase="quality", arm=k, status="PASS", exit_code=0) for k in ("baseline", "candidate")]
        (self.root / "progress.json").write_text(json.dumps(self.progress))

    def write_arm(self, name, rows):
        (self.root / "quality" / (name + "-realtime440.jsonl")).write_text(
            "".join(json.dumps(r) + "\n" for r in rows))

    def report(self):
        return REPORT.report(self.root, self.manifest, self.manifest_hash, self.audio, self.fixture)

    def test_complete_matched_data_and_missing_resources_are_honest(self):
        d = self.report()
        self.assertEqual(d["comparison"]["exact_final_equal"], 440)
        self.assertEqual(d["audio"]["frames"], 440 * 320)
        self.assertEqual(d["routes"]["candidate"]["groups"]["original420"]["reference_units"], 420 * 4)
        self.assertEqual(d["routes"]["candidate"]["resources"]["cpu_s"]["status"], "NOT_RECORDED")
        self.assertEqual(d["release_verdict"].split(":")[0], "NOT_ASSESSED")

    def test_empty_failed_and_no_model_output_still_count_in_denominator(self):
        rows = copy.deepcopy(self.rows)
        rows[0].update(text="", states=["failed"], errors=["empty final"], providers=[])
        self.write_arm("candidate", rows)
        d = self.report()
        c = d["routes"]["candidate"]
        self.assertEqual(c["groups"]["original420"]["reference_units"], 1680)
        self.assertEqual(c["groups"]["original420"]["deletions"], 4)
        self.assertEqual(c["rows_with_issues"], 1)
        self.assertFalse(d["comparison"]["quality_nonregression"]["original420"])

    def test_incomplete_duplicate_or_reordered_records_do_not_score(self):
        for rows in (self.rows[:-1], self.rows + self.rows[-1:], self.rows[:-1] + self.rows[:1], list(reversed(self.rows))):
            with self.subTest(count=len(rows)), self.assertRaises(ValueError):
                self.write_arm("candidate", rows)
                self.report()

    def test_last_row_without_newline_and_running_process_are_not_complete(self):
        path = self.root / "quality/candidate-realtime440.jsonl"
        path.write_text(path.read_text().rstrip("\n"))
        with self.assertRaisesRegex(ValueError, "unfinished"):
            self.report()
        self.write_arm("candidate", self.rows)
        self.progress.append(dict(phase="quality", arm="candidate", status="RUNNING"))
        (self.root / "progress.json").write_text(json.dumps(self.progress))
        with self.assertRaisesRegex(ValueError, "finish successfully"):
            self.report()

    def test_provider_route_frames_hash_and_pacing_mismatch_are_rejected(self):
        for key, value in (("providers", ["apple-speech-analyzer"]), ("path", "direct"),
                           ("pacing", "accelerated"), ("feedSeconds", .003),
                           ("audioFrames", 319), ("audioSHA256", "0" * 64),
                           ("audioSeconds", .019), ("maximumFeedLateness", float("nan"))):
            rows = copy.deepcopy(self.rows)
            rows[0][key] = value
            self.write_arm("candidate", rows)
            with self.subTest(field=key), self.assertRaises(ValueError):
                self.report()

    def test_corrupt_wav_and_changed_manifest_are_rejected(self):
        path = self.audio / (self.refs[0]["id"] + ".wav")
        path.write_bytes(path.read_bytes() + b"modified")
        with self.assertRaisesRegex(ValueError, "WAV SHA mismatch"):
            self.report()
        self.manifest.write_text("[]")
        with self.assertRaisesRegex(ValueError, "manifest SHA"):
            self.report()

    def test_changed_executable_or_fixture_cannot_reuse_original_build_receipt(self):
        self.fixture.write_text("// changed fixture\n")
        with self.assertRaisesRegex(ValueError, "fixture source mismatch"):
            self.report()
        self.fixture.write_text("// synthetic metadata\n")
        (self.base / "candidate-executable").write_bytes(b"wrong executable")
        with self.assertRaisesRegex(ValueError, "executable SHA mismatch"):
            self.report()

    def test_slow_feed_remains_in_score_and_timing(self):
        rows = copy.deepcopy(self.rows)
        rows[0].update(feedSeconds=2.0, maximumFeedLateness=1.98, text="中文")
        self.write_arm("candidate", rows)
        d = self.report()["routes"]["candidate"]
        self.assertEqual(d["groups"]["original420"]["reference_units"], 1680)
        self.assertEqual(d["groups"]["original420"]["deletions"], 2)
        self.assertEqual(d["timing"]["maximum_feed_lateness_s"]["max"], 1.98)


if __name__ == "__main__":
    unittest.main()
