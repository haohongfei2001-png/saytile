# English experts and precision review — 2026-11-06

## Decision and evidence limits

The provisional English streaming expert is **AssemblyAI `universal-3-6-pro`**, alongside the independently selected Chinese expert. The current Pipecat streaming table reports pooled semantic WER 0.80% and median TTFS 307 ms. This is an independent, English streaming benchmark, not proof of best Mandarin, code switching, verbatim transcription, or Saytile end-to-end performance. Its semantic scorer and speech-end-to-final latency must not be relabelled as ordinary WER or first-text latency. Soniox v5's older 1.09% result is not a v6 evaluation. Meta `muse-voice-transcribe-1.0` appears above AssemblyAI at 0.73%. The subsequent official API check confirmed a public BYOK streaming endpoint and an actual Pipecat adapter; excluding it as unavailable would be wrong. It is now an implemented, optional English expert and a required challenger in the next paired evaluation. The 0.07 percentage-point semantic-WER difference does not establish statistical significance or better Mandarin/code-switching input. AssemblyAI remains the provisional default, not an absolute quality winner.

The recommended highest-quality configuration includes completed-audio review using **ElevenLabs `scribe_v2`**, with **OpenAI `gpt-transcribe`** as an alternative or separately configured independent reviewer. Cloud processing starts only after keys and per-service consent are supplied. Neither file API's quality nor streamed HTTP output establishes live microphone quality. ElevenLabs `scribe_v2_realtime` is a separate streaming service, not an alias for Scribe v2 file transcription. It remains a research candidate; the incomplete realtime adapter was removed after the protocol audit below.

No experiment in this revision establishes that combining these models improves accuracy. Measure first displayed, evolving partial, externally committable, and completed-review output separately on the existing consented Mandarin, English and mixed examples. Preserve the existing Apple and local Qwen evidence; no model or audio was downloaded and no paid request was made for this research.

## Actual API contracts used by adapters

| Role | Model | Transport and authentication | Result handling |
|---|---|---|---|
| English streaming | `universal-3-6-pro` | `wss://streaming.assemblyai.com/v3/ws`, or explicit US/EU endpoint; raw `Authorization` key; explicit `speech_model`, `mode=max_accuracy`, `sample_rate=16000`, `encoding=pcm_s16le` | Verify `Begin.configuration.model` and `mode`; replace-by-`turn_order` `Turn`, `Termination`; words in milliseconds. Binary PCM, then `Terminate`. |
| Optional English challenger | `muse-voice-transcribe-1.0` | `wss://api.meta.ai/v1/asr/realtime`; credentials in first-frame `authorization.accessToken`, not HTTP headers; `PCM_16KHZ`, `ENDPOINTING`, cumulative partials | No-type session acknowledgement; lifecycle keyed by `turnId`, partial belongs to latest speech start; `endStream` then normal close and every completed turn. Processing-progress turn times only. |
| Researched; not shipped | `scribe_v2_realtime` | `wss://api.elevenlabs.io/v1/speech-to-text/realtime`; `xi-api-key`; PCM16 at 16 kHz inside JSON/base64 | Partial and committed segment events; delayed committed timestamps must update their segment rather than duplicate text. No non-verbatim rewriting. |
| Completed-audio reviewer | `scribe_v2` | `POST https://api.elevenlabs.io/v1/speech-to-text`; `xi-api-key`; real multipart with file and model ID | Word timestamps in seconds; disable diarization and audio-event insertion, retain spoken disfluencies. |
| Completed-audio reviewer | `gpt-transcribe` | `POST https://api.openai.com/v1/audio/transcriptions`; Bearer key; real multipart WAV | Whole-file text; do not invent word timestamps when absent. `stream=true` is output streaming after file submission. |

Only each provider's own finalized candidate prefix is marked stable here. It is evidence for the fusion coordinator, never permission for a provider to write the official transcript or dispatch to another app. Provider failure must not affect audio journaling. Model IDs are configuration data and must be rechecked when changing services.

## Meta Muse availability and integration

Meta's official release announced Muse Voice Transcribe on 2026-09-03, and its current docs describe key creation in the Model API dashboard, a live WebSocket endpoint, a completed-file endpoint, 25 languages including Mandarin and English, code switching, and vocabulary hints. Pipecat has a real implementation using this model and endpoint. It is an available paid/BYOK candidate, not merely a leaderboard name.

Saytile's optional adapter uses the same persisted 16 kHz PCM as the other experts, streams 20 ms frames at approximately real-time speed even during recovery, and permits both languages without forcing one. Its protocol differs materially from the other vendors: authentication is inside the first JSON frame; the acknowledgement has no event type; completed turns can arrive after a newer turn starts; only normal server close after a successful `endStream` and completion of all observed turns can finalize the session. No audio or messages follow `endStream`.

The schema explicitly describes `audioProcessedMs` as progress rather than precise acoustic boundaries. Saytile therefore records `turn-progress` evidence without fabricated word timing, confidence or language labels. Whole-candidate arbitration remains available, while word-level cross-model splicing cannot rely on those coarse times. General topic prose remains available to the fusion model; the Meta adapter does not silently reinterpret it as native keywords.

Enable Meta as an additional challenger or replace the provisional English expert through advanced configuration after supplying a key and cloud-processing consent. Promote it to the default if paired same-audio tests establish better first/evolving/stable/final output, including numbers, negation, terminology, repetitions and mixed language, without unacceptable stable-input regressions. None of those Saytile-specific cloud comparisons has yet been run.

## Evidence-constrained AI selection and listening

