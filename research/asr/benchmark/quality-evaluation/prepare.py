#!/usr/bin/env python3
"""Write disabled non-secret configs and JSON argv only. Never execute a probe."""
import argparse
import json
from pathlib import Path

MODEL_IDS = {'qwenMessage': 1, 'assemblyAI': 2, 'soniox': 3, 'openAIResponses': 4,
             'gemini': 5, 'elevenLabsFile': 6, 'meta': 7}


def config_template(spec):
    models = []
    for model in spec['models']:
        index = MODEL_IDS[model['provider']]
        models.append({
            'id': f'A71E0001-0000-4000-8000-{index:012d}',
            'purpose': model['purpose'], 'provider': model['provider'], 'model': model['model'],
            'enabled': True, 'cloudConsent': False,
            'region': 'cn-beijing' if model['provider'] == 'qwenMessage' else 'global',
            'workspaceID': 'REPLACE-WITH-APPROVED-WORKSPACE' if model['provider'] == 'qwenMessage' else '',
            'context': '', 'audioHourRate': None, 'inputMillionTokenRate': None,
            'outputMillionTokenRate': None, 'currency': 'USD',
            'reasoningEffort': model.get('reasoningEffort', 'high'),
            'reasoningMode': model.get('reasoningMode', 'standard')})
    return {'cloudEnabled': False, 'inputMode': spec['input_mode'], 'models': models,
            'topicContext': '', 'automaticRecovery': False}


def write_preserving(path, value):
    data = json.dumps(value, ensure_ascii=False, indent=2) + '\n'
    if path.exists() and path.read_text() != data:
        raise ValueError('Refusing to replace a changed prepared file: ' + str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data)


def generate(plan, output, audio_root, app, panel='24'):
    output = Path(output).resolve()
    fixtures = {x['id']: x for x in plan['fixtures']}
    commands = []
    for spec in plan['configurations']:
        configuration = output / 'configurations' / (spec['id'] + '.json')
        write_preserving(configuration, config_template(spec))
        for fixture_id in plan['panels'][panel]['ids']:
            fixture = fixtures[fixture_id]
            args = [str(app), '--multi-asr-probe', str(Path(audio_root) / fixture['audio']),
                    '--recognition-config', str(configuration), '--data-directory',
                    str(output / 'isolated-data' / spec['id'] / fixture_id),
                    '--report-dir', str(output / 'reports' / spec['id'] / fixture_id)]
            if spec['evaluation_mode'] == 'single-expert-baseline':
                args.append('--single-expert-baseline')
            commands.append({'configuration_id': spec['id'], 'fixture_id': fixture_id,
                'expected_audio_sha256': fixture['audio_sha256'], 'argv': args,
                'status': 'NOT_RUN', 'execution_authorized': False})
    document = {'schema_version': 1, 'status': 'PREPARE_ONLY_NO_EXECUTION',
        'panel': panel, 'configuration_count': len(plan['configurations']), 'commands': commands,
        'blocked_until': ['Explicit cloud processing and cost authorization for these public fixtures',
            'Per-service approved account/workspace and per-configuration Keychain keys',
            'Explicit aggregate budget and actual-usage checkpoints for repeated reviews; no hard cap is implemented here',
            'Review and separately enable cloudEnabled plus individual cloudConsent flags'],
        'notes': ['No audio files or Keychain/UserDefaults were read by preparation.',
                  'Stable IDs match the app recommended model identities; no credential is serialized.',
                  'Every configuration/clip has its own empty data directory. Never point this at a production archive.',
                  'JSON argv is a reviewable plan, not a shell script or executed command.']}
    write_preserving(output / 'commands.json', document)
    write_preserving(output / 'planned-workload.json', plan['planned_workloads'][panel])
    return document


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--plan', required=True, type=Path); parser.add_argument('--outdir', required=True, type=Path)
    parser.add_argument('--audio-root', required=True, help='Declared public corpus path; not opened by this script.')
    parser.add_argument('--app', required=True, help='Candidate executable path; never invoked by this script.')
    parser.add_argument('--panel', choices=['24', '48', '112'], default='24')
    args = parser.parse_args()
    result = generate(json.loads(args.plan.read_text()), args.outdir, args.audio_root, args.app, args.panel)
    print(json.dumps({'status': result['status'], 'configurations': result['configuration_count'],
                      'commands_not_executed': len(result['commands'])}))
