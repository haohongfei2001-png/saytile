#!/usr/bin/env python3
"""Preflight or promote the pinned Saytile candidate using Apple's distribution tools."""
import argparse
import contextlib
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path


HERE = Path(__file__).resolve().parent
VERSION = '1.0.0-rc.2-no-api.9'
SOURCE = 'dc26fe3c59ba55994d29e99ada8d2f0b49ad9886'
DMG_HASH = '0bd16e511f3a1cf65a3618443ef3c498ca517786aa4ad07a0226451a0c2b449d'
EXE_HASH = 'cb3b7a38dae90fccd323b57ee746baedbfcb43b457e0b30dbdcbaedffd35ed00'
APP_ID = 'app.saytile.mac'
CANDIDATE = HERE.parent / 'deliverables/no-api.9' / f'Saytile-{VERSION}-arm64.dmg'
ENTITLEMENTS = HERE / 'audio-input.plist'
EXPECTED_ENTITLEMENTS = {'com.apple.security.device.audio-input': True}


def run(*args):
    result = subprocess.run([str(arg) for arg in args], capture_output=True)
    if result.returncode:
        raise ValueError(f'{Path(str(args[0])).name} exited {result.returncode}: '
                         + result.stderr.decode(errors='replace').strip())
    return result.stdout


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def persist(path, value):
    with path.open('x') as output:
        json.dump(value, output, indent=2)
        output.write('\n')


def tools():
    return {name: run('/usr/bin/xcrun', '--find', name).decode().strip()
            for name in ('notarytool', 'stapler')}


def separate_destination(path):
    resolved = path.resolve()
    require(all(not part.lower().endswith('.app') for part in resolved.parts), 'Destination lies inside an application bundle')
    protected = (HERE.parent / 'deliverables', HERE.parent / 'dist', Path.home() / 'Library/Application Support/Saytile')
    for root in protected:
        base = str(root.resolve()).casefold()
        candidate = str(resolved).casefold()
        require(candidate != base and not candidate.startswith(base + '/'), 'Destination lies in a protected artifact or data directory')


@contextlib.contextmanager
def mount(image):
    with tempfile.TemporaryDirectory(prefix='saytile-distribution-mount-') as raw:
        point = Path(raw)
        run('/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen', '-mountpoint', point, image)
        try:
            yield point / 'Saytile.app'
        finally:
            run('/usr/bin/hdiutil', 'detach', point)


def inspect(app, verify_original):
    require(app.is_dir() and not app.is_symlink(), 'Expected Saytile.app directory')
    binary = app / 'Contents/MacOS/Saytile'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == APP_ID and info.get('CFBundleExecutable') == 'Saytile'
            and info.get('SaytileSourceDirty') is False and info.get('SaytileSourceRevision') == SOURCE
            and info.get('SaytileReleaseVersion') == VERSION, 'Candidate bundle identity mismatch')
    require(bool(info.get('NSMicrophoneUsageDescription')) and bool(info.get('NSSpeechRecognitionUsageDescription')),
            'Missing capture or speech usage description')
    # This fixed static package has one executable. Future nested code needs explicit inside-out signing.
    resources = {}
    for file in app.rglob('*'):
        require(not file.is_symlink(), 'Unexpected link inside application')
        if file.is_file() and '_CodeSignature' not in file.parts and file != binary:
            magic = file.read_bytes()[:4]
            require(magic.hex() not in {'feedface','cefaedfe','feedfacf','cffaedfe','cafebabe','bebafeca','cafebabf','bfbafeca'},
                    'Unexpected nested Mach-O code in fixed application')
            resources[str(file.relative_to(app))] = digest(file)
    require(run('/usr/bin/lipo', '-archs', binary).decode().strip() == 'arm64', 'Expected arm64 executable')
    if verify_original:
        require(digest(binary) == EXE_HASH, 'Original executable hash mismatch')
    run('/usr/bin/codesign', '--verify', '--strict', app)
    return resources


def check_candidate(image, destination=None):
    require(image.is_file() and not image.is_symlink() and digest(image) == DMG_HASH, 'Pinned candidate DMG SHA-256 mismatch')
    run('/usr/bin/hdiutil', 'verify', image)
    with mount(image) as app:
        resources = inspect(app, True)
        if destination:
            run('/usr/bin/ditto', '--norsrc', app, destination)
            require(resources == inspect(destination, True), 'Copied resources changed')
    require(digest(image) == DMG_HASH, 'Candidate changed while mounted')
    return resources


