#!/usr/bin/env python3
"""Local preparation and recorded-evidence scoring. No model invocation or network."""
import argparse
import copy
import hashlib
import json
import re
import subprocess
import sys
import wave
from collections import Counter
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
QUALITY = HERE.parent / 'quality-evaluation'
sys.path.insert(0, str(QUALITY))
import evaluate as ev
from metrics import ROOT, score_text, paired_errors
from reference_annotations import load_references
from prepare import config_template

FROZEN_PLAN_SHA = 'cd2ea2725258f899756e343a6647ed1f3ac41d070a97796476a91369c8458943'
UNAVAILABLE_F = {'status': 'NOT_AVAILABLE', 'metrics': None,
                 'reason': 'Product contract: gpt-6-astra official native audio input is not supported.'}


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
    require(not path.exists() or path.read_text() == data,
            'Refusing to overwrite changed evidence; use a fresh output directory.')
    path.write_text(data)


def frozen():
    path = QUALITY / 'plan.json'
    require(ev.checksum(path) == FROZEN_PLAN_SHA, 'Frozen selection plan changed.')
    old = ev.load_json(path)
    require(ev.checksum(ROOT / old['manifest_path']) == old['manifest_sha256'], 'Frozen manifest changed.')
    annotation = old['reference_annotations']
    items, _ = load_references(ROOT / old['manifest_path'], ROOT / annotation['path'], annotation['sha256'])
    by_id = {x['id']: x for x in items}
    ids = old['panels']['24']['ids']
    require(len(ids) == len(set(ids)) == 24, 'Not the frozen 24 panel.')
    require(all(by_id[x]['human_voice'] and not by_id[x]['synthetic_perturbation'] for x in ids),
            'Synthetic data cannot enter the human panel.')
    return old, by_id, ids


def configurations():
    models = {
        'Q': dict(provider='qwenMessage', model='qwen-audio-3.1-asr-flash-message', purpose='chineseASR'),
        'A': dict(provider='assemblyAI', model='universal-3-6-pro', purpose='englishASR'),
        'S': dict(provider='soniox', model='stt-rt-v6', purpose='multilingualASR'),
        'G': dict(provider='openAIResponses', model='gpt-6-astra', purpose='textFusion',
                  reasoningEffort='high', reasoningMode='standard')}
    return [{'id': ident, 'models': [copy.deepcopy(models[x]) for x in codes],
             'input_mode': 'highestQuality', 'topicContext': '', 'execution': 'multi_trace',
             'evaluation_mode': 'single-expert-baseline' if ident in 'ABD' else 'multi-expert-fusion'}
            for ident, codes in [('A', 'QG'), ('B', 'AG'), ('C', 'QAG'), ('D', 'SG'), ('E', 'QASG')]]


def reference_hash(item):
    return sha(item['reference'].encode())


def audio_receipt(root, item):
    relative = Path(item['audio'])
    require(not relative.is_absolute() and '..' not in relative.parts, 'Unsafe manifest audio path.')
    path = root / relative
    result = {'id': item['id'], 'audio': item['audio'], 'expected_sha256': item['audio_sha256'],
              'exists': path.is_file(), 'status': 'BLOCKED', 'pcm_sha256': None}
    if not path.is_file():
        result['reason'] = 'AUDIO_MISSING'
        return result
    require(path.resolve().is_relative_to(root.resolve()), 'Audio path escapes corpus root.')
    result['sha256'] = ev.checksum(path)
    try:
        with wave.open(str(path), 'rb') as wav:
            pcm = wav.readframes(wav.getnframes())
            result.update(sample_rate=wav.getframerate(), frames=wav.getnframes(),
                          channels=wav.getnchannels(), sample_width_bytes=wav.getsampwidth(),
                          compression=wav.getcomptype(), pcm_bytes=len(pcm), pcm_sha256=sha(pcm))
        valid = (result['sha256'] == item['audio_sha256'] and result['sample_rate'] == item['sample_rate'] == 16000
                 and result['frames'] == item['frames'] and result['channels'] == 1
                 and result['sample_width_bytes'] == 2 and result['compression'] == 'NONE'
                 and result['pcm_bytes'] == item['frames'] * 2)
        result.update(status='VERIFIED' if valid else 'BLOCKED', reason=None if valid else 'AUDIO_INTEGRITY_MISMATCH')
    except (wave.Error, EOFError):
        result['reason'] = 'INVALID_PCM_WAV'
    return result


