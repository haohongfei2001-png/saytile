import copy
import itertools
import json
from pathlib import Path
import unittest
import tempfile

import evaluate
import metrics
import plan
import prepare

HERE = Path(__file__).resolve().parent


def sample():
    item = {'id': 'synthetic-only', 'audio_sha256': 'a' * 64, 'language': 'mixed', 'group': 'fixture',
            'sample_rate': 16000, 'frames': 32000,
            'reference': '不要 delete 10 kg', 'critical': [
                {'type': 'negation', 'text': '不要'}, {'type': 'number', 'text': '10'},
                {'type': 'unit', 'text': 'kg'}, {'type': 'term', 'text': 'delete'}]}
    trace = json.loads((HERE / 'fixtures/trace-synthetic.json').read_text())
    config = {'id': 'C_dual', 'input_mode': 'highestQuality', 'models': copy.deepcopy(trace['configuration']['models'])}
    return config, item, trace


class MetricTests(unittest.TestCase):
    def test_counts_match_inherited_alignment_exhaustively(self):
        sequences = [list(x) for n in range(4) for x in itertools.product('ab', repeat=n)]
        for reference, hypothesis in itertools.product(sequences, repeat=2):
            old = metrics.frozen.align(reference, hypothesis)
            new = metrics.alignment(reference, hypothesis)
            for key in old:
                self.assertEqual(old[key], new[key])

    def test_critical_requires_token_boundaries_and_reference_truth(self):
        cases = metrics.critical_items('blockchain 10 kg GPU', 'blockchain 100 k GPU', [
            {'type': 'term', 'text': 'AI'}, {'type': 'number', 'text': '1'},
            {'type': 'number', 'text': '10'}, {'type': 'unit', 'text': 'kg'}, {'type': 'term', 'text': 'GPU'}])
        self.assertEqual([x['status'] for x in cases[:2]], ['INVALID_REFERENCE_ANNOTATION'] * 2)
        self.assertEqual([x['matched'] for x in cases[2:]], [False, False, True])

    def test_number_negation_and_filler_not_rewritten(self):
        self.assertNotEqual(metrics.tokenize('1', 'mer'), metrics.tokenize('one', 'mer'))
        result = metrics.score_text('不不不要 delete 10 kg', '要 delete 100 kg')
        self.assertGreater(result['metrics']['mer']['deletions'], 0)
        self.assertGreater(result['metrics']['mer']['substitutions'], 0)

    def test_unit_symbols_are_not_reduced_to_unrelated_letters(self):
        result = metrics.critical_items('温度37°C，湿度50%，速度10 m/s', '温度37 C 湿度50 速度10 ms', [
            {'type': 'unit', 'text': '°C'}, {'type': 'unit', 'text': '%'}, {'type': 'unit', 'text': 'm/s'}])
        self.assertTrue(all(x['status'] == 'SCORED' for x in result))
        self.assertEqual([x['matched'] for x in result], [False, False, False])

    def test_critical_occurrence_counts_preserve_real_repeats_and_expose_extras(self):
        one = metrics.critical_items('not not', 'not', [{'type': 'negation', 'text': 'not'}])[0]
        self.assertFalse(one['matched']); self.assertEqual(one['missing_occurrences'], 1)
        extra = metrics.critical_items('not', 'not not', [{'type': 'negation', 'text': 'not'}])[0]
        self.assertTrue(extra['matched']); self.assertEqual(extra['excess_occurrences'], 1)

    def test_genuine_repetition_not_penalized_as_excess(self):
        self.assertFalse(metrics.score_text('我我想去', '我我想去')['repetition_proxy']['has_excess_adjacent_repeat'])
        result = metrics.score_text('我想去', '我我想去')
        self.assertTrue(result['repetition_proxy']['has_excess_adjacent_repeat'])
        self.assertIsNone(result['semantic_hallucination']['count'])

    def test_equal_mer_can_hide_a_repair_and_new_error(self):
        pair = metrics.paired_errors(metrics.score_text('one two', 'wrong two'), metrics.score_text('one two', 'one wrong'))
        self.assertEqual(pair['mer_error_delta'], 0)
        self.assertEqual(pair['repaired_reference_errors_or_insertions'], 1)
        self.assertEqual(pair['introduced_reference_errors_or_insertions'], 1)

    def test_deletion_replaced_by_wrong_word_is_not_repaired(self):
        pair = metrics.paired_errors(metrics.score_text('one two', 'one'), metrics.score_text('one two', 'one wrong'))
        self.assertEqual(pair['repaired_reference_errors_or_insertions'], 0)
        self.assertEqual(pair['introduced_reference_errors_or_insertions'], 0)