def check_signature(path, team, app=False):
    require(re.fullmatch('[A-Z0-9]{10}', team), 'Expected a 10-character Team ID')
    identifier = APP_ID if app else APP_ID + '.distribution'
    requirement = (f'=identifier "{identifier}" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists '
                   'and certificate leaf[field.1.2.840.113635.100.6.1.13] exists '
                   f'and certificate leaf[subject.OU] = "{team}"')
    run('/usr/bin/codesign', '--verify', '--strict', '-R', requirement, path)
    details = subprocess.run(['/usr/bin/codesign', '-dvvv', str(path)], capture_output=True, check=True).stderr.decode()
    require(re.search(r'^Timestamp=.+$', details, re.M), 'Secure signing timestamp missing')
    if app:
        require(re.search(r'flags=0x[\da-f]+\([^)]*\bruntime\b', details), 'Missing hardened runtime')
        entitlements = plistlib.loads(run('/usr/bin/codesign', '-d', '--xml', '--entitlements', '-', path))
        require(entitlements == EXPECTED_ENTITLEMENTS, 'Unexpected app entitlements')


def submit(args):
    require(re.fullmatch('[0-9a-fA-F]{40}', args.identity), 'Supply the exact Developer ID Application certificate SHA-1')
    require(re.fullmatch('[A-Z0-9]{10}', args.team), 'Supply the issuing Team ID')
    require(bool(args.profile.strip()), 'Supply an existing notarytool keychain profile name')
    require(plistlib.loads(ENTITLEMENTS.read_bytes()) == EXPECTED_ENTITLEMENTS, 'Entitlement policy changed')
    separate_destination(args.work)
    programs = tools()
    args.work.mkdir(mode=0o700, exist_ok=False)
    stage = args.work / 'image-root'
    stage.mkdir()
    app = stage / 'Saytile.app'
    resources = check_candidate(args.candidate, app)
    run('/usr/bin/codesign', '--force', '--sign', args.identity, '--timestamp', '--options', 'runtime', '-i', APP_ID,
        '--entitlements', ENTITLEMENTS, app)
    check_signature(app, args.team, app=True)
    require(inspect(app, False) == resources, 'Signed copy changed app resources')
    exe = digest(app / 'Contents/MacOS/Saytile')
    (stage / 'Applications').symlink_to('/Applications')
    (stage / '安装与使用.txt').write_text(
        f'Saytile {VERSION}\n\n本包来自固定个人候选，发行方已完成 Developer ID 签名和 Apple 公证。'
        '云端识别需要用户单独配置服务、授权音频上传并完成连接检查。\n\n'
        '如需保留 RC1，请保留原 RC1.app。在升级前完全退出 Saytile，将整个 '
        '~/Library/Application Support/Saytile 目录复制到独立备份位置，包含数据库、WAL、Audio 和其他文件。'
        '使用新版本后仍保留这份升级前备份。回退时从完整备份还原，RC1 无法直接打开升级后的资料库。\n\n'
        '经用户选择升级后，将本磁盘中的 Saytile.app 拖入 Applications。原候选、源码、安装与恢复说明：\n'
        f'https://github.com/haohongfei2001-png/saytile/blob/{SOURCE}/docs/V1-INSTALL.md\n'
        f'https://github.com/haohongfei2001-png/saytile/tree/{SOURCE}\n'
        'https://github.com/haohongfei2001-png/saytile/tree/0aa51620c63612246395d8f2a83e1eb96c9e94c4/deliverables/no-api.9\n')
    image = args.work / 'staged.dmg'
    run('/usr/bin/hdiutil', 'create', '-volname', f'Saytile {VERSION}', '-srcfolder', stage, '-format', 'UDZO', image)
    run('/usr/bin/codesign', '--sign', args.identity, '--timestamp', '-i', APP_ID + '.distribution', image)
    check_signature(image, args.team)
    persist(args.work / 'signed.json', {'source': SOURCE, 'version': VERSION, 'team': args.team,
            'candidate_dmg_sha256': DMG_HASH, 'signed_executable_sha256': exe,
            'resources': resources, 'submitted_dmg_sha256': digest(image)})
    # Submit exactly once. Preserve the original reply even on timeout or error.
    result = subprocess.run([programs['notarytool'], 'submit', str(image), '--keychain-profile', args.profile,
                             '--no-wait', '--output-format', 'json'], capture_output=True)
    (args.work / 'submission.json').write_bytes(result.stdout)
    (args.work / 'submission-errors.txt').write_bytes(result.stderr)
    require(result.returncode == 0, 'Submission did not complete; inspect the preserved reply and Apple submission history')
    submission = uuid.UUID(json.loads(result.stdout)['id'])
    print(f'Submitted {submission}. Run finish after processing completes. Work directory: {args.work}')


