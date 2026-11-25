#!/usr/bin/env python3
"""Verify the prepared ZIP and exact signed feed bytes using only the shipped public key."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

PUBLIC_KEY = 'yVPpMoHz8/6GJ82Becd+jgoKvCww+9h2v2Vs6xZu/iw='


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('prepared', 'verifier', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    prepared = args.prepared.resolve()
    receipt = json.loads((prepared / 'receipt.json').read_text())
    assert receipt['public_key'] == PUBLIC_KEY and receipt['build'] == '577'
    archive = prepared / receipt['archive']
    feed = prepared / 'appcast.xml'
    assert archive.parent == prepared
    assert digest(archive) == receipt['archive_sha256'] and digest(feed) == receipt['feed_sha256']
    data = feed.read_bytes()
    marker = b'<!-- sparkle-signatures:\n'
    assert data.count(marker) == 1
    payload, footer = data.split(marker)
    signature = re.fullmatch(rb'edSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\n', footer)
    assert signature is not None and int(signature[2]) == len(payload)
    enclosure = ET.fromstring(data).find('./channel/item/enclosure')
    namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    archive_signature = enclosure.attrib[namespace + 'edSignature']
    args.output.mkdir(exist_ok=False)
    results = {}
    with tempfile.TemporaryDirectory(prefix='saytile577-signed-feed-', dir='/private/tmp') as scratch:
        signed_feed = Path(scratch) / 'signed-payload.xml'
        signed_feed.write_bytes(payload)
        for name, path, value in (('archive', archive, archive_signature),
                                  ('feed', signed_feed, signature[1].decode('ascii'))):
            process = subprocess.run(['swift', '-module-cache-path', '/private/tmp/saytile-update-verify-module-cache',
                str(args.verifier.resolve()), PUBLIC_KEY, value, str(path)], capture_output=True, text=True)
            (args.output / (name + '.log')).write_text(process.stdout + process.stderr)
            assert process.returncode == 0 and 'ED25519_PUBLIC_VERIFICATION_PASS' in process.stdout
            results[name] = dict(status='PASS', verified_bytes=path.stat().st_size,
                                 signed_payload_sha256=digest(path), signature=value)
    result = dict(status='PASS', source=receipt['source'], build='577', public_key=PUBLIC_KEY,
        verification='CryptoKit Ed25519 with the already shipped public key; no signing tool or Keychain access',
        archive_sha256=digest(archive), feed_sha256=digest(feed), results=results,
        crypto_verifier_sha256=digest(args.verifier), wrapper_sha256=digest(Path(__file__)),
        private_key_accessed=False, keychain_accessed=False, app_launched=False, production_feed_modified=False)
    (args.output / 'receipt.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
