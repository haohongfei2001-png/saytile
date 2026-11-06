import copy
import itertools
import json
import hashlib
import re
from pathlib import Path
import unittest
import tempfile

import evaluate
import metrics
import plan
import prepare
import reference_annotations

HERE = Path(__file__).resolve().parent


def sample():
    item = {'id': 'synthetic-only', 'audio_sha256': 'a' * 64, 'language': 'mixed', 'group': 'fixture',
            'sample_rate': 16000, 'frames': 32000,
            'reference': '不要 delete 10 kg', 'critical': [
                {'type': 'negation', 'text': '不要'}, {'type': 'number', 'text': '10'},
                {'type': 'unit', 'text': 'kg'}, {'type': 'term', 'text': 'delete'}]}
    trace = json.loads((HERE / 'fixtures/trace-synthetic.json').read_text())
    trace['sourceRevision'] = 'c' * 40
    config = {'id': 'C_dual', 'input_mode': 'highestQuality', 'models': copy.deepcopy(trace['configuration']['models'])}
    return config, item, trace


def complete_stage():
    config, item, trace = sample()
    trace['configuration']['models'][0]['id'] = 'config-q'
    decision = trace['fusionDecisions'][-1]
    decision['proposal']['sourceCandidateIDs'] = ['complete-acoustic']
    trace['fusionDecisions'] = [decision]
    candidate = {'id': 'complete-acoustic', 'run': {
        'id': 'run-q', 'recognitionID': 'generation-2', 'recordingID': 'record', 'configurationID': 'config-q',
        'provider': 'qwenMessage', 'model': 'qwen-audio-3.1-asr-flash-message', 'purpose': 'chineseASR'},
        'isComplete': True, 'text': item['reference'], 'audioStartSeconds': 0,
        'audioEndSeconds': 2, 'createdAt': 102100}
    trace['candidates'] = [candidate]
    return config, item, trace, decision, candidate


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

    def test_reviewed_unit_forms_accept_symbols_without_rewriting_numbers_or_lexical_scores(self):
        annotations = [{'type': 'unit', 'text': text,
                        'accepted_forms': reference_annotations.REVIEWED_UNIT_FORMS[text]}
                       for text in ('percent', 'minutes')]
        result = metrics.score_text('5 percent for 10 minutes', '5% for 10 min', annotations)
        self.assertTrue(all(x['matched'] for x in result['critical']))
        self.assertGreater(result['metrics']['mer']['errors'], 0)
        for replacement in ('5 seconds for 10 meters', '5 for 10'):
            missed = metrics.critical_items('5 percent for 10 minutes', replacement, annotations)
            self.assertTrue(all(not x['matched'] for x in missed))
        number = metrics.critical_items('5 percent', 'five %', [
            {'type': 'number', 'text': '5'}, annotations[0]])
        self.assertFalse(number[0]['matched']); self.assertTrue(number[1]['matched'])

    def test_reviewed_unit_aliases_preserve_occurrence_counts(self):
        annotation = {'type': 'unit', 'text': 'percent',
                      'accepted_forms': reference_annotations.REVIEWED_UNIT_FORMS['percent']}
        complete = metrics.critical_items('5 percent and 10 percent', '5% and 10 per cent', [annotation])[0]
        self.assertTrue(complete['matched']); self.assertEqual(complete['reference_occurrences'], 2)
        self.assertEqual(complete['hypothesis_occurrences'], 2)
        omitted = metrics.critical_items('5 percent and 10 percent', '5% and 10', [annotation])[0]
        self.assertFalse(omitted['matched']); self.assertEqual(omitted['missing_occurrences'], 1)

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
    def test_post_eos_whole_candidate_scores_early_stage_without_claiming_final(self):
        config, item, trace, _, _ = complete_stage()
        trace.pop('finalization')
        row = evaluate.trace_row(config, item, trace)
        for stage in ('first_preview', 'stable_prefix'):
            self.assertEqual(row['stages'][stage]['reference_scope'], 'complete_reference')
            self.assertEqual(row['stages'][stage]['accuracy']['metrics']['mer']['errors'], 0)
            self.assertEqual(row['stages'][stage]['reference_evidence']['candidate_id'], 'complete-acoustic')
        self.assertEqual(row['stages']['final']['status'], 'NOT_RUN')
        self.assertEqual(row['stages']['in_speech_revision']['status'], 'NOT_RUN')

    def test_complete_early_hypothesis_errors_are_scored_against_whole_gold(self):
        config, item, trace, decision, candidate = complete_stage()
        candidate['text'] = '不要 delete 100 kg'
        decision['proposal']['previewText'] = candidate['text']
        decision['proposal']['stableText'] = candidate['text']
        stage = evaluate.trace_row(config, item, trace)['stages']['stable_prefix']
        self.assertEqual(stage['accuracy']['metrics']['mer']['substitutions'], 1)

    def test_whole_candidate_scope_rejects_partial_foreign_or_temporally_unavailable_evidence(self):
        mutations = {
            'partial-stage': lambda t, d, c: d['proposal'].update(stableText='不要'),
            'foreign-generation': lambda t, d, c: c['run'].update(recognitionID='generation-1'),
            'foreign-record': lambda t, d, c: c['run'].update(recordingID='other'),
            'foreign-configuration': lambda t, d, c: c['run'].update(configurationID='other'),
            'missing-configuration': lambda t, d, c: c['run'].pop('configurationID'),
            'text-fusion': lambda t, d, c: c['run'].update(purpose='textFusion'),
            'not-a-source': lambda t, d, c: d['proposal'].update(sourceCandidateIDs=['other']),
            'candidate-in-future': lambda t, d, c: c.update(createdAt=102400),
            'candidate-before-eos': lambda t, d, c: c.update(createdAt=101900),
            'incomplete': lambda t, d, c: c.update(isComplete=False),
            'short-audio': lambda t, d, c: c.update(audioEndSeconds=1.9),
            'oversized-audio': lambda t, d, c: c.update(audioEndSeconds=2.1),
            'missing-start': lambda t, d, c: c.pop('audioStartSeconds'),
            'missing-head': lambda t, d, c: c.update(audioStartSeconds=.1),
            'nan-time': lambda t, d, c: c.update(audioEndSeconds=float('nan')),
            'missing-eos': lambda t, d, c: t['replay'].pop('lastAudioSubmittedAt'),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                config, item, trace, decision, candidate = complete_stage()
                mutate(trace, decision, candidate)
                stage = evaluate.trace_row(config, item, trace)['stages']['stable_prefix']
                self.assertIsNone(stage['accuracy'])

    def test_foreign_terminal_state_never_supplies_current_failure_or_final_latency(self):
        for state in ('failed', 'cancelled', 'interrupted', 'completed'):
            with self.subTest(state=state):
                config, item, trace = sample()
                trace['finalization'].update(recognitionID='generation-1', state=state)
                row = evaluate.trace_row(config, item, trace)
                self.assertNotEqual(row['status'], 'FAILED')
                self.assertIsNone(row['stages']['final']['accuracy'])
                self.assertIsNone(row['latencies']['final_completed_from_replay_seconds'])
                self.assertIsNone(row['stable_formation']['complete_final_formed'])

    def test_missing_or_changed_source_revision_prevents_cloud_pair(self):
        config, item, trace = sample()
        left = evaluate.trace_row(config, item, trace)
        for value in (None, 'd' * 40):
            with self.subTest(revision=value):
                trace['sourceRevision'] = value
                right = evaluate.trace_row(config, item, trace)
                pair = evaluate.compare({'a': [left], 'b': [right]}, {'baseline': 'a', 'candidate': 'b'})
                self.assertEqual(pair['stages']['final']['paired_clips'], 0)
                self.assertEqual(pair['stages']['final']['excluded_source_revision'], ['synthetic-only'])
        pair = evaluate.compare({'a': [left], 'b': [left]}, {'baseline': 'a', 'candidate': 'b'})
        self.assertEqual(pair['stages']['final']['paired_clips'], 1)

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
    def test_frozen_unit_overlay_is_loaded_into_evaluation_and_cannot_change_silently(self):
        frozen_plan = plan.build_plan()
        report = evaluate.evaluate(frozen_plan, panel='24')
        receipt = report['reference_annotations']
        self.assertEqual(receipt, frozen_plan['reference_annotations'])
        self.assertEqual(receipt['annotations_added_by_type'], {'unit': 8, 'number': 34, 'negation': 26})
        self.assertEqual(receipt['reference_occurrences_added_by_type'], {'unit': 10, 'number': 36, 'negation': 28})
        self.assertEqual(receipt['annotations_added'], 68)
        self.assertEqual(receipt['reference_occurrences_added'], 74)
        legacy = report['configurations']['legacy_apple_fixed_zh']['all']
        self.assertGreater(legacy['stages']['final']['critical']['unit']['annotated'], 0)
        frozen_plan['reference_annotations']['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'overlay changed'):
            evaluate.evaluate(frozen_plan, panel='24')

    def test_reference_supplement_has_exact_occurrences_and_preserves_originals(self):
        source = metrics.ROOT / plan.MANIFEST
        original = json.loads(source.read_text())
        enriched, receipt = reference_annotations.load_references(source)
        overlay = json.loads((metrics.ROOT / reference_annotations.OVERLAY_PATH).read_text())
        self.assertEqual(receipt['reviewed_originals'], 112)
        self.assertEqual({x['id'] for x in enriched}, {x['id'] for x in original})
        for old, new in zip(original, enriched):
            self.assertEqual(old['reference'], new['reference'])
            self.assertEqual(new.get('critical', [])[:len(old.get('critical', []))], old.get('critical', []))
        by_id = {x['id']: x for x in enriched}
        for annotation in overlay['annotations']:
            with self.subTest(annotation=annotation['annotation_id']):
                text = by_id[annotation['fixture_id']]['reference']
                result = metrics.critical_items(text, text, [annotation])[0]
                self.assertEqual(result['status'], 'SCORED')
                self.assertEqual(result['reference_occurrences'], annotation['expected_reference_occurrences'])
                self.assertTrue(result['matched'])

    def test_reviewed_numbers_and_negations_catch_changed_values_and_polarity(self):
        manifest, _ = reference_annotations.load_references(metrics.ROOT / plan.MANIFEST)
        by_id = {x['id']: x for x in manifest}
        cases = [
            ('fleurs-zh-4719524538529342597', '29', '92', 'number'),
            ('fleurs-zh-9519471631565549023', '3:2', '2:3', 'number'),
            ('fleurs-en-13896470903695476292', '10–60', '10–16', 'number'),
            ('fleurs-zh-9699581877784184472', '802.11b', '802.11z', 'number'),
            ('fleurs-en-4498640649175127270', 'not', '', 'negation'),
            ('fleurs-en-3491234462595391279', "don't", 'do', 'negation'),
            ('fleurs-zh-288222503248548843', '未能', '能够', 'negation'),
        ]
        for fixture, phrase, wrong, kind in cases:
            with self.subTest(fixture=fixture, phrase=phrase):
                item = by_id[fixture]
                annotations = [x for x in item['critical'] if x['type'] == kind and x['text'] == phrase]
                self.assertEqual(len(annotations), 1)
                result = metrics.critical_items(item['reference'], item['reference'].replace(phrase, wrong), annotations)[0]
                self.assertFalse(result['matched'])
        # No post-hoc number aliases: a semantically similar spelling is still a surface miss.
        number = {'type': 'number', 'text': '29', 'accepted_forms': ['29']}
        self.assertFalse(metrics.critical_items('29', 'twenty nine', [number])[0]['matched'])

    def test_number_negation_alias_expansion_requires_new_review(self):
        path = metrics.ROOT / reference_annotations.OVERLAY_PATH
        overlay = json.loads(path.read_text())
        annotation = next(x for x in overlay['annotations'] if x['type'] == 'number')
        annotation['accepted_forms'].append('unreviewed synonym')
        with tempfile.TemporaryDirectory(prefix='saytile-reference-review-') as temporary:
            candidate = Path(temporary) / 'overlay.json'
            candidate.write_text(json.dumps(overlay))
            with self.assertRaisesRegex(ValueError, 'literal reviewed forms'):
                reference_annotations.load_references(metrics.ROOT / plan.MANIFEST, candidate)

    def test_annotation_receipts_and_denominators_reject_fabricated_coverage(self):
        path = metrics.ROOT / reference_annotations.OVERLAY_PATH
        for change in ('duplicate', 'source', 'missing-occurrence'):
            with self.subTest(change=change), tempfile.TemporaryDirectory(prefix='saytile-reference-review-') as temporary:
                overlay = json.loads(path.read_text())
                annotation = overlay['annotations'][0]
                if change == 'duplicate':
                    extra = copy.deepcopy(annotation); extra['annotation_id'] += '-duplicate'
                    overlay['annotations'].append(extra)
                elif change == 'source':
                    annotation['source_revision'] = 'wrong-revision'
                else:
                    annotation = next(x for x in overlay['annotations'] if x['expected_reference_occurrences'] > 1)
                    annotation['reference_occurrences'].pop()
                    annotation['expected_reference_occurrences'] -= 1
                candidate = Path(temporary) / 'overlay.json'; candidate.write_text(json.dumps(overlay))
                with self.assertRaises(ValueError):
                    reference_annotations.load_references(metrics.ROOT / plan.MANIFEST, candidate)

    def test_all_explicit_digit_expressions_are_covered_without_reselecting_clips(self):
        manifest, _ = reference_annotations.load_references(metrics.ROOT / plan.MANIFEST)
        for item in manifest:
            if not item.get('human_voice') or item['synthetic_perturbation']:
                continue
            text = item['reference']
            covered = [(match.start(), match.end()) for annotation in item.get('critical', [])
                       if annotation['type'] == 'number'
                       for match in re.finditer(re.escape(annotation['text']), text)]
            for match in re.finditer(r'\d+(?:[.:–-]\d+)*(?:[a-z]+)?', text):
                with self.subTest(fixture=item['id'], number=match.group()):
                    self.assertTrue(any(start <= match.start() and end >= match.end() for start, end in covered))
        result = plan.build_plan()
        # Frozen v2 order, including the unchanged nested first 24 and 48 clips.
        self.assertEqual(hashlib.sha256('\n'.join(result['panels']['112']['ids']).encode()).hexdigest(),
                         '45b2d14c07d61aa79aa012e4785a47273d92bc088a47828e4992ee87e755b91b')

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