def preflight(audio_root, access_path):
    old, items, ids = frozen()
    audio = [audio_receipt(Path(audio_root), item) for item in items.values()]
    originals = [x for x in audio if x['id'] in old['original_ids']]
    historical = []
    for config in old['legacy_configurations']:
        path = ROOT / config['results_path']
        records = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
        valid = (ev.checksum(path) == config['sha256'] and len(records) == 112
                 and {r['id'] for r in records} == set(old['original_ids'])
                 and all(r['audio_sha256'] == items[r['id']]['audio_sha256']
                         and r['engine'] == config['engine']
                         and (not config.get('model') or r.get('model') == config['model']) for r in records)
                 and all(r['status'] == 'VERIFIED' for r in originals))
        historical.append({'id': config['id'], 'path': config['results_path'], 'sha256': ev.checksum(path),
                           'records': len(records), 'status': 'VERIFIED_HISTORICAL' if valid else 'BLOCKED',
                           'locale_policy': config.get('locale_policy'), 'cloud_A_E_records': 0})
    raw_access = ev.load_json(access_path)  # Supplied metadata only; never query keys/settings.
    fields = ('configuration_present', 'cloud_enabled', 'enabled_services', 'matching_item_count',
              'metadata_query_status', 'secret_values_requested', 'permission_prompt_allowed',
              'paid_requests', 'audio_uploaded')
    access = {k: raw_access.get(k) for k in fields}
    blockers = [
        {'code': 'CONFIGURATION_MISSING', 'applies_to': list('ABCDE'), 'status': 'BLOCKED' if access['configuration_present'] is not True else 'PRESENT_NOT_VALIDATED'},
        {'code': 'KEYCHAIN_KEYS_MISSING', 'applies_to': list('ABCDE'), 'status': 'BLOCKED' if access['matching_item_count'] == 0 else 'UNVERIFIED_PER_UUID'},
        {'code': 'CLOUD_DISABLED', 'applies_to': list('ABCDE'), 'status': 'BLOCKED' if access['cloud_enabled'] is not True else 'REQUIRES_SEPARATE_AUTHORIZATION'},
        {'code': 'PROCESSING_AND_COST_AUTHORIZATION_NOT_GRANTED', 'applies_to': list('ABCDE'), 'status': 'BLOCKED'},
        {'code': 'QWEN_APPROVED_WORKSPACE_NOT_SUPPLIED', 'applies_to': list('ACE'), 'status': 'BLOCKED'},
        {'code': 'NATIVE_CANDIDATE_NOT_VALIDATED', 'applies_to': list('ABCDE'), 'status': 'NOT_RUN'},
        {'code': 'D_MULTILINGUAL_SINGLE_EXPERT_VALIDATION_PENDING', 'applies_to': ['D'], 'status': 'BLOCKED_AT_INSPECTED_SOURCE'},
    ]
    return {'schema_version': 1, 'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'frozen_plan_sha256': FROZEN_PLAN_SHA, 'manifest_sha256': old['manifest_sha256'],
            'reference_annotations': old['reference_annotations'],
            'access_preflight_sha256': ev.checksum(access_path), 'access_metadata': access,
            'cloud_status': 'BLOCKED', 'cloud_performance': None, 'blockers': blockers, 'F': UNAVAILABLE_F,
            'corpus': {'manifest_rows': len(items), 'on_disk_manifest_samples': sum(x['exists'] for x in audio),
                       'verified_originals': sum(x['status'] == 'VERIFIED' for x in originals),
                       'absent_manifest_samples': [x['id'] for x in audio if not x['exists']],
                       'on_disk_wav_files': len(list(Path(audio_root).glob('*.wav'))),
                       'panel_count': len(ids), 'panel_verified': sum(x['status'] == 'VERIFIED' for x in audio if x['id'] in ids),
                       'panel_language_counts': dict(Counter(items[x]['language'] for x in ids))},
            'audio_integrity': audio, 'historical': historical,
            'historical_verified_records': sum(x['records'] for x in historical if x['status'] == 'VERIFIED_HISTORICAL'),
            'local_only': True, 'remote_state': 'NOT_RUN_LOCAL_ONLY_INSTRUCTION',
            'limitations': ['Historical oracle locale is not automatic mixed-language routing.',
                           'Qwen Message and AssemblyAI are engineering candidates, not winners.',
                           'Metadata is a receipt at inspection time, not current permission or per-provider validation.']}


