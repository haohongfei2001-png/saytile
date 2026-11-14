"""Endpoint evidence regressions, independent of model or GPU availability."""
import copy
from pathlib import Path
import runpy
import unittest

observe = runpy.run_path(str(Path(__file__).resolve().parents[1] /
                            "scripts/mandarin/score-stop-response.py"))["observed_response"]


class StopResponseEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.receipt = {
            "archive": ["连续文字"],
            "frames": [{"t": 9.0, "text": "连续"}, {"t": 10.4, "text": "连续文字"}],
            "rawWorkerEvents": [{"t": 9.0, "kind": "partial"}, {"t": 10.3, "kind": "final"}],
            "endOfFile": 15.0, "pipelineSettledAt": 15.1,
        }

    def test_tail_silence_does_not_substitute_eof_for_confirmation(self):
        result = observe(self.receipt, 10.0)
        self.assertEqual(result["raw_final_after_last_acoustic_signal_s"], .3)
        self.assertEqual(result["eventual_final_text_display_after_last_acoustic_signal_s"], .4)
        extended = copy.deepcopy(self.receipt)
        extended.update(endOfFile=25.0, pipelineSettledAt=25.1)
        self.assertEqual(observe(extended, 10.0), result)
        self.assertEqual(result["vad_endpoint_status"], "NOT_RECORDED")

    def test_final_text_can_be_visible_before_confirmation(self):
        self.receipt["frames"][-1]["t"] = 9.8
        result = observe(self.receipt, 10.0)
        self.assertEqual(result["eventual_final_text_display_after_last_acoustic_signal_s"], -.2)
        self.assertEqual(result["raw_final_after_last_acoustic_signal_s"], .3)
        self.assertEqual(result["eventual_final_text_display_before_raw_final_s"], .5)

    def test_temporary_final_text_match_is_not_continuous_final_display(self):
        self.receipt["frames"] = [{"t": 9.0, "text": "连续文字"},
                                  {"t": 9.5, "text": "连续文"},
                                  {"t": 10.4, "text": "连续文字"}]
        self.assertEqual(observe(self.receipt, 10.0)["eventual_final_text_continuously_visible_from_s"], 10.4)

    def test_missing_final_is_not_filled_in_with_eof(self):
        self.receipt["rawWorkerEvents"] = [{"t": 9.0, "kind": "partial"}]
        with self.assertRaisesRegex(ValueError, "No observed ASR final"):
            observe(self.receipt, 10.0)

    def test_out_of_order_frames_are_rejected(self):
        self.receipt["frames"][0]["t"] = 10.5
        with self.assertRaisesRegex(ValueError, "timestamp order"):
            observe(self.receipt, 10.0)


if __name__ == "__main__":
    unittest.main()
