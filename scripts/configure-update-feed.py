"""Configure both signed updater settings at packaging, never from user defaults."""
import base64
import os
import plistlib
import sys
from pathlib import Path
from urllib.parse import urlsplit

feed = os.environ.get("SAYTILE_UPDATE_FEED", "")
key = os.environ.get("SAYTILE_UPDATE_PUBLIC_KEY", "")
url = urlsplit(feed)
if url.scheme != "https" or not url.hostname or url.username or url.password or url.fragment:
    sys.exit("Expected an HTTPS appcast URL")
if len(base64.b64decode(key, validate=True)) != 32:
    sys.exit("Expected a 32-byte Ed25519 public key")
path = Path(sys.argv[1])
plist = plistlib.loads(path.read_bytes())
plist.update(SUFeedURL=feed, SUPublicEDKey=key, SURequireSignedFeed=True,
             SUVerifyUpdateBeforeExtraction=True, SUEnableAutomaticChecks=True)
path.write_bytes(plistlib.dumps(plist))