The integrated text arbitrator is the currently documented **`gpt-6-astra`** through the OpenAI Responses API, with strict structured output. This is a text/image reasoning model, **not a raw-audio listener**. Standard/high reasoning is suitable for evaluating live candidate disagreements; optional pro/max reasoning is a later precision policy, not a realtime latency guarantee. The root implementation independently verifies these model IDs and API parameters.

The integrated audio reviewer is **`gemini-3.8-flash`**, whose official documentation supports audio input, text output and high thinking. The current Swift adapter uses the still-supported GenerateContent API with inline WAV and structured JSON, not the distinct Interactions request format shown in newer audio guides. It currently sends the entire retained review window; automatic localization to a disputed subspan is not implemented. Keep its answer as new evidence. Do not assume an unreleased “Pro” version is available. These roles are complementary; model names alone do not prove transcription gains.

An arbitrator selects actual candidate spans, leaves unresolved disagreements explicit, and requests audio review when text cannot distinguish the alternatives. No cross-vendor confidence averaging is justified without calibration. Numbers, units, negation and intentional repetition cannot be repaired from plausibility alone. Even two agreeing models may share the same error; independent audio review and eventual targeted evaluation remain necessary. Later reviews are retained without silently changing already inserted text.

## Sources (checked 2026-11-06)

- Independent streaming harness, methodology and current results: https://github.com/pipecat-ai/stt-benchmark
- AssemblyAI actual WebSocket schema: https://www.assemblyai.com/docs/streaming/api-spec/streaming-websocket
- AssemblyAI implementation guide: https://www.assemblyai.com/docs/streaming/getting-started/transcribe-streaming-audio
- AssemblyAI 3.6 Pro accuracy preset: https://www.assemblyai.com/docs/streaming/getting-started/optimizing-accuracy-and-latency
- AssemblyAI canonical message order and word finality: https://www.assemblyai.com/docs/streaming/message-sequence
- Meta official model/API availability: https://dev.meta.ai/resources/blog/meet-muse-voice-transcribe-streaming-speech-to-text
- Meta streaming guide: https://dev.meta.ai/docs/speech-to-text
- Meta exact wire schema: https://dev.meta.ai/docs/api-reference/voice/schemas
- Meta endpoint and close codes: https://dev.meta.ai/docs/api-reference/voice/realtime
- Pipecat Meta adapter source: https://reference-server.pipecat.ai/en/latest/_modules/pipecat/services/meta/stt.html
- ElevenLabs streaming schema: https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime
- ElevenLabs commit behavior: https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies
- ElevenLabs file schema: https://elevenlabs.io/docs/api-reference/speech-to-text/convert
- OpenAI completed-file transcription: https://developers.openai.com/api/docs/guides/speech-to-text
- OpenAI live transcription (distinct interface): https://developers.openai.com/api/docs/guides/realtime-transcription
- OpenAI models: https://developers.openai.com/api/docs/models
- OpenAI structured output: https://developers.openai.com/api/docs/guides/structured-outputs
- Google audio input: https://ai.google.dev/gemini-api/docs/audio
- Google supported GenerateContent interface: https://ai.google.dev/gemini-api/docs/generate-content/get-started
- Gemini 3.8 Flash model capabilities and supported interfaces: https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-8-flash
- Soniox current model catalog: https://docs.soniox.com/stt/models
- Deepgram model catalog: https://developers.deepgram.com/docs/models-languages-overview

## Implementation checkpoint

Research checkpoint was saved before coding. `AssemblyStreamingProvider`, `MetaStreamingProvider` and `FinalASRProvider` now implement provider-specific requests and responses, with 16 English-provider and 8 Meta-provider offline protocol fixtures. AssemblyAI retains/replaces numbered turns and exposes a contiguous finalized candidate prefix, including a partial turn's explicitly finalized words. A completed Pro turn also requires `turn_is_formatted`.

**ElevenLabs realtime is not supported in this revision.** Its official commit guide documents automatic commits after approximately 36 seconds even in manual mode, while Saytile's cloud recording can remain open for 300 seconds. A segment commit cannot be treated as whole-session completion. The first adapter's single-commit assumption would reject valid longer sessions; interpreting a late automatic commit as the final manual commit would risk truncation. That adapter and its dedicated tests were removed, its persisted enum remains decode-compatible but cannot be selected or started, and Scribe v2 file review remains available. This is an adapter completeness finding, not evidence that ElevenLabs has inferior ASR quality. A future implementation needs independently verified multiple-commit association and unambiguous final-drain handling before it is offered again.

AssemblyAI's current optimization guide explicitly supports `mode=max_accuracy` on 3.6 Pro, even though parts of the general schema still say “3.5 only.” The implementation requires the server's echoed model and accuracy mode to match. It uses documented 20–1000 ms PCM frames and waits for `Termination`, rather than disconnecting before the final turn. Prompt context is limited to the documented 1750 characters. Original word text and acoustic intervals are preserved as provider evidence. An internal literal map computes partial UTF-16 stability; the fusion layer owns the shared word-to-transcript mapping, including original separators. A lexical normalization mismatch falls back to utterance timing while retaining the raw word evidence; it never invents word times or silently drops a word. HTTP 400/404/422 becomes a sanitized, non-retryable configuration error.

Requests require per-model cloud consent. Credentials use each provider's documented authorization header or Meta's first handshake frame, never a URL query or diagnostic log; malformed timestamps are rejected. Neither adapter writes official records or dispatches externally. File review rejects incomplete PCM and oversized windows rather than truncating audio. No paid network call has been performed. The initial research container had no Swift toolchain; subsequent Mac and CI validation is recorded with its source identity in [REVISION-2026-11-06.md](REVISION-2026-11-06.md). Cloud acceptance, billing, regional reachability and accuracy improvements remain unmeasured until an explicitly authorized BYOK run. This note does not claim those cloud tests passed.
