#!/usr/bin/env python3
"""Offline four-stage assessment. Reads explicitly indexed results, never audio/network."""
import argparse
import collections
import hashlib
import json
import math
import re
from pathlib import Path
from metrics import ROOT, LEGACY_SCORER, score_text, paired_errors, percentile, tokenize

STAGES = ('first_preview', 'in_speech_revision', 'stable_prefix', 'final')
TERMINAL = {'completed', 'failed', 'cancelled', 'interrupted'}


def load_json(path):
    return json.loads(Path(path).read_text())


def checksum(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def parameter_fingerprint(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'),
                                     allow_nan=False).encode()).hexdigest()


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def seconds(after, before):
    if not finite(after) or not finite(before) or after < before:
        return None
    return (after - before) / 1000


def unavailable(reason):
    return {'status': 'NOT_RUN', 'text': None, 'accuracy': None, 'reason': reason,
            'at_epoch_ms': None, 'reference_scope': None}


def observation(item, text, stage, at=None, reference=None, reference_scope=None):
    result = {'status': 'OBSERVED', 'text': text, 'reference_text': reference, 'at_epoch_ms': at, 'reference_scope': reference_scope,
              'accuracy': score_text(reference, text, item.get('critical', [])) if reference is not None else None}
    if reference is None:
        result['accuracy_status'] = 'NOT_RUN_NO_TIME_ALIGNED_REFERENCE'
        # This distance deliberately is NOT a stage accuracy claim. Early output
        # normally lacks words that have not yet been spoken or confirmed.
        full = score_text(item['reference'], text)['metrics']['mer']
        result['full_reference_coverage_diagnostic'] = {
            'reference_units': full['reference_units'], 'hypothesis_units': full['hypothesis_units'],
            'deletions_including_not_yet_spoken_or_confirmed': full['deletions'],
            'error_rate': None, 'note': 'Not CER/WER/MER accuracy; no time-aligned gold scope.'}
    else:
        result['accuracy_status'] = 'SCORED'
    return result


def stage_reference(item, decision):
    """Use only complete independently time-annotated reference units within an
    explicit evaluated output interval. Input frames alone do not establish the
    linguistic scope of a partial/stable prefix and cannot fabricate its gold.
    """
    scope = decision.get('referenceAudioRange')
    units = item.get('reference_timed_units')
    if not scope or not units or not item.get('reference_timing_annotation_id'):
        return None, None
    start, end = scope.get('startSeconds'), scope.get('endSeconds')
    if not finite(start) or not finite(end) or start < 0 or end < start:
        return None, None
    chosen = [x for x in units if x['start_seconds'] >= start and x['end_seconds'] <= end]
    # Never slice a gold word/segment, or score an invented empty interval.
    overlaps = [x for x in units if x['start_seconds'] < end and x['end_seconds'] > start]
    if not chosen or len(chosen) != len(overlaps):
        return None, None
    return ' '.join(x['text'] for x in chosen), {
        'annotation_id': item['reference_timing_annotation_id'], 'start_seconds': start, 'end_seconds': end}


def legacy_row(config, item, raw):
    if raw.get('audio_sha256') != item['audio_sha256']:
        raise ValueError('Audio identity mismatch: ' + item['id'])
    if raw.get('engine') != config['engine'] or config.get('model') and raw.get('model') != config['model']:
        raise ValueError('Legacy provider/model identity mismatch; never relabel local Qwen as cloud.')
    text = raw.get('text')
    failed = bool(raw.get('error'))
    if not isinstance(text, str):
        if not failed:
            raise ValueError('A completed legacy result is missing text.')
        text = ''
    stages = {stage: unavailable('Legacy direct-file output does not measure this fused live stage.') for stage in STAGES}
    stages['final'] = observation(item, text, 'final', reference=item['reference'], reference_scope='complete_reference')
    stages['final']['is_declared_complete'] = raw.get('completely_final')
    stages['final']['source'] = 'legacy_end_of_file_output_not_multimodel_review'
    return {'fixture_id': item['id'], 'audio_sha256': item['audio_sha256'], 'configuration_id': config['id'],
            'identity': 'MATCHED_RECORDED_AUDIO_HASH', 'execution': 'legacy_local',
            'language': item['language'], 'group': item['group'], 'status': 'FAILED' if failed else 'OBSERVED',
            'stages': stages, 'stable_formation': {'status': 'NOT_RUN', 'formed': None},
            'latencies': {}, 'offline_processing_seconds': raw.get('elapsed_seconds'),
            'service_runs': [{'state': 'failed' if failed else 'completed', 'provider': config['engine'],
                              'model': raw.get('model'), 'error': raw.get('error')}],
            'notes': ['Offline file elapsed time and provider event times are not realtime/UI latency.']}


