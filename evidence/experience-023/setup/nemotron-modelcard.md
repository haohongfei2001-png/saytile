---
license: openmdw-1.1
language:
- en
- es
- de
- fr
- it
- pt
- ru
- hi
- zh
- ja
- ko
- ar
- nl
- pl
- tr
- uk
- ro
- el
- cs
- hu
- sv
- da
- fi
- 'no'
- sk
- hr
- bg
- lt
- et
- lv
- sl
- th
- vi
- id
- ms
- bn
- ur
- fa
- ta
- te
- mr
- gu
- kn
- ml
- si
- ne
- km
- sw
- am
- ha
- zu
- yo
- ig
- af
- rw
- so
- ny
- ln
- 'or'
- he
- ku
- az
- ka
- hy
- uz
- tg
- ky
- qu
- ay
- gn
- mi
- haw
- sm
- to
- mt
tags:
- automatic-speech-recognition
- nemotron
- streaming
- conformer
- rnn-t
- multilingual
- mlx
base_model: nvidia/nemotron-3.5-asr-streaming-0.6b
library_name: mlx
pipeline_tag: automatic-speech-recognition
---

# Nemotron-3.5 ASR Streaming 0.6B — MLX INT8

Cache-aware multilingual Conformer + RNN-T speech recognition from NVIDIA,
converted to native MLX for streaming inference on Apple silicon. This bundle
uses affine group-64 8-bit linear weights, BF16 recurrent state, and
unquantized convolution, embedding, LSTM, and language-prompt layers.

## Model

| | |
|---|---|
| Parameters | 0.6B |
| Architecture | Cache-aware FastConformer + prompt-conditioned RNN-T |
| Sample rate | 16 kHz mono |
| Streaming chunk | 320 ms |
| Encoder frame rate | 80 ms |
| Attention left context | 56 frames (4.48 s) |
| Vocabulary | 13,087 SentencePiece tokens + blank |
| Quantization | MLX affine group-64 8-bit linear weights |
| On-disk size | 732.6 MB |

## Files

| File | Size | Description |
|---|---:|---|
| `model.safetensors` | 732.1 MB | MLX model weights |
| `config.json` | 1.7 KB | Strict runtime and streaming geometry |
| `vocab.json` | 100.9 KB | Ordered SentencePiece vocabulary |
| `languages.json` | 2.0 KB | Wrapped language-to-prompt-slot mapping |
| `lang2slot.json` | 1.7 KB | Flat compatibility language mapping |
| `tokenizer.model` | 397.0 KB | Original SentencePiece model |
| `speech_models_export.json` | 1.3 KB | Pinned source and export artifact hashes |
| `checksums.json` | generated | SHA-256 for every published file |

## Streaming accuracy

FLEURS test, 50 samples per language, cache-aware 320 ms streaming. English
uses Whisper's `EnglishTextNormalizer`; German, French, and Arabic use
`BasicTextNormalizer`; Hindi and Japanese use
`BasicTextNormalizer(split_letters=True)`.

| Language | WER % | CER % | RTF |
|---|---:|---:|---:|
| en-US | 8.98 | 3.96 | 0.0444 |
| de-DE | 10.59 | 5.73 | 0.0439 |
| fr-FR | 11.83 | 4.66 | 0.0451 |
| ar | 13.37 | 3.77 | 0.0481 |
| hi-IN | 4.28 | 3.50 | 0.0547 |
| ja-JP | 17.01 | 11.42 | 0.0559 |

Mean WER across these six slices is **11.01%** and mean CER is
**5.50%**.

## Streaming performance

M5 Pro with 48 GB unified memory, one fresh Python process, 63.7 seconds of
concatenated FLEURS English audio, 199 × 320 ms chunks:

| metric | value |
|---|---:|
| Real-time factor | 0.0485 |
| p50 chunk latency | 14.3 ms |
| p95 chunk latency | 16.2 ms |
| p99 chunk latency | 18.9 ms |
| RSS after lazy weight load | 196 MB |
| Peak RSS during streaming | 992 MB |

The post-load value reflects MLX's lazy memory mapping; peak RSS is the useful
resident-memory figure after inference touches the weights.

## Swift usage

The native runtime is in
[`NemotronStreamingASR`](https://github.com/soniqo/speech-swift/tree/main/Sources/NemotronStreamingASR).

```swift
import NemotronStreamingASR

let model = try await NemotronStreamingASRMLXModel.fromPretrained(
    variant: .int8
)
let session = try model.createSession(language: "en-US")

for pcm320ms in audioChunks {
    for partial in try session.pushAudio(pcm320ms) {
        print(partial.text)
    }
}

for final in try session.finalize() {
    print(final.text)
}
```

Sessions retain the mel, attention, convolution, and RNN-T predictor caches.
Model calls are serialized so multiple source-local sessions can safely share
one loaded weight set.

## Python reference runtime

The reproducible exporter, cache-aware runtime, tests, and benchmarks live in
[`speech-models/models/nemotron-asr-streaming-multilingual/export`](https://github.com/soniqo/speech-models/tree/main/models/nemotron-asr-streaming-multilingual/export).

```bash
hf download aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-MLX-8bit --local-dir ./nemotron-mlx

python streaming.py \
  --bundle ./nemotron-mlx \
  --wav recording.wav \
  --lang en-US \
  --chunk-ms 320 \
  --print-partials
```

`--print-partials` prints cumulative text whenever a chunk adds visible
tokens. Both reference runtimes remove angle-bracket language markers such as
`<en-US>` from user-facing text.

## Choosing a precision

INT5 minimizes resident memory; INT8 preserves more quantization headroom. Benchmark both on domain audio before deployment.

## Limitations

- This is ASR only. It does not perform speaker diarization or speaker
  identification.
- Language conditioning is explicit. Pass a supported BCP-47 language tag or
  use the bundle's `auto` slot.
- Partial text is provisional and may end mid-word. Applications should
  replace the previous partial until the caller finalizes the utterance.
- The native MLX path does not currently implement the Core ML runtime's
  optional word-boosting layer.
- The runtime is intended for Apple silicon and requires the MLX Metal shader
  library to be packaged with the executable.

## Provenance

| | |
|---|---|
| Upstream repository | [`nvidia/nemotron-3.5-asr-streaming-0.6b`](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b) |
| Upstream revision | `f3d333391852ba876df169dcc9ba902d25b6ab0b` |
| Upstream `.nemo` SHA-256 | `210214ed94039bf6bfbb9a047c7fa289628db75b103e2bf6381fa78285436a74` |
| Export manifest | `speech_models_export.json` |
| Artifact checksums | `checksums.json` |

## License

Distributed under
[OpenMDW 1.1](https://openmdw.ai/license/1-1/), matching the upstream NVIDIA
model. Review the upstream model card and license before deployment.

## Links

- [speech-swift](https://github.com/soniqo/speech-swift)
- [speech-models](https://github.com/soniqo/speech-models)
- [Soniqo documentation](https://soniqo.audio/guides/nemotron)
- [NVIDIA source model](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b)
