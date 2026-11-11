"""Run Sparkle's own CLI against disposable, re-signed copies on loopback."""
import argparse
import functools
import http.server
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import threading
import uuid

parser = argparse.ArgumentParser()
for key in ("app", "sparkle", "cli", "output"):
    parser.add_argument("--" + key, required=True, type=Path)
args = parser.parse_args()
args.cli = args.cli.resolve()
sign = (args.sparkle / "bin/sign_update").resolve()

def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=180).stdout.strip()

def plist(bundle):
    return bundle / "Contents/Info.plist"

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

with tempfile.TemporaryDirectory(prefix="saytile-isolated-update-") as tmp:
    root = Path(tmp)
    feed = root / "feed"
    feed.mkdir()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=feed))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_port}/"
    key = root / "session-key"
    key.touch(mode=0o600)
    pub = run("swift", "-e", 'import Foundation; import CryptoKit; let k = Curve25519.Signing.PrivateKey(); try k.rawRepresentation.base64EncodedData().write(to: URL(fileURLWithPath:CommandLine.arguments[1])); print(k.publicKey.rawRepresentation.base64EncodedString())', str(key))
    identities = re.findall(r'(\b[0-9A-F]{40}) "Developer ID Application:', run("security","find-identity","-v","-p","codesigning"))
    assert len(identities) == 1
    bundle_id = "app.saytile.update-fixture." + uuid.uuid4().hex
    installed = root / "Applications/Saytile.app"
    newer = root / "target/Saytile.app"
    for version, path in [(1, installed), (2, newer)]:
        path.parent.mkdir()
        run("ditto", "--norsrc", args.app, path)
        info = plistlib.loads(plist(path).read_bytes())
        info.update(CFBundleIdentifier=bundle_id, CFBundleVersion=str(version),
                    CFBundleShortVersionString=f"1.0.{version}", SUFeedURL=url+"appcast.xml",
                    SUPublicEDKey=pub, SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
                    SUEnableAutomaticChecks=False)
        plist(path).write_bytes(plistlib.dumps(info))
        run("codesign","--force","--options","runtime","--timestamp=none","--sign",identities[0],path)
    archive = feed / "update.zip"
    run("ditto","-c","-k","--keepParent",newer,archive)
    signature = run(sign, "-f", key, "-p", archive)
    xml = feed / "appcast.xml"
    xml.write_text(f'''<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Saytile integration</title><item><title>2</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>1.0.2</sparkle:shortVersionString><enclosure url="{url}update.zip" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{signature}"/></item></channel></rss>''')
    run(sign,"-f",key,xml)
    def check():
        cmd = [args.cli, installed, "--check-immediately", "--grant-automatic-checks", "--verbose"]
        return subprocess.run(cmd,capture_output=True,text=True,timeout=100)
    # Change a byte without changing advertised length. Restore it to retry the same feed.
    def flip():
        with archive.open("r+b") as f:
            f.seek(256)
            byte = f.read(1)[0]
            f.seek(256)
            f.write(bytes([byte ^ 1]))
    flip()
    rejected = check()
    assert rejected.returncode != 0 and plistlib.loads(plist(installed).read_bytes())['CFBundleVersion'] == '1', rejected
    flip()
    accepted = check()
    assert accepted.returncode == 0 and plistlib.loads(plist(installed).read_bytes())['CFBundleVersion'] == '2', accepted
    run("codesign","--verify","--deep","--strict",installed)
    current = check()
    assert plistlib.loads(plist(installed).read_bytes())['CFBundleVersion'] == '2'
    assert current.returncode == 4 and "no new update" in current.stderr.lower(), current
    server.shutdown()
    args.output.write_text(json.dumps(dict(source=info['SaytileSourceRevision'], status="PASS", sparkle="2.10.1", scope="unique fixture bundle ID; re-signed copies; disposable Ed25519 key; loopback only", corrupted_archive_exit=rejected.returncode, valid_update_exit=accepted.returncode, version_before=1, version_after=2, current_version_exit=current.returncode, installed_signature_verified=True),indent=2)+"\n")