def finish(args):
    separate_destination(args.output)
    separate_destination(args.work)
    require(not os.path.lexists(args.output) and args.output.suffix.lower() == '.dmg', 'Output must be a new DMG path')
    require(args.output.parent.is_dir(), 'Output parent must exist')
    programs = tools()
    info = json.loads((args.work / 'signed.json').read_text())
    require(info['candidate_dmg_sha256'] == DMG_HASH and info['source'] == SOURCE and info['version'] == VERSION, 'Release identity mismatch')
    require(bool(args.profile.strip()), 'Supply the existing notarytool keychain profile name')
    job = str(uuid.UUID(json.loads((args.work / 'submission.json').read_text())['id']))
    image = args.work / 'staged.dmg'
    require(digest(image) == info['submitted_dmg_sha256'], 'Submitted disk image changed')
    status = json.loads(run(programs['notarytool'], 'info', job, '--keychain-profile', args.profile, '--output-format', 'json'))
    (args.work / 'notary-status.json').write_text(json.dumps(status, indent=2) + '\n')
    require(uuid.UUID(status['id']) == uuid.UUID(job) and status.get('status') == 'Accepted', f'Notary job {job} state: {status.get("status")}')
    log = run(programs['notarytool'], 'log', job, '--keychain-profile', args.profile)
    (args.work / 'notary-log.json').write_bytes(log)
    report = json.loads(log)
    require(uuid.UUID(report['jobId']) == uuid.UUID(job) and report['status'] == 'Accepted'
            and report['sha256'].lower() == info['submitted_dmg_sha256'], 'Apple notary log does not match the signed submission')
    with tempfile.TemporaryDirectory(prefix='.saytile-verified-', dir=args.output.parent) as raw:
        final = Path(raw) / 'final.dmg'
        shutil.copyfile(image, final)
        require(digest(final) == info['submitted_dmg_sha256'], 'DMG copy mismatch')
        run(programs['stapler'], 'staple', final)
        run(programs['stapler'], 'validate', final)
        check_signature(final, info['team'])
        run('/usr/bin/hdiutil', 'verify', final)
        run('/usr/sbin/spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', final)
        with mount(final) as app:
            require(inspect(app, False) == info['resources'], 'Final app resources changed')
            require(digest(app / 'Contents/MacOS/Saytile') == info['signed_executable_sha256'], 'Final signed executable changed')
            check_signature(app, info['team'], app=True)
            run('/usr/sbin/spctl', '--assess', '--type', 'execute', app)
        output_hash = digest(final)
        os.link(final, args.output)  # Atomic no-replace publication on the destination filesystem.
    print(json.dumps({'output': str(args.output), 'sha256': output_hash, 'source': SOURCE, 'submission_id': job}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    preview = sub.add_parser('preflight')
    preview.add_argument('--candidate', type=Path, default=CANDIDATE)
    send = sub.add_parser('submit')
    for key in ('identity', 'team', 'profile'):
        send.add_argument('--' + key, required=True)
    send.add_argument('--work', type=Path, required=True)
    send.add_argument('--candidate', type=Path, default=CANDIDATE)
    done = sub.add_parser('finish')
    done.add_argument('--profile', required=True)
    done.add_argument('--work', type=Path, required=True)
    done.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'preflight':
        programs = tools()
        with tempfile.TemporaryDirectory(prefix='saytile-distribution-copy-') as raw:
            resources = check_candidate(args.candidate, Path(raw) / 'Saytile.app')
        print(json.dumps({'result': 'OFFLINE_PREFLIGHT_PASS', 'source': SOURCE, 'version': VERSION, 'dmg_sha256': DMG_HASH,
              'executable_sha256': EXE_HASH, 'resources': len(resources), 'tools': programs, 'signed_or_submitted': False}, indent=2))
    elif args.command == 'submit':
        submit(args)
    else:
        finish(args)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print(f'DISTRIBUTION_FAILED: {error}', file=sys.stderr)
        sys.exit(1)
