# English experts and precision review — 2026-11-06

## Decision and evidence limits

The provisional English streaming expert is **AssemblyAI `universal-3-6-pro`**, alongside the independently selected Chinese expert. The current Pipecat streaming table reports pooled semantic WER 0.80% and median TTFS 307 ms. This is an independent, English streaming benchmark, not proof of best Mandarin, code switching, verbatim transcription, or Saytile end-to-end performance. Its semantic scorer and speech-end-to-final latency must not be relabelled as ordinary WER or first-text latency. Soniox v5's older 1.09% result is not a v6 evaluation. Meta `muse-voice-transcribe-1.0` appears above AssemblyAI at 0.73%, but a benchmark row alone does not establish a mature, publicly accessible BYOK API; it is not selected without that evidence.

Optional completed-audio review uses **ElevenLabs `scribe_v2`**, with **OpenAI `gpt-transcribe`** as another supported independent reviewer. Neither file API's quality nor streamed HTTP output establishes live microphone quality. ElevenLabs `scribe_v2_realtime` is a separate optional streaming adapter, not an alias for Scribe v2 file transcription.

No experiment in this revision establishes that combining these models improves accuracy. Measure first displayed, evolving partial, externally committable, and completed-review output separately on the existing consented Mandarin, English and mixed examples. Preserve the existing Apple and local Qwen evidence; no model or audio was downloaded and no paid request was made for this research.

## Actual API contracts used by adapters

| Role | Model | Transport and authentication | Result handling |
|---|---|---|---|
| English streaming | `universal-3-6-pro` | `wss://streaming.assemblyai.com/v3/ws`, or explicit US/EU endpoint; raw `Authorization` key; explicit `speech_model`, `mode=max_accuracy`, `sample_rate=16000`, `encoding=pcm_s16le` | Verify `Begin.configuration.model` and `mode`; replace-by-`turn_order` `Turn`, `Termination`; words in milliseconds. Binary PCM, then `Terminate`. |
| Optional streaming | `scribe_v2_realtime` | `wss://api.elevenlabs.io/v1/speech-to-text/realtime`; `xi-api-key`; PCM16 at 16 kHz inside JSON/base64 | Partial and committed segment events; delayed committed timestamps must update their segment rather than duplicate text. No non-verbatim rewriting. |
| Completed-audio reviewer | `scribe_v2` | `POST https://api.elevenlabs.io/v1/speech-to-text`; `xi-api-key`; real multipart with file and model ID | Word timestamps in seconds; disable diarization and audio-event insertion, retain spoken disfluencies. |
| Completed-audio reviewer | `gpt-transcribe` | `POST https://api.openai.com/v1/audio/transcriptions`; Bearer key; real multipart WAV | Whole-file text; do not invent word timestamps when absent. `stream=true` is output streaming after file submission. |

Only each provider's own finalized candidate prefix is marked stable here. It is evidence for the fusion coordinator, never permission for a provider to write the official transcript or dispatch to another app. Provider failure must not affect audio journaling. Model IDs are configuration data and must be rechecked when changing services.

## Evidence-constrained AI selection and listening

The integrated text arbitrator is the currently documented **`gpt-6-astra`** through the OpenAI Responses API, with strict structured output. This is a text/image reasoning model, **not a raw-audio listener**. Standard/high reasoning is suitable for evaluating live candidate disagreements; optional pro/max reasoning is a later precision policy, not a realtime latency guarantee. The root implementation independently verifies these model IDs and API parameters.

The integrated audio reviewer is **`gemini-3.8-flash`**, whose official audio guide supports audio input, text output and high thinking. Send only the disputed original audio region plus adequate context and keep its answer as new evidence. Do not assume an unreleased “Pro” version is available. These roles are complementary; model names alone do not prove transcription gains.

An arbitrator selects actual candidate spans, leaves unresolved disagreements explicit, and requests audio review when text cannot distinguish the alternatives. No cross-vendor confidence averaging is justified without calibration. Numbers, units, negation and intentional repetition cannot be repaired from plausibility alone. Even two agreeing models may share the same error; independent audio review and eventual targeted evaluation remain necessary. Later reviews are retained without silently changing already inserted text.

## Sources (checked 2026-11-06)

- Independent streaming harness, methodology and current results: https://github.com/pipecat-ai/stt-benchmark
- AssemblyAI actual WebSocket schema: https://www.assemblyai.com/docs/streaming/api-spec/streaming-websocket
- AssemblyAI implementation guide: https://www.assemblyai.com/docs/streaming/getting-started/transcribe-streaming-audio
- AssemblyAI 3.6 Pro accuracy preset: https://www.assemblyai.com/docs/streaming/getting-started/optimizing-accuracy-and-latency
- AssemblyAI canonical message order and word finality: https://www.assemblyai.com/docs/streaming/message-sequence
- ElevenLabs streaming schema: https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime
- ElevenLabs file schema: https://elevenlabs.io/docs/api-reference/speech-to-text/convert
- OpenAI completed-file transcription: https://developers.openai.com/api/docs/guides/speech-to-text
- OpenAI live transcription (distinct interface): https://developers.openai.com/api/docs/guides/realtime-transcription
- OpenAI models: https://developers.openai.com/api/docs/models
- OpenAI structured output: https://developers.openai.com/api/docs/guides/structured-outputs
- Google audio input: https://ai.google.dev/gemini-api/docs/audio
- Soniox current model catalog: https://docs.soniox.com/stt/models
- Deepgram model catalog: https://developers.deepgram.com/docs/models-languages-overview

## Implementation checkpoint

Research checkpoint was saved before coding. `AssemblyStreamingProvider`, `ElevenLabsStreamingProvider` and `FinalASRProvider` now implement the provider-specific requests and responses, with 17 offline protocol fixtures. AssemblyAI retains/replaces numbered turns and exposes a contiguous finalized candidate prefix, including a partial turn's explicitly finalized words. A completed Pro turn also requires `turn_is_formatted`. The optional ElevenLabs realtime adapter deliberately uses manual commit at the original recording segment boundary: it displays evolving partials continuously, then handles committed text and delayed timing as one candidate. It is not selected for the fastest stable-prefix delivery.

AssemblyAI's current optimization guide explicitly supports `mode=max_accuracy` on 3.6 Pro, even though parts of the general schema still say “3.5 only.” The implementation requires the server's echoed model and accuracy mode to match. It uses documented 20–1000 ms PCM frames and waits for `Termination`, rather than disconnecting before the final turn. Prompt context is limited to the documented 1750 characters. Word tokens are aligned against the original transcript to preserve separators: token text joins exactly to the original text, while the original word's acoustic interval remains unchanged. A lexical normalization mismatch falls back to utterance timing; it never invents word times or silently drops a word.

Requests require per-model cloud consent, credentials stay in headers, and malformed timestamps are rejected. Neither adapter writes official records or dispatches externally. File review rejects incomplete PCM and oversized windows rather than truncating audio. No paid network call has been performed. Whitespace validation passed; Swift tests await the root agent's macOS build because this research container has no Swift toolchain. Cloud acceptance, billing, regional reachability and accuracy improvements remain unmeasured until an explicitly authorized BYOK run. This note does not claim those tests passed.
