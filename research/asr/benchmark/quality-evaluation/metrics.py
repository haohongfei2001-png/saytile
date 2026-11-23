"""Frozen lexical metrics and reference-anchored paired differences; stdlib only."""
import collections
import importlib.util
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
LEGACY_SCORER = ROOT / 'research/asr-2026-11-06/scripts/score.py'
spec = importlib.util.spec_from_file_location('saytile_frozen_score', LEGACY_SCORER)
frozen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(frozen)
normalize, tokenize, percentile = frozen.normalize, frozen.tokenize, frozen.percentile


def alignment(reference, hypothesis):
    """Deterministic Levenshtein, with error locations in the same reference.

    Ties prefer diagonal, deletion, insertion, as the inherited scorer does.
    Insertions are anchored to a reference gap and token; this is a lexical
    alignment proxy, not evidence that a model hallucinated a semantic claim.
    """
    n, m = len(reference), len(hypothesis)
    back = [bytearray([2] * (m + 1))]
    previous = list(range(m + 1))
    for i, expected in enumerate(reference, 1):
        current, choices = [i], bytearray(m + 1)
        choices[0] = 1
        for j, actual in enumerate(hypothesis, 1):
            costs = (previous[j - 1] + (expected != actual), previous[j] + 1, current[j - 1] + 1)
            best = min(range(3), key=costs.__getitem__)
            current.append(costs[best]); choices[j] = best
        previous = current; back.append(choices)
    i, j = n, m
    errors = []
    counts = collections.Counter()
    while i or j:
        choice = back[i][j]
        if i and j and choice == 0:
            i -= 1; j -= 1
            if reference[i] != hypothesis[j]:
                counts['substitutions'] += 1
                errors.append({'kind': 'substitution', 'reference_index': i,
                               'reference': reference[i], 'hypothesis': hypothesis[j]})
        elif i and (not j or choice == 1):
            i -= 1; counts['deletions'] += 1
            errors.append({'kind': 'deletion', 'reference_index': i, 'reference': reference[i]})
        else:
            j -= 1; counts['insertions'] += 1
            errors.append({'kind': 'insertion', 'reference_gap': i, 'hypothesis': hypothesis[j]})
    errors.reverse()
    total = sum(counts.values())
    return {'errors': total, 'substitutions': counts['substitutions'],
            'deletions': counts['deletions'], 'insertions': counts['insertions'],
            'reference_units': n, 'hypothesis_units': m,
            'error_rate': total / n if n else None, 'error_locations': errors}


def contains(sequence, subsequence):
    return bool(subsequence) and any(sequence[i:i + len(subsequence)] == subsequence
                                     for i in range(len(sequence) - len(subsequence) + 1))


def critical_tokens(text):
    """Keep unit symbols as their own tokens (37°C is not just the letter C).
    Punctuation outside literal numeric formats is ignored, but no values,
    negations, aliases or unit conversions are inferred.
    """
    value = unicodedata.normalize('NFKC', text).casefold()
    tokens = re.findall(r"[-+−]?\d+(?:[.,:/]\d+)*|[\u3400-\u4dbf\u4e00-\u9fff]|[a-z0-9]+(?:[’'][a-z0-9]+)*|[^\W\s]|[^\w\s]", value)
    return [x for x in tokens if len(x) > 1 or unicodedata.category(x)[0] not in 'PS'
            or unicodedata.category(x)[0] == 'S' or x in ('%', '°', '/', '·', '′', '″')]