class TraceTests(unittest.TestCase):
    def test_generation_filter_and_persisted_not_ui_latency(self):
        config, item, trace = sample()
        row = evaluate.trace_row(config, item, trace)
        self.assertEqual(row['stages']['first_preview']['text'], '不要')
        self.assertEqual(row['latencies']['first_preview_persisted_from_replay_seconds'], .3)
        self.assertEqual(row['latencies']['final_completed_after_last_audio_submission_seconds'], .4)
        self.assertIsNone(row['latencies']['first_ui_rendered_from_replay_seconds'])
        self.assertEqual(len(row['service_runs']), 2)
        self.assertEqual(row['stages']['final']['accuracy']['metrics']['mer']['errors'], 0)

    def test_partial_has_no_fabricated_accuracy_without_timed_gold(self):
        config, item, trace = sample()
        row = evaluate.trace_row(config, item, trace)
        self.assertIsNone(row['stages']['first_preview']['accuracy'])
        self.assertIsNone(row['stages']['stable_prefix']['accuracy'])
        self.assertEqual(row['stages']['in_speech_revision']['text'], '不要 delete 10 kg')
        # A source/input frontier cannot establish the stable output's acoustic end.
        trace['fusionDecisions'][1]['framesAtDecision'] = 4800
        self.assertIsNone(evaluate.trace_row(config, item, trace)['stages']['first_preview']['accuracy'])

    def test_explicit_timed_gold_scope_allows_stage_accuracy(self):
        config, item, trace = sample()
        item['reference_timing_annotation_id'] = 'independently-aligned-fixture'
        item['reference_timed_units'] = [{'text': '不要', 'start_seconds': 0, 'end_seconds': .2},
                                        {'text': 'delete 10 kg', 'start_seconds': .3, 'end_seconds': 2}]
        trace['fusionDecisions'][1]['referenceAudioRange'] = {'startSeconds': 0, 'endSeconds': .2}
        row = evaluate.trace_row(config, item, trace)
        self.assertEqual(row['stages']['first_preview']['accuracy']['metrics']['mer']['errors'], 0)
        trace['fusionDecisions'][1]['referenceAudioRange']['endSeconds'] = .4
        self.assertIsNone(evaluate.trace_row(config, item, trace)['stages']['first_preview']['accuracy'])

    def test_provider_complete_is_not_logical_final(self):
        config, item, trace = sample()
        trace.pop('finalization')
        trace['candidates'] = [{'isComplete': True, 'text': item['reference']}]
        row = evaluate.trace_row(config, item, trace)
        self.assertEqual(row['stages']['final']['status'], 'NOT_RUN')

    def test_final_from_an_old_generation_or_user_edit_not_scored(self):
        config, item, trace = sample()
        trace['finalization']['recognitionID'] = 'generation-1'
        self.assertIsNone(evaluate.trace_row(config, item, trace)['stages']['final']['accuracy'])
        trace['finalization']['recognitionID'] = 'generation-2'
        trace['revisions'][0]['origin'] = 'userEdit'
        self.assertIsNone(evaluate.trace_row(config, item, trace)['stages']['final']['accuracy'])

    def test_audio_and_configuration_identity_fail_closed(self):
        config, item, trace = sample()
        trace['source']['audioSHA256'] = 'b' * 64
        self.assertEqual(evaluate.trace_row(config, item, trace)['status'], 'NOT_RUN')

    def test_mislabeled_baseline_and_reasoning_change_are_not_pooled(self):
        config, item, trace = sample()
        trace['configurationIdentity']['evaluationMode'] = 'single-expert-baseline'
        self.assertEqual(evaluate.trace_row(config, item, trace)['status'], 'NOT_RUN')
        config, item, trace = sample()
        config['models'][0]['reasoningEffort'] = 'high'
        trace['configuration']['models'][0]['reasoningEffort'] = 'low'
        self.assertEqual(evaluate.trace_row(config, item, trace)['status'], 'NOT_RUN')

    def test_uncertain_or_inconsistent_final_not_certified(self):
        config, item, trace = sample()
        trace['finalization']['resolved'] = False
        self.assertIsNone(evaluate.trace_row(config, item, trace)['stages']['final']['accuracy'])
        trace['finalization']['resolved'] = True
        trace['finalization']['selectedText'] = 'other text'
        self.assertIsNone(evaluate.trace_row(config, item, trace)['stages']['final']['accuracy'])

    def test_shared_provider_parameter_changes_break_single_variable_pair(self):
        config, item, trace = sample()
        left = evaluate.trace_row(config, item, trace)
        trace['configuration']['models'][0]['region'] = 'another-region'
        right = evaluate.trace_row(config, item, trace)
        result = evaluate.compare({'a': [left], 'b': [right]}, {'baseline': 'a', 'candidate': 'b'})
        self.assertEqual(result['stages']['final']['paired_clips'], 0)
        self.assertEqual(result['stages']['final']['excluded_shared_parameter_changes'], ['synthetic-only'])
        config, item, trace = sample()
        trace['configuration']['models'].pop()
        self.assertEqual(evaluate.trace_row(config, item, trace)['status'], 'NOT_RUN')

    def test_no_stable_prefix_count_only_ended_verified_sessions(self):
        config, item, trace = sample()
        trace['fusionDecisions'] = trace['fusionDecisions'][:3]
        row = evaluate.trace_row(config, item, trace)
        self.assertFalse(row['stable_formation']['formed'])
        trace['replay'].pop('sessionEndedAt')
        self.assertIsNone(evaluate.trace_row(config, item, trace)['stable_formation']['formed'])

    def test_failure_not_dropped_from_final_omissions(self):
        config, item, trace = sample()
        trace['finalization']['state'] = 'failed'
        trace['modelRuns'][1]['state'] = 'failed'
        row = evaluate.trace_row(config, item, trace)
        result = evaluate.summarize([row], 1)
        self.assertEqual(result['stages']['final']['mer']['micro_error_rate'], 1)
        self.assertEqual(result['service']['failure_rate_terminal_attempts'], .5)

    def test_missing_latency_is_null_not_zero(self):
        config, item, trace = sample()
        trace['replay'].pop('firstAudioSubmittedAt')
        row = evaluate.trace_row(config, item, trace)
        self.assertIsNone(row['latencies']['first_preview_persisted_from_audio_submission_seconds'])
        self.assertIsNone(evaluate.seconds(1, 2))

    def test_paired_different_scopes_not_compared(self):
        config, item, trace = sample()
        row = evaluate.trace_row(config, item, trace)
        other = copy.deepcopy(row)
        other['stages']['final']['reference_scope'] = {'start_seconds': 1, 'end_seconds': 2}
        result = evaluate.compare({'a': [row], 'b': [other]}, {'baseline': 'a', 'candidate': 'b'})
        self.assertEqual(result['stages']['final']['status'], 'NOT_RUN')


