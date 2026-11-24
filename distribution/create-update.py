#!/usr/bin/env python3
"""Prepare (never publish) a signed Sparkle archive/feed with the existing key.

The signing tool accesses the authorized Keychain account internally. This
script never accepts, exports, prints or persists a private key.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def run(*command):
    result = subprocess.run([str(x) for x in command], capture_output=True, text=True, timeout=240)
    if result.returncode:
        raise RuntimeError(f"{Path(command[0]).name} failed ({result.returncode}): {result.stderr[-1600:]}")
    return result.stdout.strip()


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def validate_metadata(info, expected_source):
    channels = json.loads((ROOT / "packaging/update-channels.json").read_text())["channels"]
    bundle = info.get("CFBundleIdentifier")
    if bundle not in channels:
        raise ValueError("Unrecognized release bundle identity")
    expected = channels[bundle]
    for key, value in {"SaytileUpdateBundleIdentifier": bundle, "SaytileUpdateChannel": expected["channel"],
                       "SUPublicEDKey": expected["publicEDKey"], "SUFeedURL": expected["feedURL"],
                       "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
                       "SUSignedFeedFailureExpirationInterval": 0, "SUAllowsAutomaticUpdates": False,
                       "SUSendProfileInfo": False}.items():
        if info.get(key) != value or type(info.get(key)) is not type(value):
            raise ValueError(f"Release update contract mismatch: {key}")
    if not re.fullmatch(r"[0-9a-f]{40}", expected_source) or info.get("SaytileSourceRevision") != expected_source:
        raise ValueError("Release source SHA does not match the candidate")
    if info.get("SaytileSourceDirty") is not False:
        raise ValueError("Only a clean-source candidate can prepare a release update")
    if not re.fullmatch(r"[1-9][0-9]*", str(info.get("CFBundleVersion", ""))):
        raise ValueError("Build number must be a positive canonical integer")
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", info.get("CFBundleShortVersionString", "")):
        raise ValueError("A release requires a three-component product version")
    return expected


def validate_download_url(value):
    address = urlsplit(value)
    if (address.scheme != "https" or not address.hostname or not address.path.endswith(".zip") or
            address.username is not None or address.password is not None or address.query or address.fragment or
            any(c.isspace() or ord(c) < 32 for c in value) or "\\" in value or "?" in value or "#" in value):
        raise ValueError("Archive URL must be credential-free HTTPS ending in .zip")
    if address.port is not None and not 1 <= address.port <= 65535:
        raise ValueError("Invalid archive URL port")
    return value


def verify_signature(path, signature, public_key):
    """Verify against the already shipped public key, not a newly inferred key."""
    if len(base64.b64decode(public_key, validate=True)) != 32 or len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Malformed public key or Ed25519 signature")
    run("swift", "-module-cache-path", str(Path(tempfile.gettempdir()) / "saytile-update-verify-module-cache"),
        ROOT / "distribution/verify-update-signature.swift", public_key, signature, path)


def sign_archive(sign_tool, account, archive, public_key):
    signature = run(sign_tool, "--account", account, "-p", archive)
    verify_signature(archive, signature, public_key)
    return signature


def appcast(info, download_url, length, signature, notes):
    if not notes.strip() or "\x00" in notes:
        raise ValueError("Plain-text release notes are required")
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "Saytile"
    # Forward-compatible metadata; Sparkle 2.10.1 still enforces the installed
    # bundle identity at archive installation, not via the newer 2.11 setting.
    ET.SubElement(channel, f"{{{SPARKLE}}}bundleIdentifier").text = info["CFBundleIdentifier"]
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = "Saytile " + info["CFBundleShortVersionString"]
    for name, value in (("version", info["CFBundleVersion"]),
                        ("shortVersionString", info["CFBundleShortVersionString"]),
                        ("minimumSystemVersion", info["LSMinimumSystemVersion"])):
        ET.SubElement(item, f"{{{SPARKLE}}}" + name).text = value
    # Inline plain text is authenticated with the feed, needs no extra request,
    # and gives the standard native updater real notes before installation.
    ET.SubElement(item, "description", {f"{{{SPARKLE}}}format": "plain-text"}).text = notes.strip()
    ET.SubElement(item, "enclosure", {"url": validate_download_url(download_url), "length": str(length),
        "type": "application/octet-stream", f"{{{SPARKLE}}}edSignature": signature})
    ET.indent(root)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("app", "sparkle", "notes", "output"):
        parser.add_argument("--" + key, required=True, type=Path)
    parser.add_argument("--expected-source", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--signing-account", default="app.saytile.updates.v1")
    args = parser.parse_args()
    app = args.app.resolve()
    if app.name != "Saytile.app":
        raise ValueError("The archive must contain the canonical Saytile.app name")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    channel = validate_metadata(info, args.expected_source)
    validate_download_url(args.download_url)
    notes = args.notes.read_text()
    if not notes.strip():
        raise ValueError("Release notes are empty")
    run("codesign", "--verify", "--deep", "--strict", app)
    details = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)], capture_output=True, text=True, check=True).stderr
    if "Authority=Developer ID Application:" not in details or "flags=0x10000(runtime)" not in details or "Timestamp=" not in details:
        raise ValueError("A timestamped Developer ID hardened-runtime candidate is required")
    sign = args.sparkle.resolve() / "bin/sign_update"
    original_binary = digest(app / "Contents/MacOS/Saytile")
    original_plist = digest(app / "Contents/Info.plist")
    args.output.mkdir(parents=True, exist_ok=False)
    archive = args.output / Path(urlsplit(args.download_url).path).name
    run("ditto", "-c", "-k", "--keepParent", app, archive)
    signature = sign_archive(sign, args.signing_account, archive, channel["publicEDKey"])
    feed = args.output / "appcast.xml"
    feed.write_bytes(appcast(info, args.download_url, archive.stat().st_size, signature, notes))
    run(sign, "--account", args.signing_account, feed)
    run(sign, "--account", args.signing_account, "--verify", feed)
    assert digest(app / "Contents/MacOS/Saytile") == original_binary
    assert digest(app / "Contents/Info.plist") == original_plist
    receipt = dict(status="PREPARED_NOT_PUBLISHED", source=args.expected_source, version=info["CFBundleShortVersionString"],
        build=info["CFBundleVersion"], bundle_id=info["CFBundleIdentifier"], channel=channel["channel"],
        public_key=channel["publicEDKey"], signing_account=args.signing_account,
        archive=archive.name, archive_bytes=archive.stat().st_size, archive_sha256=digest(archive),
        feed_sha256=digest(feed), executable_sha256=original_binary, signing_tool_sha256=digest(sign),
        archive_signature_verified_with_published_public_key=True, signed_feed_verified=True,
        release_notes="signed inline plain text", keychain_mutated=False, private_key_exported=False,
        production_feed_modified=False, candidate_modified=False, notarization="NOT_ASSESSED_BY_THIS_TOOL")
    (args.output / "receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