def critical_items(reference, hypothesis, annotations):
    """Only pre-existing annotations with a token-exact gold occurrence count.

    No semantic number conversion, synonym matching or post-hoc alias expansion.
    AI is not present in the word blockchain; 1 is not present in 10.
    """
    expected, actual = critical_tokens(reference), critical_tokens(hypothesis)
    result = []
    def occurrences(tokens, aliases):
        spans = {(i, i + len(alias)) for alias in aliases if alias
                 for i in range(len(tokens) - len(alias) + 1) if tokens[i:i + len(alias)] == alias}
        end = -1; count = 0
        for start, stop in sorted(spans, key=lambda x: (x[0], -x[1])):
            if start >= end:
                count += 1; end = stop
        return count
    for index, annotation in enumerate(annotations):
        forms = annotation.get('accepted_forms') or [annotation['text']]
        sequences = [critical_tokens(value) for value in forms]
        valid = any(contains(expected, tokens) for tokens in sequences)
        reference_count = occurrences(expected, sequences)
        hypothesis_count = occurrences(actual, sequences)
        result.append({'annotation_index': index, 'type': annotation.get('type', 'unknown'),
                       'text': annotation['text'], 'accepted_forms': forms,
                       'status': 'SCORED' if valid else 'INVALID_REFERENCE_ANNOTATION',
                       'matched': hypothesis_count >= reference_count if valid else None,
                       'reference_occurrences': reference_count if valid else None,
                       'hypothesis_occurrences': hypothesis_count if valid else None,
                       'missing_occurrences': max(0, reference_count - hypothesis_count) if valid else None,
                       'excess_occurrences': max(0, hypothesis_count - reference_count) if valid else None})
    return result


def repetition_proxy(reference, hypothesis):
    """Excess repeated adjacent 1..4-grams, with genuine reference repeats retained."""
    def repetitions(tokens, size):
        return collections.Counter(tuple(tokens[i:i + size]) for i in range(len(tokens) - 2 * size + 1)
                                   if tokens[i:i + size] == tokens[i + size:i + 2 * size])
    found = []
    for size in range(1, 5):
        extra = repetitions(hypothesis, size) - repetitions(reference, size)
        found.extend({'tokens': list(tokens), 'excess_adjacent_occurrences': count}
                     for tokens, count in sorted(extra.items()))
    return {'status': 'LEXICAL_PROXY', 'has_excess_adjacent_repeat': bool(found), 'patterns': found,
            'note': 'Overlapping lengths are not summed as independent errors; this is not a semantic verdict.'}


def score_text(reference, hypothesis, annotations=()):
    scores = {kind: alignment(tokenize(reference, kind), tokenize(hypothesis, kind))
              for kind in ('cer', 'wer', 'mer')}
    for kind in ('cer', 'wer'):
        scores[kind].pop('error_locations')
    mer = scores['mer']
    return {'metrics': scores, 'critical': critical_items(reference, hypothesis, annotations),
            'omitted_reference_tokens': mer['deletions'],
            'inserted_tokens_proxy': mer['insertions'],
            'repetition_proxy': repetition_proxy(tokenize(reference, 'mer'), tokenize(hypothesis, 'mer')),
            'semantic_hallucination': {'status': 'NOT_RUN', 'count': None,
                                       'reason': 'No independently reviewed semantic labels are available.'}}


def paired_errors(baseline, candidate):
    def signatures(score):
        values = collections.Counter()
        for error in score['metrics']['mer']['error_locations']:
            if error['kind'] == 'insertion':
                key = ('gap', error['reference_gap'], error['hypothesis'])
            else:
                # Changing a deletion into a wrong substitution is not a repair.
                key = ('reference', error['reference_index'])
            values[key] += 1
        return values
    before, after = signatures(baseline), signatures(candidate)
    repaired, introduced = before - after, after - before
    old = {x['annotation_index']: x for x in baseline['critical'] if x['status'] == 'SCORED'}
    new = {x['annotation_index']: x for x in candidate['critical'] if x['status'] == 'SCORED'}
    return {'repaired_reference_errors_or_insertions': sum(repaired.values()),
            'introduced_reference_errors_or_insertions': sum(introduced.values()),
            'repairs': [{'location': list(k), 'count': v} for k, v in sorted(repaired.items())],
            'introductions': [{'location': list(k), 'count': v} for k, v in sorted(introduced.items())],
            'critical_repaired': [i for i in sorted(old.keys() & new.keys()) if not old[i]['matched'] and new[i]['matched']],
            'critical_introduced': [i for i in sorted(old.keys() & new.keys()) if old[i]['matched'] and not new[i]['matched']],
            'mer_error_delta': candidate['metrics']['mer']['errors'] - baseline['metrics']['mer']['errors']}
