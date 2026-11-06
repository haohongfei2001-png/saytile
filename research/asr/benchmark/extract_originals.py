#!/usr/bin/env python3
"""Extract the already frozen original subset, never re-select examples."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import numpy as np
import pyarrow.parquet as pq
import soundfile as sf

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--sources', required=True)
    ap.add_argument('--cache', required=True)
    ap.add_argument('--audio-root', required=True)
    ap.add_argument('--output-manifest', required=True)
    args = ap.parse_args()
    items = [x for x in json.loads(Path(args.manifest).read_text()) if not x['synthetic_perturbation']]
    sources = json.loads(Path(args.sources).read_text())
    audio = Path(args.audio_root); audio.mkdir(parents=True, exist_ok=True)
    for name, source in sources.items():
        path = Path(args.cache)/source['file']
        with path.open('rb') as f:
            if hashlib.file_digest(f, 'sha256').hexdigest() != source['archive_sha256']:
                raise ValueError('Archive hash mismatch: '+name)
        chosen = {(x['source_row_id'], x['source_audio_filename']): x for x in items if x['source_dataset']==name}
        for batch in pq.ParquetFile(path).iter_batches(batch_size=32):
            for row in batch.to_pylist():
                item = chosen.get((str(row['id']), Path(row['path']).name))
                if item is None: continue
                data, rate = sf.read(io.BytesIO(row['audio']['bytes']), dtype='float32')
                if data.ndim == 2: data = data.mean(axis=1)
                if rate != item['sample_rate']: raise ValueError('Sample rate mismatch')
                out = audio/item['audio']
                sf.write(out, data, rate, subtype='PCM_16')
                if hashlib.sha256(out.read_bytes()).hexdigest() != item['audio_sha256']:
                    raise ValueError('PCM hash mismatch: '+item['id'])
        if not all((audio/x['audio']).exists() for x in chosen.values()):
            raise ValueError('Missing source rows: '+name)
        print(json.dumps({'dataset': name, 'originals_verified':len(chosen)}), flush=True)
    out = Path(args.output_manifest); out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(items, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({'total_originals':len(items), 'manifest_sha256':hashlib.sha256(out.read_bytes()).hexdigest()}))

if __name__ == '__main__': main()
