"""Packaging-only tests: synthetic public keys, temporary plists, no Keychain/network."""
import base64
import copy
import importlib.util
import itertools
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/configure-update-feed.py"
SPEC = importlib.util.spec_from_file_location("update_configuration", SCRIPT)
CONFIG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONFIG)
STANDARD = "app.saytile.mac"
MANDARIN = "app.saytile.mac.mandarin-candidate"
KEY = base64.b64encode(bytes(range(32))).decode("ascii")


def fixture():
    return {"schemaVersion": 1, "channels": {
        STANDARD: {"channel": "standard", "feedURL": "https://example.test/standard/appcast.xml", "publicEDKey": KEY},
        MANDARIN: {"channel": "mandarin", "feedURL": "https://example.test/mandarin/appcast.xml", "publicEDKey": KEY},
    }}


class UpdateConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.config = fixture()
        self.channels = CONFIG.validate_channels(self.config)

    def configure(self, bundle=STANDARD, environment=None, **info):
        return CONFIG.configured_plist({"CFBundleIdentifier": bundle, **info}, self.channels, environment or {})

    def test_defaults_require_signed_feed_and_never_auto_install_or_profile(self):
        result = self.configure(CFBundleVersion="488", CFBundleShortVersionString="0.17")
        for key in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUEnableAutomaticChecks"):
            self.assertIs(result[key], True)
        for key in ("SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates", "SUEnableSystemProfiling", "SUSendProfileInfo"):
            self.assertIs(result[key], False)
        self.assertEqual(result["SUSignedFeedFailureExpirationInterval"], 0)
        self.assertEqual(result["SUScheduledCheckInterval"], 86400)
        self.assertEqual(result["CFBundleVersion"], "488")
        self.assertEqual(result["CFBundleShortVersionString"], "0.17")
        self.assertEqual(result["SaytileUpdateBundleIdentifier"], STANDARD)

    def test_candidate_keeps_its_identity_and_own_feed(self):
        standard, candidate = self.configure(), self.configure(MANDARIN)
        self.assertEqual(candidate["CFBundleIdentifier"], MANDARIN)
        self.assertEqual(candidate["SaytileUpdateBundleIdentifier"], MANDARIN)
        self.assertEqual(candidate["SaytileUpdateChannel"], "mandarin")
        self.assertNotEqual(candidate["SUFeedURL"], standard["SUFeedURL"])
        self.assertEqual(candidate["SUPublicEDKey"], standard["SUPublicEDKey"])

    def test_unknown_bundle_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "bundle identifier"):
            self.configure("app.saytile.mac.old-preview")

    def test_malformed_plist_fails_closed(self):
        for info in ([], None, {"CFBundleIdentifier": []}, {"CFBundleIdentifier": 1}):
            with self.subTest(info=info), self.assertRaises(ValueError):
                CONFIG.configured_plist(info, self.channels, {})

    def test_repository_channels_are_valid_and_bind_distinct_feeds(self):
        channels = CONFIG.read_channels(CONFIG.DEFAULT_CONFIG)
        self.assertEqual(set(channels), {STANDARD, MANDARIN})
        self.assertEqual(channels[STANDARD]["publicEDKey"], channels[MANDARIN]["publicEDKey"])
        self.assertTrue(channels[STANDARD]["feedURL"].endswith("/standard/appcast.xml"))
        self.assertTrue(channels[MANDARIN]["feedURL"].endswith("/mandarin/appcast.xml"))

    def test_existing_cross_profile_metadata_is_rejected(self):
        for fields in ({"SaytileUpdateBundleIdentifier": MANDARIN}, {"SaytileUpdateChannel": "mandarin"}):
            with self.subTest(fields=fields), self.assertRaisesRegex(ValueError, "different bundle"):
                self.configure(**fields)

    def test_channel_mapping_cannot_be_swapped(self):
        self.config["channels"][STANDARD]["channel"] = "mandarin"
        with self.assertRaisesRegex(ValueError, "does not match"):
            CONFIG.validate_channels(self.config)

    def test_same_feed_cannot_serve_both_app_identities(self):
        self.config["channels"][MANDARIN]["feedURL"] = self.config["channels"][STANDARD]["feedURL"]
        with self.assertRaisesRegex(ValueError, "different feed"):
            CONFIG.validate_channels(self.config)

    def test_malformed_or_insecure_feed_is_rejected(self):
        invalid = [None, "", "http://example.test/appcast.xml", "https:///appcast.xml",
                   "https://user:pass@example.test/feed", "https://@example.test/feed",
                   "https://example.test/feed#", "https://example.test/feed#fragment",
                   "https://example.test/feed?token=secret", "https://example.test/feed?",
                   " https://example.test/feed", "https://example.test/fee\nd", "https://example.test/fee\td",
                   "https://example.test\\other/feed", "https://example.test:bad/feed",
                   "https://example.test:65536/feed", "https://example.test:0/feed", "https://example.test"]
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(ValueError):
                CONFIG.validate_feed(value)

    def test_public_key_is_exact_canonical_32_byte_base64(self):
        invalid = [None, "", "not a key", KEY + "\n", KEY + "=", KEY.rstrip("="),
                   base64.b64encode(bytes(31)).decode(), base64.b64encode(bytes(33)).decode(),
                   KEY[:-2] + "9="]
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(ValueError):
                CONFIG.validate_public_key(value)
        self.assertEqual(CONFIG.validate_public_key(KEY), KEY)

    def test_complete_override_retains_bundle_channel_and_safety_defaults(self):
        result = self.configure(MANDARIN, {
            "SAYTILE_UPDATE_FEED": "https://example.test/testing/appcast.xml",
            "SAYTILE_UPDATE_PUBLIC_KEY": KEY, "SAYTILE_UPDATE_CHANNEL": "mandarin",
        })
        self.assertEqual(result["SUFeedURL"], "https://example.test/testing/appcast.xml")
        self.assertEqual(result["SaytileUpdateChannel"], "mandarin")
        self.assertIs(result["SUAllowsAutomaticUpdates"], False)

    def test_partial_or_empty_override_never_falls_back_silently(self):
        full = dict(zip(CONFIG.OVERRIDES, ["https://example.test/testing/feed", KEY, "standard"]))
        for count in (1, 2):
            for names in itertools.combinations(CONFIG.OVERRIDES, count):
                with self.subTest(names=names), self.assertRaisesRegex(ValueError, "together"):
                    self.configure(environment={name: full[name] for name in names})
        for name in CONFIG.OVERRIDES:
            env = dict(full); env[name] = ""
            with self.subTest(empty=name), self.assertRaisesRegex(ValueError, "together"):
                self.configure(environment=env)

    def test_override_wrong_channel_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "does not match"):
            self.configure(MANDARIN, dict(zip(CONFIG.OVERRIDES, ["https://example.test/testing/feed", KEY, "standard"])))

    def test_override_known_other_profile_feed_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "another bundle"):
            self.configure(MANDARIN, dict(zip(CONFIG.OVERRIDES, [self.channels[STANDARD]["feedURL"], KEY, "mandarin"])))

    def test_unknown_missing_and_malformed_configuration_are_rejected(self):
        bad = [{}, {"schemaVersion": True, "channels": self.channels}, {"schemaVersion": 2, "channels": self.channels}]
        absent = copy.deepcopy(self.config); absent["channels"].pop(MANDARIN); bad.append(absent)
        extra = copy.deepcopy(self.config); extra["channels"]["other.app"] = dict(self.channels[STANDARD]); bad.append(extra)
        typo = copy.deepcopy(self.config); typo["channels"][STANDARD]["publicKey"] = KEY; bad.append(typo)
        for config in bad:
            with self.subTest(config=config), self.assertRaises(ValueError):
                CONFIG.validate_channels(config)

    def test_duplicate_json_keys_are_rejected(self):
        with tempfile.TemporaryDirectory(prefix="saytile-update-config-") as directory:
            path = Path(directory) / "channels.json"
            path.write_text('{"schemaVersion":1,"schemaVersion":1,"channels":{}}')
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                CONFIG.read_channels(path)

    def test_defaults_do_not_inherit_arbitrary_environment_preferences(self):
        result = self.configure(environment={"SUAutomaticallyUpdate": "YES", "SUSendProfileInfo": "YES", "SUFeedURL": "https://wrong.test/feed"})
        self.assertEqual(result["SUFeedURL"], self.channels[STANDARD]["feedURL"])
        self.assertIs(result["SUAutomaticallyUpdate"], False)
        self.assertIs(result["SUSendProfileInfo"], False)

    def test_cli_failure_leaves_input_plist_unchanged_then_valid_config_succeeds(self):
        with tempfile.TemporaryDirectory(prefix="saytile-update-config-") as directory:
            root = Path(directory)
            channels, info = root / "channels.json", root / "Info.plist"
            channels.write_text(json.dumps(self.config))
            original = plistlib.dumps({"CFBundleIdentifier": MANDARIN, "CFBundleVersion": "488"})
            info.write_bytes(original)
            command = [sys.executable, str(SCRIPT), str(info), "--channels", str(channels)]
            env = {"PATH": os.defpath, "SAYTILE_UPDATE_CHANNEL": "mandarin"}
            failed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("together", failed.stderr)
            self.assertEqual(info.read_bytes(), original)
            passed = subprocess.run(command, env={"PATH": os.defpath}, capture_output=True, text=True, timeout=10)
            self.assertEqual(passed.returncode, 0, passed.stderr)
            self.assertEqual(plistlib.loads(info.read_bytes())["SaytileUpdateChannel"], "mandarin")


if __name__ == "__main__":
    unittest.main(verbosity=2)