def trace_row(config, item, trace):
    """Schema-1 traces remain inspectable, but missing identity cannot be scored.
    The replay metadata must identify exactly one logical generation; old retries
    exported alongside it cannot improve the scored result or delay statistics.
    """
    row = {'fixture_id': item['id'], 'audio_sha256': item['audio_sha256'], 'configuration_id': config['id'],
           'language': item['language'], 'group': item['group'], 'execution': 'multi_trace',
           'status': 'NOT_RUN', 'identity': 'UNVERIFIED', 'stages': {s: unavailable('No verified current-generation observation.') for s in STAGES},
           'stable_formation': {'status': 'NOT_RUN', 'formed': None}, 'latencies': {}, 'service_runs': [], 'notes': []}
    source = trace.get('source') or {}
    if (source.get('audioSHA256') != item['audio_sha256'] or source.get('fixtureID') != item['id']
            or source.get('frameCount') != item['frames'] or source.get('sampleRate') != item['sample_rate']):
        row['notes'].append('Missing/mismatched embedded fixture identity; index labels alone cannot establish same audio.')
        return row
    replay = trace.get('replay') or {}
    recognition_id = replay.get('recognitionID')
    if not recognition_id or trace.get('timestampEncoding') != 'unix-epoch-milliseconds':
        row['notes'].append('Missing generation identity or unrecognized timestamp encoding.'); return row
    actual_configuration = trace.get('configuration') or {}
    identity = trace.get('configurationIdentity') or {}
    expected_mode = config.get('evaluation_mode', 'multi-expert-fusion')
    if identity.get('evaluationMode') != expected_mode or not re.fullmatch('[0-9a-f]{64}', identity.get('sha256', '')):
        row['notes'].append('Missing configuration fingerprint or mislabeled single-expert/fusion layer.'); return row
    observed_models = actual_configuration.get('models')
    expected = sorted((m['provider'], m['model'], m['purpose']) for m in config['models'])
    active_models = [m for m in observed_models or [] if m.get('enabled', True)]
    actual = sorted((m.get('provider', ''), m.get('model', ''), m.get('purpose', '')) for m in active_models)
    if expected != actual or actual_configuration.get('inputMode') != config['input_mode']:
        row['notes'].append('Missing/mismatched enabled model set or input mode; do not pool silently changed configurations.')
        return row
    if actual_configuration.get('topicContext', '') != config.get('topicContext', '') or any(m.get('context', '') for m in active_models):
        row['notes'].append('Context differs from the declared no-context control; declare a separate configuration.'); return row
    for wanted in config['models']:
        matching = next(m for m in active_models if all(m.get(k) == wanted[k] for k in ('provider', 'model', 'purpose')))
        if any(matching.get(k) != wanted[k] for k in ('reasoningEffort', 'reasoningMode') if k in wanted):
            row['notes'].append('Reasoning settings differ from the declared configuration.'); return row
    row['identity'] = 'MATCHED_EMBEDDED_AUDIO_AND_CONFIGURATION'
    row['configuration_sha256'] = identity['sha256']
    row['source_revision'] = trace.get('sourceRevision')
    row['model_parameter_fingerprints'] = {'/'.join(m[k] for k in ('provider', 'model', 'purpose')):
        parameter_fingerprint({k: v for k, v in m.items() if k not in
            ('id', 'enabled', 'cloudConsent', 'audioHourRate', 'inputMillionTokenRate', 'outputMillionTokenRate', 'currency')})
        for m in active_models}
    state = (trace.get('finalization') or {}).get('state')
    ended = finite(replay.get('sessionEndedAt'))
    row['status'] = 'FAILED' if state in ('failed', 'cancelled', 'interrupted') else 'OBSERVED'
    decisions = [x for x in trace.get('fusionDecisions', []) if x.get('recognitionID') == recognition_id]
    decisions = sorted(decisions, key=lambda x: (x.get('createdAt', math.inf), x.get('id', '')))
    previews = [x for x in decisions if x.get('proposal', {}).get('previewText')]
    stable = [x for x in decisions if x.get('outcome') == 'published' and x.get('proposal', {}).get('stableText')]
    eof = replay.get('lastAudioSubmittedAt')
    changed = []
    previous_text = None
    for decision in previews:
        text = decision['proposal']['previewText']
        if text != previous_text and previous_text is not None and finite(eof) and finite(decision.get('createdAt')) and decision['createdAt'] <= eof:
            changed.append(decision)
        previous_text = text
    for stage, decision, key in (
        ('first_preview', previews[0] if previews else None, 'previewText'),
        ('in_speech_revision', changed[-1] if changed else None, 'previewText'),
        ('stable_prefix', stable[0] if stable else None, 'stableText')):
        if decision:
            reference, scope = stage_reference(item, decision)
            row['stages'][stage] = observation(item, decision['proposal'][key], stage,
                                             decision.get('createdAt'), reference, scope)
            row['stages'][stage]['decision_id'] = decision['id']
            row['stages'][stage]['audio_submitted_seconds'] = decision.get('audioSubmittedSeconds')
            row['stages'][stage]['source'] = 'persisted_fusion_decision_not_ui_render'
    revisions = {x['id']: x for x in trace.get('revisions', [])}
    finalization = trace.get('finalization') or {}
    final_id = finalization.get('selectedRevisionID')
    final = revisions.get(final_id)
    if (finalization.get('recognitionID') == recognition_id and state == 'completed'
            and finalization.get('resolved') is True and final and final.get('origin') == 'final'
            and finalization.get('selectedText') == final['text']):
        row['stages']['final'] = observation(item, final['text'], 'final', finalization.get('completedAt'),
                                           item['reference'], 'complete_reference')
        row['stages']['final']['revision_id'] = final_id
        row['stages']['final']['dispatch_eligible'] = finalization.get('dispatchEligible')
    elif state in ('failed', 'cancelled', 'interrupted') and ended:
        row['stages']['final'] = observation(item, '', 'final', reference=item['reference'], reference_scope='complete_reference')
        row['stages']['final']['source'] = 'no_confirmed_final_service_failure_counted_as_omissions'
    else:
        row['stages']['final'] = unavailable('No generation-scoped completed final selection; provider complete/last revision alone is insufficient.')
    row['stable_formation'] = {'status': 'OBSERVED' if ended else 'NOT_RUN',
                               'formed': bool(stable) if ended else None,
                               'any_publication_observed': bool(stable),
                               'complete_final_formed': (state == 'completed' and row['stages']['final']['status'] == 'OBSERVED')
                                   if ended and state in TERMINAL else None}
    origin = replay.get('replayStartedAt')
    first_audio = replay.get('firstAudioSubmittedAt')
    first_preview = previews[0].get('createdAt') if previews else None
    first_stable = stable[0].get('createdAt') if stable else None
    completed_at = finalization.get('completedAt') if state == 'completed' else None
    row['latencies'] = {
        'first_preview_persisted_from_replay_seconds': seconds(first_preview, origin),
        'first_preview_persisted_from_audio_submission_seconds': seconds(first_preview, first_audio),
        'first_stable_published_from_replay_seconds': seconds(first_stable, origin),
        'first_stable_published_from_audio_submission_seconds': seconds(first_stable, first_audio),
        'final_completed_after_last_audio_submission_seconds': seconds(completed_at, eof),
        'final_completed_from_replay_seconds': seconds(completed_at, origin),
        'session_termination_after_last_audio_submission_seconds': seconds(replay.get('sessionEndedAt'), eof),
        'first_ui_rendered_from_replay_seconds': seconds((trace.get('timing') or {}).get('firstPreviewRenderedAt'), origin),
        'last_in_speech_revision_from_replay_seconds': seconds(changed[-1].get('createdAt') if changed else None, origin),
    }
    row['service_runs'] = [{'run_id': x['ticket']['id'], 'provider': x['ticket']['provider'],
                            'model': x['ticket']['model'], 'state': x['state'], 'error': x.get('error')}
                           for x in trace.get('modelRuns', []) if x.get('ticket', {}).get('recognitionID') == recognition_id]
    row['notes'] += ['Publication is dispatch eligibility, not an external insertion receipt.',
                     'Audio submission timestamps include leading silence; no microphone/onset latency is claimed.']
    return row


