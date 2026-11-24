#!/usr/bin/env python3
"""Default Sparkle UI in a disposable GitHub-hosted GUI session; compile-only locally."""
import argparse
import hashlib
import http.server
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile
import threading
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FEED = ROOT / 'evidence/release-101/distribution/final-prepared-update/appcast.xml'
FEED_SHA = 'f2c372c76b374449313f1e21a3a4046f87013264b607d34c3cec69351de81622'
PUBLIC_KEY = 'yVPpMoHz8/6GJ82Becd+jgoKvCww+9h2v2Vs6xZu/iw='
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()


def native_target():
    architecture = platform.machine()
    if platform.system() != 'Darwin' or architecture not in ('arm64', 'x86_64'):
        raise ValueError('Standard Sparkle UI requires native macOS arm64 or x86_64')
    return architecture, architecture + '-apple-macos26.0'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compile-only', action='store_true')
    args = parser.parse_args()
    if not args.compile_only and not (os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('SAYTILE_ALLOW_STANDARD_UPDATE_UI') == '1'):
        parser.error('UI activation is allowed only in the explicitly enabled CI GUI session')
    architecture, target = native_target()
    assert sha(FEED) == FEED_SHA, 'Keep the signed fixture bytes unchanged'
    args.output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix='saytile-standard-ui-', dir='/private/tmp') as directory:
        root = Path(directory); app = root / 'Saytile.app'; contents = app / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'Resources').mkdir()
        fixture_id = 'app.saytile.update-fixture.' + uuid.uuid4().hex
        requests = []
        class Feed(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_GET(self):
                requests.append(self.path)
                body = FEED.read_bytes() if self.path == '/appcast.xml' else b''
                self.send_response(200 if body else 404)
                self.send_header('Content-Type', 'application/rss+xml')
                self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Feed)
        info = dict(CFBundleIdentifier=fixture_id, CFBundleExecutable='Probe', CFBundleName='Saytile', CFBundleDisplayName='Saytile',
                    CFBundlePackageType='APPL', CFBundleShortVersionString='1.0.0', CFBundleVersion='572', LSUIElement=True,
                    SaytileUpdateBundleIdentifier=fixture_id, SaytileUpdateChannel='fixture', SUEnableAutomaticChecks=True,
                    SUFeedURL=f'http://127.0.0.1:{server.server_port}/appcast.xml', SUPublicEDKey=PUBLIC_KEY,
                    SURequireSignedFeed=True, SUSignedFeedFailureExpirationInterval=0, SUVerifyUpdateBeforeExtraction=True,
                    SUAllowsAutomaticUpdates=False, SUSendProfileInfo=False, SUScheduledCheckInterval=86400)
        product = ROOT / 'dist/Saytile.app/Contents'
        if (product / 'Info.plist').exists():
            icon = plistlib.loads((product / 'Info.plist').read_bytes()).get('CFBundleIconFile')
            icon_path = product / 'Resources' / (icon if icon and Path(icon).suffix else str(icon) + '.icns')
            if icon and icon_path.is_file():
                shutil.copy2(icon_path, contents / 'Resources' / icon_path.name); info['CFBundleIconFile'] = icon
        (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
        products = Path(os.environ['SAYTILE_UPDATE_PROBE_PRODUCTS'])
        modulemap = os.environ['SAYTILE_UPDATE_PROBE_MODULE_MAP']
        sparkle = Path(os.environ.get('SAYTILE_UPDATE_PROBE_SPARKLE', ROOT / '.build/sparkle')).resolve()
        sdk = plistlib.loads((sparkle / 'Sparkle.framework/Resources/Info.plist').read_bytes())
        assert sdk['CFBundleShortVersionString'] == '2.10.1'
        executable = contents / 'MacOS/Probe'
        command = ['swiftc', '-swift-version', '6', '-warnings-as-errors', '-target', target,
                   '-module-cache-path', os.environ.get('SAYTILE_UPDATE_PROBE_CACHE', '/private/tmp/saytile-update-probe-module-cache'),
                   '-I', str(products), '-I', str(products / 'Modules'), '-I', 'Sources/CSQLite',
                   '-Xcc', '-fmodule-map-file=' + modulemap, '-F', str(sparkle), '-L', str(products), '-lSaytileKit', '-lc++',
                   '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', str(sparkle),
                   'Sources/SaytileApp/AppUpdateController.swift', 'tests/fixtures/StandardUpdateUIProbe.swift', '-o', str(executable)]
        with (args.output / 'build.log').open('w') as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        result = dict(status='NOT_RUN' if args.compile_only else 'FAIL', source=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                      source_dirty=bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)), sparkle_version=sdk['CFBundleShortVersionString'],
                      probe_architecture=architecture, swift_target=target, model_inference_performed=False,
                      controller_sha256=sha(ROOT / 'Sources/SaytileApp/AppUpdateController.swift'),
                      probe_sha256=sha(ROOT / 'tests/fixtures/StandardUpdateUIProbe.swift'), signed_feed_sha256=FEED_SHA,
                      public_key=PUBLIC_KEY, fixture_bundle_id=fixture_id, private_key_used=False, production_data_accessed=False,
                      full_product_ui=False, compile_only=args.compile_only, runtime_launch_requested=not args.compile_only,
                      network_policy_requested=not args.compile_only)
        try:
            if not args.compile_only:
                notes = args.output / 'expected-inline-notes.txt'
                notes.write_text(ET.fromstring(FEED.read_bytes()).find('./channel/item/description').text)
                threading.Thread(target=server.serve_forever, daemon=True).start()
                # Seatbelt's address grammar accepts localhost, not numeric host
                # literals here. This still permits only loopback, never WAN.
                profile = '(version 1)(allow default)(deny network*)(allow network-outbound (remote ip "localhost:*"))(allow network-inbound (local ip "localhost:*"))'
                with (args.output / 'native.log').open('w') as log:
                    subprocess.run(['sandbox-exec', '-p', profile, str(executable), str(args.output.resolve()), str(notes.resolve())],
                                   stdout=log, stderr=subprocess.STDOUT, check=True, timeout=45)
                native = json.loads((args.output / 'native-receipt.json').read_text())
                assert native['status'] == 'PASS' and native['architecture'] == architecture and requests and set(requests) == {'/appcast.xml'}
                result.update(status='PASS', runtime_started=True, public_network_denied=True, archive_requested=False,
                              screenshot_sha256=sha(args.output / 'standard-update-dialog.png'))
        finally:
            if not args.compile_only: server.shutdown()
            server.server_close()
            result['loopback_requests'] = requests
            result['native_probe_receipt_present'] = (args.output / 'native-receipt.json').exists()
            (args.output / 'receipt.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result))


if __name__ == '__main__': main()