def prepare(out, app):
    old, items, ids = frozen()
    out = Path(out)
    commands = []
    configs = configurations()
    for spec in configs:
        write(out / 'configurations' / (spec['id'] + '.json'), config_template(spec))
    # Rotate configuration order per clip; every expert still receives the complete same WAV/PCM.
    for i, ident in enumerate(ids):
        for spec in configs[i % 5:] + configs[:i % 5]:
            key = spec['id']
            argv = [app, '--multi-asr-probe', '${AUDIO_ROOT}/' + items[ident]['audio'],
                    '--recognition-config', '${RUN_ROOT}/configurations/' + key + '.json',
                    '--data-directory', '${RUN_ROOT}/isolated-data/' + key + '/' + ident,
                    '--report-dir', '${RUN_ROOT}/reports/' + key + '/' + ident]
            if key in 'ABD':
                argv.append('--single-expert-baseline')
            commands.append({'configuration_id': key, 'fixture_id': ident, 'argv': argv,
                             'audio_sha256': items[ident]['audio_sha256'], 'reference_sha256': reference_hash(items[ident]),
                             'status': 'NOT_RUN', 'execution_authorized': False})
    plan = {'schema_version': 1, 'status': 'PREPARE_ONLY', 'frozen_plan_sha256': FROZEN_PLAN_SHA,
            'manifest_sha256': old['manifest_sha256'], 'reference_annotations': old['reference_annotations'],
            'ids': ids, 'configurations': configs, 'F': UNAVAILABLE_F, 'commands': commands,
            'audio_policy': 'identical_full_pcm_to_every_expert_no_language_routing',
            'fusion_policy': 'one_identical_GPT6_text_core_verbatim_evidence_only',
            'dynamic_gpt_call_count': None, 'planned_native_sessions': len(commands)}
    write(out / 'commands.json', plan)
    return plan


def missing_row(spec, item):
    return {'fixture_id': item['id'], 'configuration_id': spec['id'], 'audio_sha256': item['audio_sha256'],
            'reference_sha256': reference_hash(item), 'language': item['language'], 'group': item['group'],
            'execution': 'multi_trace', 'identity': 'NOT_RUN', 'status': 'NOT_RUN', 'source_revision': None,
            'stages': {s: ev.unavailable('No recorded native trace.') for s in ev.STAGES},
            'raw_asr': [], 'gpt_reviews': [], 'gpt_error_pairs': [], 'latencies': {}, 'revisions': [],
            'stable_formation': {'status': 'NOT_RUN', 'formed': None}, 'service_runs': []}