def summarize(rows, expected):
    metrics = {}
    for stage in STAGES:
        scored = [r['stages'][stage]['accuracy'] for r in rows if r['stages'][stage].get('accuracy') is not None]
        stage_report = {'observed': sum(r['stages'][stage]['status'] == 'OBSERVED' for r in rows),
                        'accuracy_scored': len(scored), 'accuracy_not_run': expected - len(scored)}
        for kind in ('cer', 'wer', 'mer'):
            n = sum(x['metrics'][kind]['reference_units'] for x in scored)
            totals = {k: sum(x['metrics'][kind][k] for x in scored) for k in ('errors', 'substitutions', 'deletions', 'insertions')}
            stage_report[kind] = {'status': 'SCORED' if scored else 'NOT_RUN', 'reference_units': n if scored else None,
                                  **{k: v if scored else None for k, v in totals.items()},
                                  'micro_error_rate': totals['errors'] / n if n else None}
        stage_report['critical'] = {}
        for kind in ('number', 'negation', 'unit', 'term'):
            entries = [e for x in scored for e in x['critical'] if e['type'] == kind and e['status'] == 'SCORED']
            stage_report['critical'][kind] = {'status': 'SCORED' if entries else 'NOT_RUN_NO_VALID_ANNOTATIONS',
                'annotated': len(entries), 'missed': sum(not e['matched'] for e in entries) if entries else None,
                'missing_occurrences': sum(e['missing_occurrences'] for e in entries) if entries else None,
                'excess_occurrences': sum(e['excess_occurrences'] for e in entries) if entries else None,
                'miss_rate': sum(not e['matched'] for e in entries) / len(entries) if entries else None}
        stage_report['excess_repeat_utterances_proxy'] = sum(x['repetition_proxy']['has_excess_adjacent_repeat'] for x in scored) if scored else None
        stage_report['semantic_hallucination_rate'] = None
        stage_report['semantic_hallucination_status'] = 'NOT_RUN_NO_INDEPENDENT_LABELS'
        metrics[stage] = stage_report
    runs = [run for row in rows for run in row['service_runs']]
    terminated = [run for run in runs if run['state'] in TERMINAL]
    formation = [r['stable_formation']['formed'] for r in rows if r['stable_formation']['status'] == 'OBSERVED']
    complete_finals = [r['stable_formation']['complete_final_formed'] for r in rows
                       if r['stable_formation'].get('complete_final_formed') is not None]
    latency_keys = sorted({k for r in rows for k in r['latencies']})
    latency = {}
    for key in latency_keys:
        values = [r['latencies'][key] for r in rows if finite(r['latencies'].get(key))]
        latency[key] = {'observed': len(values), 'missing': expected - len(values),
                        'p50': percentile(values, .5), 'p95': percentile(values, .95)}
    return {'expected_utterances': expected, 'observed_utterances': sum(r['status'] != 'NOT_RUN' for r in rows),
            'not_run': expected - sum(r['status'] != 'NOT_RUN' for r in rows), 'stages': metrics,
            'stable_formation': {'eligible_ended_traces': len(formation),
                'unable_to_form_count': sum(not x for x in formation) if formation else None,
                'unable_to_form_rate': sum(not x for x in formation) / len(formation) if formation else None,
                'complete_final_observed_sessions': len(complete_finals),
                'unable_to_form_complete_final_rate': sum(not x for x in complete_finals) / len(complete_finals) if complete_finals else None,
                'status': 'OBSERVED' if formation else 'NOT_RUN'},
            'service': {'runs_started': len(runs), 'runs_terminal': len(terminated),
                'failures': sum(r['state'] == 'failed' for r in terminated) if terminated else None,
                'failure_rate_terminal_attempts': sum(r['state'] == 'failed' for r in terminated) / len(terminated) if terminated else None,
                'cancelled_or_interrupted': sum(r['state'] in ('cancelled', 'interrupted') for r in terminated) if terminated else None,
                'note': 'Attempt denominator includes retries separately; report it alongside utterance outcomes.'},
            'latencies': latency}


