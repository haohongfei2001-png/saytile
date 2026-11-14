"""Read-only contract for this 0.18 Mandarin candidate's signed update configuration."""
import base64
import hashlib
import json
import plistlib
from pathlib import Path

BUNDLE = 'app.saytile.mac.mandarin-candidate'
PUBLIC_KEY = 'yVPpMoHz8/6GJ82Becd+jgoKvCww+9h2v2Vs6xZu/iw='
FEED_ROOT = 'https://raw.githubusercontent.com/haohongfei2001-png/saytile/codex/update-feed/'
CHANNELS = {'app.saytile.mac': 'standard', BUNDLE: 'mandarin'}
FLAGS = dict(SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
             SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=False,
             SUAllowsAutomaticUpdates=False, SUEnableSystemProfiling=False,
             SUSendProfileInfo=False)
INTERVALS = dict(SUSignedFeedFailureExpirationInterval=0, SUScheduledCheckInterval=86400)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate update configuration key')
        result[key] = value
    return result


def verify_update_configuration(app, source_config=None):
    app = Path(app)
    resource = app / 'Contents/Resources/UpdateChannels.json'
    require(resource.is_file() and not resource.is_symlink(), 'Missing signed channel provenance')
    raw = resource.read_bytes()
    if source_config is not None:
        require(raw == Path(source_config).read_bytes(), 'Packaged channel file differs from source')
    config = json.loads(raw, object_pairs_hook=unique)
    require(set(config) == {'schemaVersion', 'channels'} and type(config['schemaVersion']) is int
            and config['schemaVersion'] == 1, 'Wrong channel schema')
    expected = {bundle: dict(channel=channel, feedURL=FEED_ROOT + channel + '/appcast.xml',
                            publicEDKey=PUBLIC_KEY) for bundle, channel in CHANNELS.items()}
    require(config['channels'] == expected, 'Unexpected release channel, endpoint or public key')
    public = base64.b64decode(PUBLIC_KEY, validate=True)
    require(len(public) == 32 and base64.b64encode(public).decode() == PUBLIC_KEY, 'Wrong public key format')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    require(info['CFBundleIdentifier'] == info.get('SaytileUpdateBundleIdentifier') == BUNDLE
            and info.get('SaytileUpdateChannel') == 'mandarin', 'Update channel crosses app profiles')
    require(info.get('SUFeedURL') == expected[BUNDLE]['feedURL']
            and info.get('SUPublicEDKey') == PUBLIC_KEY, 'Unexpected signed feed or key')
    require(all(info.get(key) is value for key, value in FLAGS.items()), 'Unsafe update or privacy flags')
    require(all(type(info.get(key)) is int and info[key] == value for key, value in INTERVALS.items()),
            'Unsafe feed signature expiry or scheduled check interval')
    return dict(bundle=BUNDLE, channel='mandarin', feed_url=info['SUFeedURL'],
                public_key_sha256=hashlib.sha256(public).hexdigest(), flags=FLAGS, intervals_seconds=INTERVALS,
                source_configuration_sha256=hashlib.sha256(raw).hexdigest())
