#!/usr/bin/env python3
"""Deterministic selection from the existing corpus; never downloads/runs a model."""
import argparse
import collections
import copy
import hashlib
import json
from pathlib import Path
from metrics import ROOT, critical_items
from reference_annotations import load_references

SEED = 'saytile-pr4-quality-v2-reviewed-units'
MANIFEST = 'research/asr-2026-11-06/corpus/manifest.json'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def ordered_sample(items):
    """Language-balanced nested panels; pre-annotated challenges and group first.

    No model output is read here. Counts/speaker coverage are disclosed rather
    than claiming this purposeful subset is an unbiased population estimate.
    """
    selected = []
    for language in ('zh', 'en', 'mixed'):
        pool = sorted((x for x in items if x['language'] == language),
                      key=lambda x: hashlib.sha256((SEED + x['id']).encode()).hexdigest())
        chosen = []
        for kind in ('number', 'negation', 'unit', 'term'):
            candidates = [x for x in pool if x not in chosen and any(
                e['type'] == kind and e['status'] == 'SCORED'
                for e in critical_items(x['reference'], x['reference'], x.get('critical', [])))]
            if candidates:
                chosen.append(candidates[0])
        for group in sorted({x['group'] for x in pool}):
            if not any(x['group'] == group for x in chosen):
                chosen.append(next(x for x in pool if x['group'] == group and x not in chosen))
        while len(chosen) < len(pool):
            seen = {(x['source_dataset'], x.get('speaker')) for x in chosen if x.get('speaker') is not None}
            remaining = [x for x in pool if x not in chosen]
            # Diversify existing speaker IDs when available; never invent IDs for FLEURS.
            fresh = [x for x in remaining if x.get('speaker') is not None and
                     (x['source_dataset'], x.get('speaker')) not in seen]
            chosen.append((fresh or remaining)[0])
        selected.append(chosen)
    return [x for index in range(max(map(len, selected))) for group in selected for x in group[index:index + 1]]


