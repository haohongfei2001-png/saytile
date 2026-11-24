"""Release-preparation boundaries; public metadata and signatures only."""
import base64
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("release_update", ROOT / "distribution/create-update.py")
UPDATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPDATE)
SHA = "a" * 40


def metadata():
    bundle = "app.saytile.mac.mandarin-candidate"
    channel = json.loads((ROOT / "packaging/update-channels.json").read_text())["channels"][bundle]
    return dict(CFBundleIdentifier=bundle, SaytileUpdateBundleIdentifier=bundle, SaytileUpdateChannel=channel["channel"],
        CFBundleShortVersionString="1.0.1", CFBundleVersion="573", SaytileSourceRevision=SHA, SaytileSourceDirty=False,
        LSMinimumSystemVersion="26.0", SUFeedURL=channel["feedURL"], SUPublicEDKey=channel["publicEDKey"],
        SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True, SUSignedFeedFailureExpirationInterval=0,
        SUAllowsAutomaticUpdates=False, SUSendProfileInfo=False)


class ReleaseUpdateTests(unittest.TestCase):
    def test_release_candidate_retains_existing_trust_and_identity(self):
        self.assertEqual(UPDATE.validate_metadata(metadata(), SHA)["channel"], "mandarin")

    def test_wrong_source_or_dirty_candidate_cannot_prepare_update(self):
        for key, value in (("SaytileSourceRevision", "b" * 40), ("SaytileSourceDirty", True), ("SaytileSourceDirty", 0)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                UPDATE.validate_metadata({**metadata(), key: value}, SHA)

    def test_identity_and_each_security_contract_are_fail_closed(self):
        changes = dict(CFBundleIdentifier="app.saytile.experimental", SaytileUpdateBundleIdentifier="app.saytile.mac",
            SaytileUpdateChannel="standard", SUPublicEDKey=base64.b64encode(bytes(32)).decode(),
            SUFeedURL="https://example.test/other.xml", SURequireSignedFeed=False, SUVerifyUpdateBeforeExtraction=False,
            SUSignedFeedFailureExpirationInterval=86400, SUAllowsAutomaticUpdates=True, SUSendProfileInfo=True)
        for key, value in changes.items():
            with self.subTest(key=key), self.assertRaises(ValueError):
                UPDATE.validate_metadata({**metadata(), key: value}, SHA)

    def test_boolean_types_cannot_bypass_security_contract(self):
        for key, value in (("SURequireSignedFeed", 1), ("SUAllowsAutomaticUpdates", 0), ("SUSignedFeedFailureExpirationInterval", False)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                UPDATE.validate_metadata({**metadata(), key: value}, SHA)

    def test_nonrelease_or_ambiguous_versions_are_rejected(self):
        for key, value in (("CFBundleVersion", "0573"), ("CFBundleVersion", "0"), ("CFBundleVersion", "573-beta"),
                           ("CFBundleShortVersionString", "1.0.1-beta"), ("CFBundleShortVersionString", "1.0"),
                           ("CFBundleShortVersionString", "01.0.1")):
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                UPDATE.validate_metadata({**metadata(), key: value}, SHA)

    def test_release_notes_are_authenticated_inline_plain_text(self):
        notes = "保留原音 & 修改稿\n<script>not HTML</script>"
        root = ET.fromstring(UPDATE.appcast(metadata(), "https://example.test/Saytile-1.0.1.zip", 123, "public-signature", notes))
        item = root.find("./channel/item")
        description = item.find("description")
        self.assertEqual(description.text, notes)
        self.assertEqual(description.get(f"{{{UPDATE.SPARKLE}}}format"), "plain-text")
        self.assertIsNone(item.find(f"{{{UPDATE.SPARKLE}}}releaseNotesLink"))
        self.assertEqual(item.find(f"{{{UPDATE.SPARKLE}}}version").text, "573")
        self.assertEqual(item.find(f"{{{UPDATE.SPARKLE}}}shortVersionString").text, "1.0.1")
        self.assertEqual(root.find(f"./channel/{{{UPDATE.SPARKLE}}}bundleIdentifier").text, metadata()["CFBundleIdentifier"])
        self.assertEqual(item.find("enclosure").get("length"), "123")

    def test_empty_notes_rejected(self):
        for notes in ("", " \n", "bad\x00notes"):
            with self.subTest(notes=notes), self.assertRaises(ValueError):
                UPDATE.appcast(metadata(), "https://example.test/update.zip", 123, "signature", notes)

    def test_unsafe_archive_locations_rejected(self):
        for url in ("http://example.test/update.zip", "file:///tmp/update.zip", "https://u:p@example.test/update.zip",
                    "https://example.test/update.zip?token=secret", "https://example.test/update.zip#fragment",
                    "https://example.test/up\ndate.zip", "https://example.test/update.dmg", "https://example.test:0/update.zip",
                    "https://example.test:bad/update.zip", "https://example.test/update.zip?", "https://example.test/update.zip#"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                UPDATE.validate_download_url(url)

    def test_public_verifier_accepts_signature_and_rejects_changed_bytes(self):
        # RFC 8032 section 7.1, empty-message Ed25519 test vector. Public parts
        # only: no generated/stored/signing key is involved in this test.
        public_key = bytes.fromhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        signature = bytes.fromhex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
                                  "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
        with tempfile.TemporaryDirectory(prefix="saytile-update-public-vector-") as folder:
            message = Path(folder) / "message"
            message.write_bytes(b"")
            key64, sig64 = (base64.b64encode(value).decode() for value in (public_key, signature))
            UPDATE.verify_signature(message, sig64, key64)
            message.write_bytes(b"changed")
            with self.assertRaises(RuntimeError):
                UPDATE.verify_signature(message, sig64, key64)


if __name__ == "__main__":
    unittest.main(verbosity=2)
