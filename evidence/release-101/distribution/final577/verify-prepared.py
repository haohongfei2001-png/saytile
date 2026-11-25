#!/usr/bin/env python3
"""Read and extract the prepared 577 update; never launch or modify an app."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def manifest(app):
    entries, directories = {}, {}
    for path in sorted(app.rglob('*')):
        relative = str(path.relative_to(app))
        mode = stat.S_IMODE(path.lstat().st_mode)
        if path.is_symlink():
            entries[relative] = dict(symlink=os.readlink(path), mode=mode)
        elif path.is_file():
            entries[relative] = dict(bytes=path.stat().st_size, mode=mode, sha256=digest(path))
        elif path.is_dir():
            directories[relative] = mode
        else:
            raise ValueError('Unexpected bundle entry: ' + relative)
    return entries, directories


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('app', 'prepared', 'notes', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--expected-source', required=True)
    args = parser.parse_args()
    app, prepared = args.app.resolve(), args.prepared.resolve()
    receipt = json.loads((prepared / 'receipt.json').read_text())
    assert receipt['status'] == 'PREPARED_NOT_PUBLISHED'
    archive, feed = prepared / receipt['archive'], prepared / 'appcast.xml'
    assert archive.parent == prepared and archive.stat().st_size == receipt['archive_bytes']
    assert digest(archive) == receipt['archive_sha256'] and digest(feed) == receipt['feed_sha256']
    assert receipt['archive_signature_verified_with_published_public_key'] and receipt['signed_feed_verified']
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['SaytileSourceRevision'] == args.expected_source == receipt['source']
    assert info['SaytileSourceDirty'] is False
    assert info['CFBundleShortVersionString'] == receipt['version'] == '1.0.1'
    assert info['CFBundleVersion'] == receipt['build'] == '577'
    assert info['CFBundleIdentifier'] == receipt['bundle_id']
    assert info['SUPublicEDKey'] == receipt['public_key']
    assert digest(app / 'Contents/MacOS/Saytile') == receipt['executable_sha256']
    tree = ET.fromstring(feed.read_bytes())
    namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    item = tree.find('./channel/item')
    assert len(tree.findall('./channel/item')) == 1
    assert item.find(namespace + 'version').text == '577'
    assert item.find(namespace + 'shortVersionString').text == '1.0.1'
    description = item.find('description')
    assert description.attrib[namespace + 'format'] == 'plain-text'
    assert description.text == args.notes.read_text().strip()
    enclosure = item.find('enclosure')
    assert int(enclosure.attrib['length']) == archive.stat().st_size
    assert enclosure.attrib['url'] == 'https://github.com/haohongfei2001-png/saytile/releases/download/v1.0.1/' + archive.name
    assert namespace + 'edSignature' in enclosure.attrib
    before, before_directories = manifest(app)
    args.output.mkdir(parents=True, exist_ok=False)
    extraction = Path(tempfile.mkdtemp(prefix='saytile-577-zip-inspection-', dir='/private/tmp'))
    subprocess.run(['ditto', '-x', '-k', str(archive), str(extraction)], check=True)
    extracted = extraction / 'Saytile.app'
    observed, observed_directories = manifest(extracted)
    assert observed == before and observed_directories == before_directories
    assert manifest(app) == (before, before_directories)
    verified = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(extracted)], capture_output=True, text=True)
    (args.output / 'codesign-verify.log').write_text(verified.stdout + verified.stderr)
    assert verified.returncode == 0
    metadata = subprocess.run(['codesign', '-dv', '--verbose=4', str(extracted)], capture_output=True, text=True, check=True)
    (args.output / 'codesign-metadata.log').write_text(metadata.stdout + metadata.stderr)
    for required in ('Authority=Developer ID Application:', 'flags=0x10000(runtime)', 'Timestamp='):
        assert required in metadata.stderr
    for name in ('receipt.json', 'appcast.xml'):
        shutil.copy2(prepared / name, args.output / name)
    (args.output / 'bundle-manifest.json').write_text(json.dumps(observed, indent=2, sort_keys=True) + '\n')
    (args.output / 'directory-manifest.json').write_text(json.dumps(observed_directories, indent=2, sort_keys=True) + '\n')
    result = dict(status='PASS', source=args.expected_source, version='1.0.1', build='577',
        bundle_id=info['CFBundleIdentifier'], source_dirty=False,
        archive_sha256=digest(archive), archive_bytes=archive.stat().st_size,
        feed_sha256=digest(feed), executable_sha256=receipt['executable_sha256'],
        sealed_bundle_entry_count=len(observed), directory_count=len(observed_directories),
        bundle_manifest_sha256=digest(args.output / 'bundle-manifest.json'),
        all_files_modes_symlinks_equal_to_signed_original=True, all_directory_modes_equal=True,
        signed_inline_notes_match_final_snapshot=True, feed_archive_metadata_match=True,
        original_unchanged=True, developer_id_deep_strict_verification=True,
        hardened_runtime_and_timestamp_present=True, extracted_app_launched=False,
        launchservices_registration_requested=False, quarantine_removed=False,
        public_feed_modified=False, notarization='NOT_ASSESSED_BY_THIS_TOOL',
        extracted_copy=str(extracted), verifier_sha256=digest(Path(__file__)))
    (args.output / 'extraction-receipt.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
