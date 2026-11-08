"""Synthetic in-memory traces test plumbing only; never write cloud results."""
import copy
import json
import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import patch

import harness as h


def specimen():
    spec = h.configurations()[0]
    item = {'id': 'synthetic-unit-only', 'reference': '不要 delete 10 kg', 'audio_sha256': 'a' * 64,
            'frames': 32000, 'sample_rate': 16000, 'language': 'mixed', 'group': 'unit-test',
            'critical': [{'type': 'negation', 'text': '不要'}, {'type': 'number', 'text': '10'},
                         {'type': 'term', 'text': 'delete'}, {'type': 'unit', 'text': 'kg'}]}
    config = h.config_template(spec)
    # Authorization is fabricated solely inside this test, never prepared artifacts.
    config['cloudEnabled'] = True
    for model in config['models']:
        model['cloudConsent'] = True
        if model['provider'] == 'qwenMessage':
            model['workspaceID'] = 'unit-test-workspace'
    def ticket(model, ident):
        return {'id': ident, 'configurationID': model['id'], 'recognitionID': 'generation',
                'recordingID': 'recording', 'audioEpoch': 1,
                **{k: model[k] for k in ('provider', 'model', 'purpose')}}
    raw_run, gpt_run = ticket(config['models'][0], 'raw-run'), ticket(config['models'][1], 'gpt-run')
    text = '不要 delete 100 kg'  # Deliberately wrong, never the gold by construction.
    candidate = {'id': 'candidate', 'run': raw_run, 'sequence': 1, 'text': text,
                 'isComplete': True, 'audioStartSeconds': 0, 'audioEndSeconds': 2, 'createdAt': 3100}
    trace = {'schemaVersion': 2, 'sourceRevision': 'c' * 40, 'timestampEncoding': 'unix-epoch-milliseconds',
        'source': {'fixtureID': item['id'], 'audioSHA256': item['audio_sha256'], 'sampleRate': 16000, 'frameCount': 32000},
        'configuration': config,
        'configurationIdentity': {'sha256': 'b' * 64, 'evaluationMode': 'single-expert-baseline'},
        'recording': {'id': 'recording'},
        'replay': {'recognitionID': 'generation', 'replayStartedAt': 1000, 'firstAudioSubmittedAt': 1020,
                   'lastAudioSubmittedAt': 3000, 'sessionEndedAt': 3500},
        'candidates': [candidate], 'revisions': [{'id': 'final', 'origin': 'final', 'text': text}],
        'finalization': {'recognitionID': 'generation', 'state': 'completed', 'resolved': True,
                         'selectedRevisionID': 'final', 'selectedText': text, 'completedAt': 3400},
        'fusionDecisions': [{'id': 'decision', 'recognitionID': 'generation', 'createdAt': 3350,
                             'proposal': {'previewText': text, 'stableText': text}, 'outcome': 'published'}],
        'modelRuns': [{'ticket': raw_run, 'state': 'completed'}, {'ticket': gpt_run, 'state': 'completed'}],
        'modelUsage': [{'id': 'usage', 'runID': 'gpt-run', 'createdAt': 3300, 'elapsedSeconds': .15,
                        'arbitrationResponse': {'candidateIDs': ['candidate'], 'confirmedPrefix': '',
                            'decision': {'selections': [{'candidateID': 'candidate', 'utf16Start': 0,
                                                        'utf16End': len(text.encode('utf-16-le')) // 2}]}}}]}
    return spec, item, trace


def scored(trace=None):
    spec, item, default = specimen()
    trace = default if trace is None else trace
    return h.enrich(h.validate_trace(spec, item, trace, 'c' * 40, trace['configuration']), trace, item)


class PreparationTests(unittest.TestCase):
    def test_shapes_same_core_and_original_uuids(self):
        shapes = ['chineseASR', 'englishASR', 'chineseASR englishASR', 'multilingualASR',
                  'chineseASR englishASR multilingualASR']
        cores = []
        for spec, shape in zip(h.configurations(), shapes):
            template = h.config_template(spec)
            self.assertEqual([m['purpose'] for m in template['models'][:-1]], shape.split())
            self.assertEqual(sum(m['purpose'] == 'textFusion' for m in template['models']), 1)
            cores.append(template['models'][-1])
            for model in template['models']:
                suffix = {'qwenMessage': '001', 'assemblyAI': '002', 'soniox': '003', 'openAIResponses': '004'}[model['provider']]
                self.assertTrue(model['id'].endswith(suffix))
        self.assertTrue(all(x == cores[0] for x in cores))

    def test_frozen_ids_hashes_and_no_reselection(self):
        old, items, ids = h.frozen()
        self.assertEqual(ids, old['panels']['24']['ids'])
        self.assertEqual(len(ids), 24)
        self.assertEqual(h.ev.checksum(h.ROOT / old['manifest_path']), old['manifest_sha256'])
        original = {x['id']: x for x in old['fixtures']}
        for ident in ids:
            self.assertEqual(items[ident]['audio_sha256'], original[ident]['audio_sha256'])
            self.assertFalse(items[ident]['synthetic_perturbation'])

    def test_prepare_no_authorization_no_gold_no_execution(self):
        with tempfile.TemporaryDirectory(dir=h.HERE) as directory, patch.object(h.subprocess, 'check_output', side_effect=AssertionError('No invocation')):
            plan = h.prepare(directory, '${NATIVE_APP}')
            self.assertEqual(len(plan['commands']), 120)
            self.assertEqual(plan['F']['status'], 'NOT_AVAILABLE')
            for path in (Path(directory) / 'configurations').glob('*.json'):
                config = json.loads(path.read_text())
                self.assertFalse(config['cloudEnabled'])
                self.assertFalse(config['automaticRecovery'])
                self.assertTrue(all(m['cloudConsent'] is False for m in config['models']))
                self.assertNotIn('key', path.read_text().lower())
            _, items, ids = h.frozen()
            for ident in ids:
                commands = [x for x in plan['commands'] if x['fixture_id'] == ident]
                self.assertEqual(len({x['argv'][2] for x in commands}), 1)
                self.assertEqual(len({x['audio_sha256'] for x in commands}), 1)
                self.assertNotIn(items[ident]['reference'], json.dumps(commands, ensure_ascii=False))
            for command in plan['commands']:
                self.assertFalse(command['execution_authorized'])
                self.assertEqual('--single-expert-baseline' in command['argv'], command['configuration_id'] in 'ABD')

    def test_changed_preparation_not_overwritten(self):
        with tempfile.TemporaryDirectory(dir=h.HERE) as directory:
            path = Path(directory) / 'evidence.json'
            h.write(path, {'x': 1})
            with self.assertRaises(ValueError):
                h.write(path, {'x': 2})

    def test_audio_integrity_actual_pcm_and_hash(self):
        with tempfile.TemporaryDirectory(dir=h.HERE) as directory:
            path = Path(directory) / 'unit.wav'
            with wave.open(str(path), 'wb') as wav:
                wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(16000); wav.writeframes(b'\x00\x00' * 10)
            item = {'id': 'unit', 'audio': 'unit.wav', 'audio_sha256': h.ev.checksum(path), 'sample_rate': 16000, 'frames': 10}
            receipt = h.audio_receipt(Path(directory), item)
            self.assertEqual(receipt['status'], 'VERIFIED')
            self.assertEqual(receipt['pcm_sha256'], h.sha(b'\x00\x00' * 10))
            item['frames'] = 11
            self.assertEqual(h.audio_receipt(Path(directory), item)['status'], 'BLOCKED')
            item['audio'] = 'missing.wav'
            self.assertIsNone(h.audio_receipt(Path(directory), item)['pcm_sha256'])


class ScoringTests(unittest.TestCase):
    def test_not_run_is_null_not_perfect_score(self):
        report = h.score()
        self.assertEqual(len(report['rows']), 120)
        for config in report['configurations'].values():
            self.assertEqual(config['summary']['observed_utterances'], 0)
            for stage in config['summary']['stages'].values():
                self.assertEqual(stage['mer']['status'], 'NOT_RUN')
                self.assertIsNone(stage['mer']['micro_error_rate'])
                self.assertIsNone(stage['mer']['errors'])
        self.assertEqual(report['F']['status'], 'NOT_AVAILABLE')

    def test_recorded_wrong_output_not_replaced_with_gold(self):
        row = scored()
        self.assertEqual(row['stages']['final']['accuracy']['metrics']['mer']['errors'], 1)
        self.assertEqual(row['raw_asr'][0]['accuracy']['metrics']['mer']['errors'], 1)
        self.assertEqual(row['gpt_reviews'][0]['accuracy']['metrics']['mer']['errors'], 1)
        self.assertEqual(row['latencies']['final_completed_after_last_audio_submission_seconds'], .4)
        self.assertEqual(len(row['gpt_error_pairs']), 1)

    def test_partial_and_missing_gpt_response_never_use_whole_gold(self):
        _, _, trace = specimen()
        trace['candidates'][0]['isComplete'] = False
        row = scored(trace)
        self.assertIsNone(row['raw_asr'][0]['accuracy'])
        self.assertIsNone(row['gpt_reviews'][0]['accuracy'])
        trace['modelUsage'][0].pop('arbitrationResponse')
        self.assertIsNone(scored(trace)['gpt_reviews'][0]['text'])

    def test_failure_preserved_not_counted_as_observed_gpt(self):
        _, _, trace = specimen()
        trace['finalization']['state'] = 'failed'
        trace['modelRuns'][1]['state'] = 'failed'
        trace['modelUsage'] = []
        row = scored(trace)
        self.assertEqual(row['status'], 'FAILED')
        self.assertEqual(row['stages']['final']['status'], 'FAILED')
        self.assertIsNone(row['stages']['final']['accuracy'])
        self.assertEqual(row['gpt_reviews'], [])

    def test_identity_mismatches_rejected(self):
        spec, item, original = specimen()
        mutations = [lambda t: t['source'].update(audioSHA256='d' * 64),
                     lambda t: t['source'].update(fixtureID='other'),
                     lambda t: t['source'].update(frameCount=1),
                     lambda t: t.update(sourceRevision='d' * 40),
                     lambda t: t.update(synthetic=True),
                     lambda t: t['configuration']['models'][0].update(id='other'),
                     lambda t: t['configuration']['models'].append(t['configuration']['models'][-1]),
                     lambda t: t['configuration'].update(cloudEnabled=False)]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                trace = copy.deepcopy(original); mutate(trace)
                with self.assertRaises(ValueError):
                    h.validate_trace(spec, item, trace, 'c' * 40, trace['configuration'])

    def test_foreign_generation_is_not_a_raw_or_gpt_revision(self):
        _, _, trace = specimen()
        trace['candidates'][0]['run']['recognitionID'] = 'foreign'
        trace['modelRuns'][1]['ticket']['recognitionID'] = 'foreign'
        row = scored(trace)
        self.assertEqual(row['raw_asr'], [])
        self.assertEqual(row['gpt_reviews'], [])

    def test_repaired_and_introduced_errors_both_visible(self):
        spec, item, trace = specimen()
        item.update(reference='one two', critical=[])
        trace['candidates'][0]['text'] = 'bad two'
        second = copy.deepcopy(trace['candidates'][0])
        second.update(id='second', text='one bad', sequence=2, createdAt=3200)
        trace['candidates'].append(second)
        evidence = trace['modelUsage'][0]['arbitrationResponse']
        evidence['candidateIDs'] = ['candidate', 'second']
        evidence['decision']['selections'] = [{'candidateID': 'second', 'utf16Start': 0, 'utf16End': 7}]
        row = h.enrich(h.validate_trace(spec, item, trace, 'c' * 40, trace['configuration']), trace, item)
        pair = next(p for p in row['gpt_error_pairs'] if p['raw_candidate_id'] == 'candidate')
        self.assertEqual(pair['mer_error_delta'], 0)
        self.assertEqual(pair['repaired_reference_errors_or_insertions'], 1)
        self.assertEqual(pair['introduced_reference_errors_or_insertions'], 1)

    def test_pair_source_audio_and_parameters_are_checked(self):
        left = scored()
        for key, value, reason in [('audio_sha256', 'd' * 64, 'audio_mismatch'),
                                   ('source_revision', 'd' * 40, 'source_revision'),
                                   ('model_parameter_fingerprints', {k: 'drift' for k in left['model_parameter_fingerprints']}, 'shared_parameter_changes')]:
            right = copy.deepcopy(left); right[key] = value
            result = h.ev.compare_latency({'unit': left}, {'unit': right})
            self.assertEqual(result['status'], 'NOT_RUN')
            self.assertEqual(result['excluded'][reason], ['unit'])

    def test_index_generation_does_not_synthesize_missing_exports(self):
        with tempfile.TemporaryDirectory(dir=h.HERE) as directory:
            index = h.index_traces(directory, Path(directory) / 'index.json', 'c' * 40)
            self.assertEqual(index['records'], [])
            self.assertEqual(h.score(index)['status'], 'NOT_RUN')

    def test_native_export_index_scoring_and_receipt_tamper(self):
        spec, item, trace = specimen()
        old = {'manifest_sha256': 'e' * 64, 'reference_annotations': {}}
        # Replace panel only inside the test, so synthetic fixture cannot enter real 24 IDs.
        with tempfile.TemporaryDirectory(dir=h.HERE) as directory, patch.object(h, 'frozen', return_value=(old, {item['id']: item}, [item['id']])):
            path = Path(directory) / 'reports' / spec['id'] / item['id'] / 'export.json'
            h.write(path, trace)
            index = h.index_traces(directory, Path(directory) / 'index.json', 'c' * 40)
            self.assertEqual(len(index['records']), 1)
            report = h.score(index)
            self.assertEqual(report['configurations']['A']['summary']['observed_utterances'], 1)
            self.assertEqual(report['configurations']['B']['summary']['not_run'], 1)
            self.assertNotIn(directory, json.dumps(report))
            index['records'][0]['reference_sha256'] = 'wrong'
            with self.assertRaisesRegex(ValueError, 'Reference'):
                h.score(index)
            index['records'][0]['reference_sha256'] = h.reference_hash(item)
            path.write_text(json.dumps(dict(trace, sourceRevision='d' * 40)))
            with self.assertRaisesRegex(ValueError, 'receipt'):
                h.score(index)

    def test_multiple_exports_are_not_best_of_selected(self):
        _, _, ids = h.frozen()
        with tempfile.TemporaryDirectory(dir=h.HERE) as directory:
            path = Path(directory) / 'reports' / 'A' / ids[0]
            h.write(path / 'attempt1.json', {})
            h.write(path / 'attempt2.json', {})
            with self.assertRaisesRegex(ValueError, 'Multiple attempts'):
                h.index_traces(directory, Path(directory) / 'index.json', 'c' * 40)

    def test_exact_snapshot_mismatch_and_missing_latency(self):
        spec, item, trace = specimen()
        altered = copy.deepcopy(trace['configuration'])
        altered['models'][0]['workspaceID'] = 'changed'
        with self.assertRaisesRegex(ValueError, 'Exact recorded'):
            h.validate_trace(spec, item, trace, 'c' * 40, altered)
        trace['finalization'].pop('completedAt')
        self.assertIsNone(scored(trace)['latencies']['final_completed_after_last_audio_submission_seconds'])

    def test_configuration_drift_across_clips_rejected(self):
        spec, item, trace = specimen()
        second = dict(item, id='second-synthetic-unit-only')
        other = copy.deepcopy(trace)
        other['source']['fixtureID'] = second['id']
        other['configuration']['models'][0]['workspaceID'] = 'another-unit-workspace'
        old = {'manifest_sha256': 'e' * 64, 'reference_annotations': {}}
        with tempfile.TemporaryDirectory(dir=h.HERE) as directory, patch.object(h, 'frozen', return_value=(old, {item['id']: item, second['id']: second}, [item['id'], second['id']])):
            for fixture, export in ((item, trace), (second, other)):
                h.write(Path(directory) / 'reports' / spec['id'] / fixture['id'] / 'export.json', export)
            index = h.index_traces(directory, Path(directory) / 'index.json', 'c' * 40)
            with self.assertRaisesRegex(ValueError, 'changed across clips'):
                h.score(index)

    def test_duplicate_event_and_gold_provenance_rejected(self):
        spec, item, trace = specimen()
        trace['candidates'].append(copy.deepcopy(trace['candidates'][0]))
        with self.assertRaisesRegex(ValueError, 'Duplicate trace'):
            h.validate_trace(spec, item, trace, 'c' * 40, trace['configuration'])
        trace['candidates'].pop()
        trace['provenance'] = 'gold'
        with self.assertRaisesRegex(ValueError, 'Not native'):
            h.validate_trace(spec, item, trace, 'c' * 40, trace['configuration'])

    def test_duplicate_unknown_or_synthetic_index_rejected(self):
        _, _, ids = h.frozen()
        record = {'configuration_id': 'A', 'fixture_id': ids[0], 'provenance': 'synthetic'}
        for records in ([record], [record, record], [dict(record, fixture_id='synthetic-unit-only')]):
            with self.assertRaises(ValueError):
                h.score({'records': records, 'source_commit': 'c' * 40})


if __name__ == '__main__':
    unittest.main()