def validate_trace(spec, item, trace, source_commit, exact_config):
    require(re.fullmatch('[0-9a-f]{40}', source_commit or '') is not None, 'Full native source commit required.')
    require(trace.get('sourceRevision') == source_commit, 'Native source commit mismatch.')
    require(trace.get('schemaVersion', 0) >= 2 and not trace.get('synthetic')
            and trace.get('provenance') not in ('synthetic', 'gold', 'reference'), 'Not native trace evidence.')
    require(trace.get('configuration') == exact_config, 'Exact recorded configuration mismatch.')
    template = config_template(spec)
    # Only separately authorized cloud flags, workspace and billing metadata may differ.
    require(set(exact_config) == set(template), 'Unknown configuration fields require explicit schema review.')
    require(exact_config.get('cloudEnabled') is True, 'Native cloud trace has disabled cloud.')
    require(exact_config['inputMode'] == 'highestQuality' and exact_config['topicContext'] == ''
            and exact_config['automaticRecovery'] is False, 'Shared configuration drift.')
    require(len(exact_config['models']) == len(template['models']), 'Model count mismatch.')
    for expected, actual in zip(template['models'], exact_config['models']):
        allowed = {'workspaceID', 'cloudConsent', 'audioHourRate', 'inputMillionTokenRate', 'outputMillionTokenRate'}
        require(not set(actual) - set(expected), 'Unknown model fields.')
        require(all(actual.get(k) == v for k, v in expected.items() if k not in allowed), 'Model/UUID/parameter drift.')
        require(actual.get('cloudConsent') is True, 'Cloud consent absent in recorded configuration.')
        if actual['provider'] == 'qwenMessage':
            require(bool(actual.get('workspaceID')) and 'REPLACE' not in actual['workspaceID'], 'Unconfigured Qwen workspace.')
    for collection in ('candidates', 'fusionDecisions', 'revisions'):
        entries = trace.get(collection, [])
        require(len({x['id'] for x in entries}) == len(entries), 'Duplicate trace event IDs.')
    row = ev.trace_row(spec, item, trace)
    require(row['identity'] == 'MATCHED_EMBEDDED_AUDIO_AND_CONFIGURATION', 'Trace identity mismatch.')
    row['exact_configuration'] = exact_config
    row['configuration_canonical_sha256'] = ev.parameter_fingerprint(exact_config)
    row['reference_sha256'] = reference_hash(item)
    # Shared evaluator's omission-penalty fallback is not an observed GPT output.
    if row['stages']['final'].get('source') == 'no_confirmed_final_service_failure_counted_as_omissions':
        row['stages']['final'] = {**ev.unavailable('Service failed; no final output observed.'), 'status': 'FAILED'}
    return row


def complete(candidate, item, eof):
    return (candidate.get('isComplete') is True and candidate.get('audioStartSeconds') == 0
            and ev.finite(candidate.get('audioEndSeconds'))
            and abs(candidate['audioEndSeconds'] - item['frames'] / item['sample_rate']) <= 1 / item['sample_rate']
            and ev.finite(eof) and ev.finite(candidate.get('createdAt')) and candidate['createdAt'] >= eof)


