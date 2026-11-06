"""Append independently reviewed reference annotations without changing the source."""
import copy
import collections
import hashlib
import json
from pathlib import Path
from metrics import critical_items

ROOT = Path(__file__).resolve().parents[4]
OVERLAY_PATH = 'research/asr/benchmark/quality-evaluation/unit-annotations.json'
# Frozen from reference unit spellings before rescoring any hypotheses. These
# affect this small offline recall metric only, never production ASR evidence.
REVIEWED_UNIT_FORMS = {
    '年': ['年'], '岁': ['岁'], '英里': ['英里'], '分钟': ['分钟'], '月': ['月'],
    'minutes': ['minutes', 'minute', 'min', 'mins'],
    'percent': ['percent', 'per cent', '%'],
}


def digest_bytes(data):
    return hashlib.sha256(data).hexdigest()


def load_references(manifest_path, overlay_path=None, expected_overlay_sha256=None):
    manifest_path = Path(manifest_path)
    overlay_path = Path(overlay_path) if overlay_path else ROOT / OVERLAY_PATH
    original = manifest_path.read_bytes()
    overlay_bytes = overlay_path.read_bytes()
    overlay = json.loads(overlay_bytes)
    checksum = digest_bytes(overlay_bytes)
    if expected_overlay_sha256 is not None and checksum != expected_overlay_sha256:
        raise ValueError('Reference annotation overlay changed after the plan was frozen.')
    if overlay.get('manifest_sha256') != digest_bytes(original):
        raise ValueError('Annotation overlay does not belong to this frozen manifest.')
    manifest = json.loads(original)
    items = {x['id']: x for x in manifest}
    originals = {x['id'] for x in manifest if x.get('human_voice') and not x['synthetic_perturbation']}
    if set(overlay['reviewed_original_ids']) != originals or len(overlay['reviewed_original_ids']) != len(originals):
        raise ValueError('Reference review coverage is incomplete or duplicated.')
    seen = set()
    for annotation in overlay['annotations']:
        ident, fixture_id = annotation['annotation_id'], annotation['fixture_id']
        if ident in seen or fixture_id not in originals:
            raise ValueError('Duplicate annotation or non-original fixture in overlay.')
        seen.add(ident)
        item = items[fixture_id]
        text = item['reference']
        if digest_bytes(text.encode()) != annotation['reference_sha256']:
            raise ValueError('Annotated reference text has changed.')
        if annotation.get('reference') != text or any(annotation.get(key) != item.get(key)
                for key in ('source_dataset', 'source_revision', 'license')):
            raise ValueError('Annotation source receipt differs from the frozen reference.')
        if any(x.get('type') == annotation['type'] and x.get('text') == annotation['text']
               for x in item.get('critical', [])):
            raise ValueError('Duplicate existing type/text annotation would inflate the denominator.')
        spans = annotation['reference_occurrences']
        if len(spans) != annotation['expected_reference_occurrences'] or not spans:
            raise ValueError('Invalid reference occurrence count.')
        seen_spans = set()
        for span in spans:
            start, end = span['start'], span['end']
            if (not isinstance(start, int) or not isinstance(end, int) or start < 0 or end <= start
                    or text[start:end] != annotation['text'] or (start, end) in seen_spans):
                raise ValueError('Critical annotation is not an exact reference span.')
            seen_spans.add((start, end))
        kind = annotation['type']
        if kind == 'unit':
            if annotation['accepted_forms'] != REVIEWED_UNIT_FORMS.get(annotation['text']):
                raise ValueError('Unit aliases differ from the fixed reviewed standard-unit forms.')
        elif kind in ('number', 'negation'):
            if annotation['accepted_forms'] != [annotation['text']]:
                raise ValueError('Number/negation annotations must preserve literal reviewed forms.')
        else:
            raise ValueError('Unsupported reviewed reference annotation type.')
        measured = critical_items(text, text, [annotation])[0]
        if measured['reference_occurrences'] != annotation['expected_reference_occurrences']:
            raise ValueError('Reviewed occurrence count differs from the token-boundary reference count.')
        item.setdefault('critical', []).append({key: copy.deepcopy(annotation[key])
            for key in ('annotation_id', 'type', 'text', 'accepted_forms')})
    return manifest, {'path': str(overlay_path.relative_to(ROOT)) if overlay_path.is_relative_to(ROOT) else str(overlay_path),
                      'sha256': checksum, 'overlay_id': overlay['overlay_id'],
                      'reviewed_originals': len(originals), 'annotations_added': len(seen),
                      'annotations_added_by_type': dict(collections.Counter(x['type'] for x in overlay['annotations'])),
                      'reference_occurrences_added_by_type': {kind: sum(x['expected_reference_occurrences']
                          for x in overlay['annotations'] if x['type'] == kind)
                          for kind in sorted({x['type'] for x in overlay['annotations']})},
                      'reference_occurrences_added': sum(x['expected_reference_occurrences'] for x in overlay['annotations'])}