def build_plan():
    manifest, reference_annotations = load_references(ROOT / MANIFEST)
    items = [x for x in manifest if x.get('human_voice') and not x['synthetic_perturbation']]
    if len(items) != 112 or len({x['id'] for x in items}) != len(items):
        raise ValueError('The frozen 112-original manifest changed; review before generating a new plan.')
    # Number/negation coverage was reviewed after the v2 panels were frozen.
    # Extend scoring coverage without reselecting clips or moving checkpoints.
    selection_items = copy.deepcopy(items)
    for item in selection_items:
        item['critical'] = [x for x in item.get('critical', [])
                            if not x.get('annotation_id', '').startswith('surface-v1-')]
    by_id = {x['id']: x for x in items}
    ordered = [by_id[x['id']] for x in ordered_sample(selection_items)]
    models = {
        'Q': {'provider': 'qwenMessage', 'model': 'qwen-audio-3.1-asr-flash-message', 'purpose': 'chineseASR'},
        'A': {'provider': 'assemblyAI', 'model': 'universal-3-6-pro', 'purpose': 'englishASR', 'mode': 'max_accuracy'},
        'S': {'provider': 'soniox', 'model': 'stt-rt-v6', 'purpose': 'multilingualASR'},
        'T': {'provider': 'openAIResponses', 'model': 'gpt-6-astra', 'purpose': 'textFusion', 'reasoningEffort': 'high', 'reasoningMode': 'standard'},
        'G': {'provider': 'gemini', 'model': 'gemini-3.8-flash', 'purpose': 'audioReview'},
        'F': {'provider': 'elevenLabsFile', 'model': 'scribe_v2', 'purpose': 'finalASR'},
        'M': {'provider': 'meta', 'model': 'muse-voice-transcribe-1.0', 'purpose': 'englishASR'},
    }
    configurations = []
    for ident, description, codes in [
        ('A_qwen_cloud', 'Qwen cloud alone; never the old local Qwen result', 'Q'),
        ('B_assembly', 'AssemblyAI alone', 'A'), ('C_dual', 'Chinese + English experts', 'QA'),
        ('D_dual_soniox', 'Dual + mixed-language expert', 'QAS'),
        ('E_dual_soniox_ai', 'D + text arbitration', 'QAST'),
        ('F_dual_soniox_ai_audio', 'E + blind acoustic review', 'QASTG'),
        ('G_dual_soniox_ai_audio_file', 'F + complete-file ASR', 'QASTGF'),
        ('H_dual_ai', 'C + text arbitration, without Soniox', 'QAT'),
        ('M_meta_alone', 'Meta challenger alone', 'M'),
        ('N_qwen_meta', 'C with Meta replacing AssemblyAI', 'QM'),
        ('S_soniox_alone', 'Soniox streaming expert alone', 'S'),
    ]:
        configurations.append({'id': ident, 'description': description, 'execution': 'cloud_planned',
                               'status': 'NOT_RUN', 'input_mode': 'highestQuality',
                               'evaluation_mode': 'single-expert-baseline' if len(codes) == 1 else 'multi-expert-fusion',
                               'topicContext': '',
                               'models': [models[code] for code in codes]})
    legacy = [
        {'id': 'legacy_apple_fixed_zh', 'execution': 'legacy_local', 'engine': 'apple-speechtranscriber',
         'locale_policy': 'fixed_zh-CN', 'file': 'apple-direct-fixed-zh.jsonl'},
        {'id': 'legacy_apple_oracle_locale', 'execution': 'legacy_local', 'engine': 'apple-speechtranscriber',
         'locale_policy': 'known_reference_language_oracle_not_production_routing', 'file': 'apple-direct-oracle-locale.jsonl'},
        {'id': 'legacy_qwen_mlx_1_7b_bf16', 'execution': 'legacy_local', 'engine': 'qwen3-asr-1.7b-mlx-bf16',
         'model': 'mlx-community/Qwen3-ASR-1.7B-bf16', 'file': 'qwen-direct.jsonl'},
    ]
    receipts = json.loads((ROOT / 'research/asr/results/direct/run.json').read_text())
    for config in legacy:
        config['results_path'] = 'research/asr/results/direct/' + config.pop('file')
        config['sha256'] = receipts['runs'][Path(config['results_path']).stem]['sha256']
        if digest(ROOT / config['results_path']) != config['sha256']:
            raise ValueError('Existing result checksum differs from its receipt.')
    panels = {}
    workloads = {}
    for size in (24, 48, 112):
        sample = ordered[:size]
        panels[str(size)] = {'ids': [x['id'] for x in sample],
                            'language_counts': dict(collections.Counter(x['language'] for x in sample)),
                            'group_counts': dict(collections.Counter(x['group'] for x in sample)),
                            'valid_critical_annotations': dict(collections.Counter(e['type'] for x in sample
                                for e in critical_items(x['reference'], x['reference'], x.get('critical', []))
                                if e['status'] == 'SCORED'))}
        audio_seconds = sum(x['duration_seconds'] for x in sample)
        services = {}
        for config in configurations:
            for model in config['models']:
                key = model['provider'] + '/' + model['model']
                entry = services.setdefault(key, {'provider': model['provider'], 'model': model['model'],
                    'configuration_ids': [], 'fixture_exposures': 0, 'streaming_sessions': 0,
                    'streaming_audio_seconds': 0, 'review_fixture_exposures': 0,
                    'one_full_audio_pass_seconds_for_review_exposures': 0,
                    'dynamic_review_calls': None, 'review_input_tokens': None, 'review_output_tokens': None})
                entry['configuration_ids'].append(config['id']); entry['fixture_exposures'] += size
                if model['purpose'] in ('chineseASR', 'englishASR', 'multilingualASR'):
                    entry['streaming_sessions'] += size
                    entry['streaming_audio_seconds'] += audio_seconds
                else:
                    entry['review_fixture_exposures'] += size
                    if model['purpose'] in ('audioReview', 'finalASR'):
                        entry['one_full_audio_pass_seconds_for_review_exposures'] += audio_seconds
        workloads[str(size)] = {'clips': size, 'unique_audio_seconds': audio_seconds,
            'configuration_runs_planned': size * len(configurations), 'services': list(services.values()),
            'total_streaming_sessions': sum(x['streaming_sessions'] for x in services.values()),
            'dynamic_review_call_count': None, 'status': 'PLANNED_NOT_AUTHORIZED_OR_RUN',
            'note': 'Review/file ASR can run on multiple PCM snapshots. One full pass is a costing unit, not a call budget or total. Costs/tokens/retries remain unknown until explicit caps and service prices are supplied.'}
    return {'schema_version': 1, 'selection_seed': SEED,
            'selection_annotation_policy': 'original manifest plus unit-v1 annotations; surface-v1 number/negation additions affect scoring only, preserving frozen v2 panel IDs',
            'manifest_path': MANIFEST,
            'manifest_sha256': digest(ROOT / MANIFEST), 'reference_annotations': reference_annotations,
            'original_ids': [x['id'] for x in items],
            'fixtures': [{'id': x['id'], 'audio': x['audio'], 'audio_sha256': x['audio_sha256'],
                          'duration_seconds': x['duration_seconds'], 'language': x['language'],
                          'group': x['group']} for x in ordered],
            'panels': panels, 'planned_workloads': workloads,
            'configurations': configurations, 'legacy_configurations': legacy,
            'paired_comparisons': [
                {'baseline': a, 'candidate': b, 'change': why} for a, b, why in [
                    ('A_qwen_cloud', 'C_dual', 'add English expert'), ('B_assembly', 'C_dual', 'add Chinese expert'),
                    ('C_dual', 'D_dual_soniox', 'add Soniox'), ('D_dual_soniox', 'E_dual_soniox_ai', 'add text arbitration'),
                    ('E_dual_soniox_ai', 'F_dual_soniox_ai_audio', 'add acoustic review'),
                    ('F_dual_soniox_ai_audio', 'G_dual_soniox_ai_audio_file', 'add file ASR'),
                    ('C_dual', 'H_dual_ai', 'add text arbitration without Soniox'),
                    ('H_dual_ai', 'E_dual_soniox_ai', 'add Soniox while holding arbitration fixed'),
                    ('B_assembly', 'M_meta_alone', 'replace English provider'),
                    ('C_dual', 'N_qwen_meta', 'replace English provider in dual configuration'),
                    ('A_qwen_cloud', 'S_soniox_alone', 'replace the sole streaming provider'),
                    ('S_soniox_alone', 'D_dual_soniox', 'add both Qwen and Assembly; aggregate comparison, not a single-expert ablation'),
                    ('legacy_apple_fixed_zh', 'legacy_apple_oracle_locale', 'historical oracle-language control'),
                    ('legacy_apple_fixed_zh', 'legacy_qwen_mlx_1_7b_bf16', 'historical local engine replacement')]],
            'constraints': [
                'No audio is read, copied, uploaded or selected using model errors by this tool.',
                '24 and 48 are nested language-balanced purposeful panels, not unbiased population estimates.',
                'All 112 frozen human originals remain unchanged; append-only critical-expression labels are independently reviewed and hash-frozen; number/negation additions do not reselect frozen panels.',
                'Only reviewed percent/minute forms are equivalent for unit recall; no conversions, translations or semantic-hallucination labels are inferred.',
                'Run ordering should be counterbalanced per clip, with same PCM hash and one recorded attempt per run index.',
                'A configuration must be executed as declared; unsupported combinations remain NOT_RUN, never silently downgraded.',
                'Cloud execution, cost, credentials and per-audio processing consent are outside this offline plan.',
            ]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(build_plan(), ensure_ascii=False, indent=2) + '\n')