def enrich(row, trace, item):
    """Keep every revision/review; never select a winner using the reference."""
    generation = trace['replay']['recognitionID']
    recording = trace['recording']['id']
    models = {m['id']: m for m in trace['configuration']['models']}
    def current(run):
        model = models.get(run.get('configurationID'), {})
        return (run.get('recognitionID') == generation and run.get('recordingID') == recording
                and bool(model) and all(run.get(k) == model[k] for k in ('provider', 'model', 'purpose')))
    candidates = {x['id']: x for x in trace.get('candidates', []) if current(x['run']) and x['run']['purpose'] != 'textFusion'}
    eof = trace['replay'].get('lastAudioSubmittedAt')
    row['raw_asr'] = []
    for candidate in sorted(candidates.values(), key=lambda c: (c.get('createdAt', 0), c['id'])):
        full = complete(candidate, item, eof)
        row['raw_asr'].append({'candidate_id': candidate['id'], 'run': candidate['run'],
            'sequence': candidate.get('sequence'), 'is_complete': candidate.get('isComplete'),
            **ev.observation(item, candidate['text'], 'raw_asr', candidate.get('createdAt'),
                             item['reference'] if full else None, 'complete_reference' if full else None)})
    row['revisions'] = [x for x in trace.get('fusionDecisions', []) if x.get('recognitionID') == generation]
    runs = {x['ticket']['id']: x for x in trace.get('modelRuns', []) if current(x['ticket'])}
    row['service_runs'] = [{'run_id': r['ticket']['id'], 'provider': r['ticket']['provider'],
                            'model': r['ticket']['model'], 'state': r['state'], 'error': r.get('error')}
                           for r in runs.values()]
    row['gpt_reviews'], row['gpt_error_pairs'] = [], []
    for usage in trace.get('modelUsage', []):
        run = runs.get(usage.get('runID'))
        if not run or run['ticket']['purpose'] != 'textFusion':
            continue
        entry = {'usage_id': usage['id'], 'run_id': usage['runID'], 'run_state': run['state'],
                 'status': 'NOT_RUN', 'text': None, 'accuracy': None,
                 'elapsed_seconds': usage.get('elapsedSeconds'), 'at_epoch_ms': usage.get('createdAt'),
                 'reason': 'No verifiable complete selection; never fill with reference.'}
        evidence = usage.get('arbitrationResponse') or {}
        decision = evidence.get('decision') or {}
        spans = decision.get('selections', [])
        entry['response_evidence'] = evidence or None
        # Conservative full-clip scope: exact single complete acoustic selection.
        # Partial/spliced responses remain auditable, not scored against whole gold.
        if len(spans) == 1:
            span = spans[0]
            candidate = candidates.get(span.get('candidateID'))
            if (candidate and candidate['id'] in evidence.get('candidateIDs', [])
                    and span.get('utf16Start') == 0
                    and span.get('utf16End') == len(candidate['text'].encode('utf-16-le')) // 2
                    and complete(candidate, item, eof) and ev.finite(usage.get('createdAt'))
                    and candidate['createdAt'] <= usage['createdAt']):
                entry.update(ev.observation(item, candidate['text'], 'gpt_selection', usage['createdAt'],
                                            item['reference'], 'complete_reference'))
                entry['reason'] = 'Decoded GPT selection, not proof of accepted publication or semantic truth.'
                for raw in row['raw_asr']:
                    if (raw['accuracy'] is not None and raw['candidate_id'] in evidence.get('candidateIDs', [])
                            and raw['at_epoch_ms'] <= usage['createdAt']):
                        row['gpt_error_pairs'].append({'raw_candidate_id': raw['candidate_id'], 'gpt_usage_id': usage['id'],
                            'reference_sha256': reference_hash(item), 'audio_sha256': item['audio_sha256'],
                            'status': 'PAIRED_LEXICAL_SELECTION', **paired_errors(raw['accuracy'], entry['accuracy'])})
        row['gpt_reviews'].append(entry)
    return row


def index_traces(run_root, output, source_commit):
    """Freeze existing native exports, not generated outputs or hypotheses."""
    require(re.fullmatch('[0-9a-f]{40}', source_commit or '') is not None, 'Full native source commit required.')
    _, items, ids = frozen()
    entries = []
    for spec in configurations():
        for ident in ids:
            paths = sorted((Path(run_root) / 'reports' / spec['id'] / ident).glob('*.json'))
            require(len(paths) <= 1, 'Multiple attempts: select an explicit fresh run directory, never best-of.')
            if not paths:
                continue
            path = paths[0]
            trace = ev.load_json(path)
            exact = trace.get('configuration', {})
            validate_trace(spec, items[ident], trace, source_commit, exact)
            # Index stays local. Output paths never appear in the scored public report.
            entries.append({'configuration_id': spec['id'], 'fixture_id': ident, 'trace_path': str(path.resolve()),
                            'trace_sha256': ev.checksum(path), 'reference_sha256': reference_hash(items[ident]),
                            'provenance': 'native_multi_asr_probe', 'exact_configuration': exact})
    index = {'schema_version': 1, 'source_commit': source_commit, 'records': entries}
    write(output, index)
    return index