def compare(rows_by_config, spec):
    before = {r['fixture_id']: r for r in rows_by_config.get(spec['baseline'], [])}
    after = {r['fixture_id']: r for r in rows_by_config.get(spec['candidate'], [])}
    result = {**spec, 'stages': {}}
    for stage in STAGES:
        pairs = []
        confounded = []
        for fixture_id in sorted(before.keys() & after.keys()):
            left, right = before[fixture_id], after[fixture_id]
            a, b = left['stages'][stage], right['stages'][stage]
            if not a.get('accuracy') or not b.get('accuracy'):
                continue
            if left['audio_sha256'] != right['audio_sha256'] or a['reference_scope'] != b['reference_scope']:
                continue
            left_settings, right_settings = left.get('model_parameter_fingerprints', {}), right.get('model_parameter_fingerprints', {})
            if any(left_settings[key] != right_settings[key] for key in left_settings.keys() & right_settings.keys()):
                confounded.append(fixture_id); continue
            pairs.append({'fixture_id': fixture_id, 'audio_sha256': left['audio_sha256'],
                          **paired_errors(a['accuracy'], b['accuracy'])})
        result['stages'][stage] = {'status': 'PAIRED' if pairs else 'NOT_RUN', 'paired_clips': len(pairs),
            'excluded_shared_parameter_changes': confounded,
            'clips_improved': sum(x['mer_error_delta'] < 0 for x in pairs) if pairs else None,
            'clips_regressed': sum(x['mer_error_delta'] > 0 for x in pairs) if pairs else None,
            'repaired_errors': sum(x['repaired_reference_errors_or_insertions'] for x in pairs) if pairs else None,
            'introduced_errors': sum(x['introduced_reference_errors_or_insertions'] for x in pairs) if pairs else None,
            'mer_error_delta': sum(x['mer_error_delta'] for x in pairs) if pairs else None, 'pairs': pairs}
    return result


