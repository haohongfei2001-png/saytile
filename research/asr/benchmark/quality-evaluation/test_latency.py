import unittest
import evaluate


def row(ident, value, language='zh'):
    return {'fixture_id': ident, 'audio_sha256': ident * 64, 'source_revision': 'c' * 40,
            'execution': 'multi_trace', 'identity': 'MATCHED_EMBEDDED_AUDIO_AND_CONFIGURATION',
            'language': language, 'model_parameter_fingerprints': {'shared': 'same'},
            'latencies': {'first_stable_published_from_replay_seconds': value}}


class PairedLatencyTests(unittest.TestCase):
    def test_pair_first_then_quantile_not_difference_of_aggregate_medians(self):
        before = {key: row(key, value) for key, value in zip('abc', [1, 2, 100])}
        after = {key: row(key, value) for key, value in zip('abc', [2, 100, 101])}
        report = evaluate.compare_latency(before, after)
        metric = report['all']['metrics']['first_stable_published_from_replay_seconds']
        self.assertEqual(metric['paired_clips'], 3)
        self.assertEqual(metric['delta_p50_seconds'], 1)
        self.assertEqual([x['added_seconds'] for x in metric['pairs']], [1, 98, 1])
        self.assertEqual(report['by_language']['zh'], report['all'])
        self.assertEqual(report['by_language']['en']['eligible_clips'], 0)

    def test_missing_latency_is_not_zero_and_does_not_need_timed_accuracy(self):
        report = evaluate.compare_latency({'a': row('a', None), 'b': row('b', 3)},
                                          {'a': row('a', 1), 'b': row('b', 2)})
        metric = report['all']['metrics']['first_stable_published_from_replay_seconds']
        self.assertEqual(metric['missing_event_clips'], ['a'])
        self.assertEqual(metric['delta_p50_seconds'], -1)
        self.assertEqual(metric['paired_clips'], 1)
        empty = evaluate.compare_latency({'a': row('a', None)}, {'a': row('a', None)})
        self.assertEqual(empty['status'], 'NOT_RUN')
        self.assertIsNone(empty['all']['metrics']['first_stable_published_from_replay_seconds']['delta_p50_seconds'])

    def test_source_audio_parameters_and_unverified_or_missing_traces_excluded(self):
        changes = [('source_revision', {'source_revision': None}),
                   ('source_revision', {'source_revision': 'd' * 40}),
                   ('audio_mismatch', {'audio_sha256': 'different'}),
                   ('shared_parameter_changes', {'model_parameter_fingerprints': {'shared': 'changed'}}),
                   ('unverified_trace', {'identity': 'UNVERIFIED'}),
                   ('unverified_trace', {'execution': 'legacy_local'})]
        for reason, change in changes:
            with self.subTest(reason=reason, change=change):
                candidate = row('a', 1); candidate.update(change)
                report = evaluate.compare_latency({'a': row('a', 2)}, {'a': candidate})
                self.assertEqual(report['excluded'][reason], ['a'])
                self.assertEqual(report['status'], 'NOT_RUN')
        missing = evaluate.compare_latency({'a': row('a', 1)}, {})
        self.assertEqual(missing['excluded']['missing_trace'], ['a'])

    def test_nonfinite_and_absent_events_stay_unmeasured(self):
        candidate = row('a', float('nan')); candidate['latencies']['final_seconds'] = 4
        report = evaluate.compare_latency({'a': row('a', 1)}, {'a': candidate})
        for metric in report['all']['metrics'].values():
            self.assertEqual(metric['status'], 'NOT_RUN')
            self.assertEqual(metric['missing_event_clips'], ['a'])
            self.assertIsNone(metric['delta_p50_seconds'])
        self.assertEqual(evaluate.compare_latency({}, {})['status'], 'NOT_RUN')