def score(index=None):
    old, items, ids = frozen()
    index = index or {'records': [], 'source_commit': None}
    records = index['records']
    indexed = {(r['configuration_id'], r['fixture_id']): r for r in records}
    require(len(indexed) == len(records), 'Duplicate attempt identities.')
    require(set(indexed) <= {(c, i) for c in 'ABCDE' for i in ids}, 'Unknown panel or configuration.')
    rows = {}
    for spec in configurations():
        rows[spec['id']] = []
        for ident in ids:
            item = items[ident]
            record = indexed.get((spec['id'], ident))
            row = missing_row(spec, item)
            if record:
                require(record['provenance'] == 'native_multi_asr_probe', 'Synthetic/gold output cannot enter results.')
                require(record['reference_sha256'] == reference_hash(item), 'Reference pair identity mismatch.')
                require(ev.checksum(record['trace_path']) == record['trace_sha256'], 'Raw trace receipt mismatch.')
                trace = ev.load_json(record['trace_path'])
                row = enrich(validate_trace(spec, item, trace, index['source_commit'], record['exact_configuration']), trace, item)
                row['trace_sha256'] = record['trace_sha256']
            rows[spec['id']].append(row)
        require(len({r['configuration_canonical_sha256'] for r in rows[spec['id']]
                     if r.get('configuration_canonical_sha256')}) <= 1, 'Configuration changed across clips.')
    comparisons = [ev.compare(rows, {'baseline': a, 'candidate': b}) for a, b in
                   [('A', 'C'), ('B', 'C'), ('C', 'D'), ('C', 'E'), ('D', 'E')]]
    return {'schema_version': 1, 'status': 'RECORDED_EVIDENCE' if records else 'NOT_RUN',
            'evaluator_source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'evaluator_files_sha256': {p.name: ev.checksum(p) for p in (Path(__file__), QUALITY / 'evaluate.py', QUALITY / 'metrics.py')},
            'native_source_commit': index['source_commit'], 'manifest_sha256': old['manifest_sha256'],
            'reference_annotations': old['reference_annotations'], 'F': UNAVAILABLE_F,
            'configurations': {s['id']: {'specification': s, 'summary': ev.summarize(rows[s['id']], len(ids))}
                               for s in configurations()}, 'comparisons': comparisons,
            'rows': [r for group in rows.values() for r in group],
            'limitations': ['CER/WER/MER and critical expressions reuse the frozen evaluator; surface form is not semantic truth.',
                'GPT repair/introduction counts are reference-anchored lexical proxies per raw candidate and review; do not sum repeated revisions as independent clips.',
                'Decoded GPT selection, persisted fusion decision, accepted final and UI rendering are separate stages.',
                'Partial and multi-span GPT decisions retain evidence but need independently timed scope before accuracy scoring.',
                'Native configuration hash is retained as a receipt; canonical configuration hash is computed separately.',
                'No performance ranking or correctness claim follows from fluency; no cloud calls occur during scoring.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('preflight'); p.add_argument('--audio-root', type=Path, required=True)
    p.add_argument('--access-preflight', type=Path, required=True); p.add_argument('--output', type=Path, required=True)
    p = sub.add_parser('prepare'); p.add_argument('--app', required=True); p.add_argument('--outdir', type=Path, required=True)
    p = sub.add_parser('index'); p.add_argument('--run-root', type=Path, required=True)
    p.add_argument('--native-source-commit', required=True); p.add_argument('--output', type=Path, required=True)
    p = sub.add_parser('score'); p.add_argument('--index', type=Path); p.add_argument('--output', type=Path, required=True)
    p.add_argument('--summary-only', action='store_true', help='Omit rows and detailed paired comparisons; no rescoring or model calls.')
    args = parser.parse_args()
    if args.command == 'preflight':
        value = preflight(args.audio_root, args.access_preflight)
        receipt_path = args.output.with_name(args.output.stem + '-audio-integrity.json')
        write(receipt_path, value.pop('audio_integrity'))
        value['audio_integrity_receipt'] = {'file': receipt_path.name, 'sha256': ev.checksum(receipt_path)}
        write(args.output, value)
    elif args.command == 'prepare':
        value = prepare(args.outdir, args.app)
    elif args.command == 'index':
        value = index_traces(args.run_root, args.output, args.native_source_commit)
    else:
        value = score(ev.load_json(args.index) if args.index else None)
        if args.summary_only:
            value['rows_omitted'] = True
            value['stage_observations'] = {c: {
                'raw_asr_revisions': sum(len(r['raw_asr']) for r in value['rows'] if r['configuration_id'] == c),
                'gpt_reviews': sum(len(r['gpt_reviews']) for r in value['rows'] if r['configuration_id'] == c)} for c in 'ABCDE'}
            value.pop('rows'); value.pop('comparisons')
        write(args.output, value)
    print(json.dumps({'command': args.command, 'status': value.get('status', value.get('cloud_status', 'INDEXED'))}))


if __name__ == '__main__':
    main()
