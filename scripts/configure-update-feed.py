#!/usr/bin/env python3
"""Embed the matching signed update channel at packaging, never from user defaults."""
import argparse
import base64
import binascii
import json
import os
import plistlib
from pathlib import Path
from urllib.parse import urlsplit


CHANNELS = {
    "app.saytile.mac": "standard",
    "app.saytile.mac.mandarin-candidate": "mandarin",
}
OVERRIDES = ("SAYTILE_UPDATE_FEED", "SAYTILE_UPDATE_PUBLIC_KEY", "SAYTILE_UPDATE_CHANNEL")
DEFAULT_CONFIG = Path(__file__).resolve().parents[1] / "packaging/update-channels.json"


def validate_feed(value):
    if not isinstance(value, str) or not value or any(ord(c) <= 32 or ord(c) == 127 for c in value):
        raise ValueError("Expected an HTTPS appcast URL without whitespace")
    try:
        url = urlsplit(value)
        port = url.port
    except ValueError as error:
        raise ValueError("Malformed HTTPS appcast URL") from error
    if (url.scheme != "https" or not url.hostname or not url.path
            or url.username is not None or url.password is not None
            or "#" in value or "?" in value or "\\" in value or port == 0):
        raise ValueError("Expected an HTTPS appcast URL without credentials, query or fragment")
    return value


def validate_public_key(value):
    try:
        decoded = base64.b64decode(value, validate=True) if isinstance(value, str) else b""
    except (ValueError, binascii.Error) as error:
        raise ValueError("Expected a canonical base64 32-byte Ed25519 public key") from error
    if len(decoded) != 32 or base64.b64encode(decoded).decode("ascii") != value:
        raise ValueError("Expected a canonical base64 32-byte Ed25519 public key")
    return value


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate key in update channel configuration")
        result[key] = value
    return result


def read_channels(path):
    return validate_channels(json.loads(path.read_text(), object_pairs_hook=unique_object))


def validate_channels(config):
    if (not isinstance(config, dict) or set(config) != {"schemaVersion", "channels"}
            or type(config["schemaVersion"]) is not int or config["schemaVersion"] != 1):
        raise ValueError("Unsupported update channel configuration schema")
    channels = config["channels"]
    if not isinstance(channels, dict) or set(channels) != set(CHANNELS):
        raise ValueError("Expected exactly the standard and Mandarin bundle channels")
    feeds = set()
    for bundle_id, name in CHANNELS.items():
        entry = channels[bundle_id]
        if (not isinstance(entry, dict) or set(entry) != {"channel", "feedURL", "publicEDKey"}
                or entry["channel"] != name):
            raise ValueError("Update channel does not match its bundle identifier")
        feed = validate_feed(entry["feedURL"])
        validate_public_key(entry["publicEDKey"])
        if feed in feeds:
            raise ValueError("Independent bundle channels must use different feed URLs")
        feeds.add(feed)
    return channels


def configured_plist(info, channels, environment):
    if not isinstance(info, dict):
        raise ValueError("Expected an application Info.plist dictionary")
    bundle_id = info.get("CFBundleIdentifier")
    if not isinstance(bundle_id, str) or bundle_id not in CHANNELS:
        raise ValueError("Unsupported update bundle identifier")
    channel = CHANNELS[bundle_id]
    if (info.get("SaytileUpdateBundleIdentifier", bundle_id) != bundle_id
            or info.get("SaytileUpdateChannel", channel) != channel):
        raise ValueError("Existing update metadata belongs to a different bundle channel")
    entry = channels[bundle_id]
    feed, key = entry["feedURL"], entry["publicEDKey"]
    if any(name in environment for name in OVERRIDES):
        if not all(isinstance(environment.get(name), str) and environment[name] for name in OVERRIDES):
            raise ValueError("Update overrides require feed, public key and matching channel together")
        if environment["SAYTILE_UPDATE_CHANNEL"] != channel:
            raise ValueError("Update override channel does not match the packaged bundle")
        feed = validate_feed(environment["SAYTILE_UPDATE_FEED"])
        key = validate_public_key(environment["SAYTILE_UPDATE_PUBLIC_KEY"])
        if any(other_id != bundle_id and other["feedURL"] == feed for other_id, other in channels.items()):
            raise ValueError("Update override points at another bundle's feed")
    result = dict(info)
    result.update(
        SaytileUpdateBundleIdentifier=bundle_id, SaytileUpdateChannel=channel,
        SUFeedURL=feed, SUPublicEDKey=key,
        SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
        SUEnableAutomaticChecks=True,
        SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False,
        SUEnableSystemProfiling=False, SUSendProfileInfo=False,
    )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plist", type=Path)
    parser.add_argument("--channels", type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()
    try:
        channels = read_channels(args.channels)
        info = plistlib.loads(args.plist.read_bytes())
        result = configured_plist(info, channels, os.environ)
        data = plistlib.dumps(result)
        args.plist.write_bytes(data)
    except (OSError, ValueError, TypeError, plistlib.InvalidFileException) as error:
        parser.exit(1, "Update configuration rejected: " + str(error) + "\n")


if __name__ == "__main__":
    main()