class CorpusTests(unittest.TestCase):
    def test_prepare_only_configs_are_disabled_and_use_isolated_cli_paths(self):
        with tempfile.TemporaryDirectory(prefix='saytile-quality-prepare-') as temporary:
            result = prepare.generate(plan.build_plan(), temporary, '/declared/public/audio', '/candidate/Saytile')
            self.assertEqual(result['configuration_count'], 11)
            self.assertEqual(len(result['commands']), 24 * 11)
            for command in result['commands']:
                self.assertFalse(command['execution_authorized'])
                self.assertIn('--data-directory', command['argv'])
            for path in (Path(temporary) / 'configurations').glob('*.json'):
                config = json.loads(path.read_text())
                self.assertFalse(config['cloudEnabled'])
                self.assertTrue(all(not model['cloudConsent'] for model in config['models']))
            single = next(x for x in result['commands'] if x['configuration_id'] == 'A_qwen_cloud')
            self.assertIn('--single-expert-baseline', single['argv'])
            path = Path(temporary) / 'configurations/A_qwen_cloud.json'
            path.write_text('modified by reviewer')
            with self.assertRaisesRegex(ValueError, 'Refusing to replace'):
                prepare.generate(plan.build_plan(), temporary, '/declared/public/audio', '/candidate/Saytile')

    def test_nested_deterministic_language_balanced_panels(self):
        result = plan.build_plan()
        self.assertEqual(result, plan.build_plan())
        for size, each in [('24', 8), ('48', 16)]:
            self.assertEqual(result['panels'][size]['language_counts'], {'zh': each, 'en': each, 'mixed': each})
        self.assertEqual(result['panels']['48']['ids'][:24], result['panels']['24']['ids'])
        self.assertEqual(len(set(result['panels']['112']['ids'])), 112)

    def test_local_qwen_cannot_be_claimed_as_hosted_qwen(self):
        result = plan.build_plan()
        config = next(x for x in result['legacy_configurations'] if 'qwen' in x['id'])
        raw = json.loads((metrics.ROOT / config['results_path']).read_text().splitlines()[0])
        item = next(x for x in evaluate.load_json(metrics.ROOT / result['manifest_path']) if x['id'] == raw['id'])
        row = evaluate.legacy_row(config, item, raw)
        self.assertEqual(row['execution'], 'legacy_local')
        self.assertEqual(row['latencies'], {})
        with self.assertRaises(ValueError):
            evaluate.legacy_row({**config, 'model': 'qwen-audio-3.1-asr-flash-message'}, item, raw)

    def test_cloud_unrun_metrics_are_null_and_legacy_results_all_accounted(self):
        result = evaluate.evaluate(plan.build_plan(), panel='24')
        self.assertEqual(len(result['rows']), 72)
        cloud = result['configurations']['A_qwen_cloud']['all']
        self.assertEqual(cloud['not_run'], 24)
        self.assertIsNone(cloud['stages']['final']['mer']['micro_error_rate'])
        self.assertIsNone(cloud['service']['failure_rate_terminal_attempts'])
        self.assertEqual(result['comparisons'][0]['stages']['final']['status'], 'NOT_RUN')

    def test_duplicate_trace_attempts_rejected(self):
        index = [{'configuration_id': 'A_qwen_cloud', 'fixture_id': 'same'}] * 2
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            evaluate.evaluate(plan.build_plan(), index)


if __name__ == '__main__':
    unittest.main()
