#!/usr/bin/env python3
"""Derive the fixed 32-second decoder-boundary example from the public composite."""
import argparse
import hashlib
import json
from pathlib import Path
import wave

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("composite", type=Path)
p.add_argument("output", type=Path)
a = p.parse_args()
raw_digest = hashlib.sha256(a.composite.read_bytes()).hexdigest()
if raw_digest != "5e7b5564803cec7cb90282b0427e99cd345472b758464060bf1f2ae5ba013c04":
    raise ValueError("expected the pinned continuous-public-5.wav")
with wave.open(str(a.composite), "rb") as r:
    assert (r.getsampwidth(), r.getnchannels(), r.getframerate()) == (2, 1, 16000)
    pcm = r.readframes(481280)
with a.output.open("xb") as out:
    with wave.open(out, "wb") as r:
        r.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        r.writeframes(bytes(48000) + pcm + bytes(96000))
digest = hashlib.sha256(a.output.read_bytes()).hexdigest()
if digest != "44f64214de1cdd8e71b16ce87d29376065c7f35520a8533e87f019c72defe7af":
    raise ValueError("derived PCM is not the pinned test input")
print(json.dumps(dict(id=a.output.stem, audio_sha256=digest, source_wav_sha256=raw_digest,
                      source_frames=481280, silence_before=24000, silence_after=48000)))