def evaluate(plan, trace_index=None, panel='112', include_legacy=True):
    manifest_path = ROOT / plan['manifest_path']
    if checksum(manifest_path) != plan['manifest_sha256']:
        raise ValueError('Manifest checksum changed after sample selection.')
    manifest = {x['id']: x for x in load_json(manifest_path)}
    ids = plan['panels'][panel]['ids']
    items = [manifest[x] for x in ids]
    configurations = plan['configurations'] + (plan['legacy_configurations'] if include_legacy else [])
    rows_by_config = {c['id']: [] for c in configurations}
    index = {(x['configuration_id'], x['fixture_id']): x for x in trace_index or []}
    if len(index) != len(trace_index or []):
        raise ValueError('Duplicate trace identities; choose an explicit attempt, never silently overwrite retries.')
    if set(index) - {(c['id'], x) for c in plan['configurations'] for x in plan['original_ids']}:
        raise ValueError('Unknown configuration/fixture in trace index.')
    input_receipts = []
    for config in configurations:
        legacy = {}
        if config['execution'] == 'legacy_local':
            path = ROOT / config['results_path']
            if checksum(path) != config['sha256']:
                raise ValueError('Legacy results changed; preserve the original receipt.')
            records = [json.loads(x) for x in path.read_text().splitlines() if x.strip()]
            legacy = {x['id']: x for x in records}
            if len(legacy) != len(records):
                raise ValueError('Duplicate legacy experiment IDs.')
            if set(legacy) != set(plan['original_ids']):
                raise ValueError('Historical 112-output set differs from the fixed manifest.')
            input_receipts.append({'path': config['results_path'], 'sha256': config['sha256'], 'rows': len(records)})
        for item in items:
            if item['id'] in legacy:
                row = legacy_row(config, item, legacy[item['id']])
            elif (config['id'], item['id']) in index:
                entry = index[(config['id'], item['id'])]
                path = Path(entry['trace_path'])
                if not path.is_absolute(): path = ROOT / path
                actual_hash = checksum(path)
                if entry.get('trace_sha256') != actual_hash:
                    raise ValueError('Missing/mismatched trace receipt; freeze raw output before scoring.')
                input_receipts.append({'path': str(path), 'sha256': actual_hash})
                row = trace_row(config, item, load_json(path))
            else:
                row = {'fixture_id': item['id'], 'audio_sha256': item['audio_sha256'], 'configuration_id': config['id'],
                       'language': item['language'], 'group': item['group'], 'execution': config['execution'],
                       'identity': 'NOT_RUN', 'status': 'NOT_RUN', 'stages': {s: unavailable('No result was supplied.') for s in STAGES},
                       'stable_formation': {'status': 'NOT_RUN', 'formed': None}, 'latencies': {}, 'service_runs': []}
            rows_by_config[config['id']].append(row)
    summaries = {}
    for config in configurations:
        rows = rows_by_config[config['id']]
        if len({r['configuration_sha256'] for r in rows if r.get('configuration_sha256')}) > 1:
            raise ValueError('Configuration fingerprint changed across clips: ' + config['id'])
        summaries[config['id']] = {'configuration': config, 'all': summarize(rows, len(ids)),
            'by_language': {language: summarize([r for r in rows if r['language'] == language],
                           sum(x['language'] == language for x in items)) for language in ('zh', 'en', 'mixed')},
            'by_group': {group: summarize([r for r in rows if r['group'] == group],
                        sum(x['group'] == group for x in items)) for group in sorted({x['group'] for x in items})}}
    return {'schema_version': 1, 'panel': panel, 'normalization': 'inherited_v1_NFKC_casefold_no_lexical_rewrite',
            'normalizer_source_sha256': checksum(LEGACY_SCORER), 'manifest_sha256': plan['manifest_sha256'],
            'inputs': input_receipts, 'configurations': summaries,
            'comparisons': [compare(rows_by_config, spec) for spec in plan['paired_comparisons']],
            'rows': [r for rows in rows_by_config.values() for r in rows if r['identity'] != 'NOT_RUN'],
            'limitations': ['Legacy local Qwen3-ASR results never stand in for hosted Qwen Audio 3.1.',
                'CER and whitespace WER are reported consistently; Chinese whitespace WER is not a word-segmented Chinese benchmark.',
                'Unified MER uses Han characters and Latin/numeric tokens across all three language strata.',
                'Early-stage exact accuracy needs independently timed gold and a validated evaluated output interval.',
                'Insertion and adjacent-repeat proxies do not establish semantic hallucination.',
                'No cloud model, private data, microphone, UI rendering or external insertion is invoked by this scorer.',
                'No confidence interval, population ranking, quality win or realtime speed is inferred from absent measurements.']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--plan', type=Path, required=True); parser.add_argument('--trace-index', type=Path)
    parser.add_argument('--panel', choices=['24', '48', '112'], default='112')
    parser.add_argument('--no-legacy', action='store_true'); parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = evaluate(load_json(args.plan), load_json(args.trace_index) if args.trace_index else None,
                      args.panel, not args.no_legacy)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    print(json.dumps({k: {'observed': v['all']['observed_utterances'],
                         'final_mer': v['all']['stages']['final']['mer']['micro_error_rate']}
                      for k, v in report['configurations'].items()}, ensure_ascii=False))
