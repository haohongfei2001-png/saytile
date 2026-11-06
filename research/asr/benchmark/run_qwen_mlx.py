#!/usr/bin/env python3
"""Bounded, resumable local Qwen ASR evaluation. Never opens a microphone.

Token streaming over an already-complete file is NOT real-time audio recognition.
All timing in this runner is explicitly offline processing time.
"""
import argparse
import hashlib
import importlib.metadata
import json
import os
import platform
import time
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--audio-root', required=True)
    ap.add_argument('--model-dir', required=True)
    ap.add_argument('--output', required=True)
    ap.add_argument('--limit', type=int)
    ap.add_argument('--max-audio-seconds', type=float, default=3600)
    args = ap.parse_args()
    raw = Path(args.manifest).read_text()
    items = json.loads(raw) if raw.lstrip().startswith('[') else [json.loads(s) for s in raw.splitlines() if s.strip()]
    if args.limit:
        items = items[:args.limit]
    if sum(x['duration_seconds'] for x in items) > args.max_audio_seconds:
        raise SystemExit('Audio budget exceeded; change budget explicitly before running')
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    done = set()
    if out.exists():
        for s in out.read_text().splitlines():
            r = json.loads(s)
            done.add((r['id'], r['audio_sha256']))
    model_dir = Path(args.model_dir)
    metadata = model_dir / '.cache/huggingface/download/model.safetensors.metadata'
    revision = metadata.read_text().splitlines()[0] if metadata.exists() else None
    weight_digest = hashlib.sha256((model_dir/'model.safetensors').read_bytes()).hexdigest()
    from mlx_audio.stt.utils import load_model
    import mlx.core as mx
    started = time.monotonic()
    model = load_model(str(model_dir))
    load_seconds = time.monotonic() - started
    for i, item in enumerate(items):
        if (item['id'], item['audio_sha256']) in done:
            continue
        path = Path(args.audio_root)/item['audio']
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != item['audio_sha256']:
            raise SystemExit('Audio hash mismatch: '+item['id'])
        started = time.monotonic()
        text = ''
        error = None
        info = {}
        max_tokens = min(2048, max(128, int(item['duration_seconds']*12+64)))
        try:
            result = model.generate(str(path), language=None, temperature=0.0,
                                    max_tokens=max_tokens, verbose=False, stream=False)
            text = result.text
            for name in ('language', 'total_tokens', 'prompt_tokens', 'generation_tokens', 'prompt_tps', 'generation_tps', 'total_time'):
                value = getattr(result, name, None)
                if isinstance(value, (str, int, float, bool)) or value is None:
                    info[name] = value
        except Exception as exc:
            error = type(exc).__name__+': '+str(exc)
        row = {
            'id': item['id'], 'audio_sha256': digest, 'text': text, 'error': error,
            'engine': 'qwen3-asr-1.7b-mlx-bf16',
            'model': 'mlx-community/Qwen3-ASR-1.7B-bf16', 'model_revision': revision,
            'weights_sha256': weight_digest, 'mlx_audio_version': importlib.metadata.version('mlx-audio'),
            'mlx_version': importlib.metadata.version('mlx'),
            'configuration': {'language': 'auto', 'temperature': 0, 'max_tokens': max_tokens,
                              'vad': False, 'hotwords': None, 'system_prompt': None},
            'elapsed_seconds': time.monotonic()-started, 'model_load_seconds': load_seconds,
            'latency_class': 'offline_file_processing_not_realtime',
            'first_readable_seconds': None, 'stable_after_input_seconds': None,
            'platform': platform.platform(), 'generation': info,
        }
        with out.open('a') as f:
            f.write(json.dumps(row, ensure_ascii=False)+'\n')
            f.flush()
            os.fsync(f.fileno())
        print(json.dumps({'index': i+1, 'id': item['id'], 'seconds': round(row['elapsed_seconds'], 3), 'error': error}), flush=True)
        mx.clear_cache()


if __name__ == '__main__':
    main()
