# Equal ASR protocol audit — no API keys

Base: PR #6, `3cd8ebcbc94e7536ea8d4ccfd4474b72e9fd2b46`. Reviewed 2026-11-07 against current primary provider documentation. This is protocol engineering evidence, not cloud authentication, recognition quality or provider availability evidence. No microphone, production database, real credential or paid API was used.

## Official contracts used

- [Qwen Message WebSocket](https://help.aliyun.com/en/model-studio/qwen-asr-message-websocket-api): workspace-specific Beijing/Singapore WSS endpoint, regional API key, Bearer authorization. `qwen-audio-3.1-asr-flash-message` is explicitly requested. Both language hints remain permissive; both experts receive all PCM.
- [Qwen client events](https://help.aliyun.com/en/model-studio/qwen-asr-message-client-events): 16 kHz mono signed 16-bit PCM; start task then binary audio then finish-task. Explicit intermediate results; no automatic disfluency removal. Context limit is 400 characters per turn. [Python SDK](https://help.aliyun.com/en/model-studio/qwen-asr-message-python-sdk) recommends approximately 100 ms packets and 1–16 KB packet sizes; these recommendations are not treated as a reason to invent or pad speech.
- [Qwen server events](https://help.aliyun.com/en/model-studio/qwen-asr-message-server-events): send PCM only after matching task-started. Partial revisions replace a sentence ID, ordinary sentence IDs start at 1, heartbeat ID 0 is ignored. Finish-task must be followed by final results and task-finished; a failed task is not reusable. A sentence-start may be empty. Real timestamp evidence is preserved; absent word alignment is not manufactured. These pages do not specify a fixed maximum Message session duration, so no limit is copied from a different Qwen protocol.
- [Assembly WebSocket reference](https://www.assemblyai.com/docs/streaming/api-spec/streaming-websocket): explicit `universal-3-6-pro`, `max_accuracy`, mono 16 kHz `pcm_s16le`, raw Authorization key, 20–1000 ms binary packets. A validated Begin acknowledges actual model/mode. Partials replace the same numbered turn; Pro final turns are formatted. Terminate drains final turns before Termination. [Endpoint/data zones](https://www.assemblyai.com/docs/streaming/endpoints-and-data-zones) defines global, US and EU hosts.
- [Assembly message sequence](https://www.assemblyai.com/docs/streaming/message-sequence), [midstream configuration](https://www.assemblyai.com/docs/streaming/updating-configuration-mid-stream) and [prompt/keyterms](https://www.assemblyai.com/docs/streaming/prompting-and-keyterms): prompt UpdateConfiguration follows Begin and has no acknowledgement; the existing verbatim topic context is retained. Maximum session duration is three hours; Saytile segments are much shorter.
- [Assembly session errors](https://www.assemblyai.com/docs/streaming/common-session-errors-and-closures): parse the Error frame before the close. Code 1008 can mean auth, funds, disabled access or new-session rate limiting; it cannot safely mean one generic retryable connection error. Code 3007 is an audio duration/rate violation; 3005/3008 are recoverable service/session failures. Unknown policy failures are not blindly retried.

## Concrete fixes

1. Preserve provider-final text against late partials and duplicate delivery. A conflicting second final raises a safe protocol error without mutating the accepted state. Separate turns containing intentional repetition remain separate.
2. Distinguish authorization, access permission, workspace/region, exhausted quota, temporary rate limit, bad configuration, protocol incompatibility and connection failure. No arbitrary service error body is surfaced. Unknown Qwen CLIENT_ERROR remains a connection failure because the official example is a timeout; no unverified claim is made that all future error codes are exhaustively classified.
3. Normalize malformed JSON into a safe protocol diagnostic rather than leaking parser errors or disguising a schema incompatibility as a network failure.
4. Check Qwen audio-upload consent at the adapter network boundary, matching the existing Assembly behavior. Connection-ready callbacks fire only after the provider acknowledgement passes validation, never merely after a socket upgrade.
5. Internal loopback URL injection preserves the production request, authentication headers, PCM encoder, URLSession and parser. Only literal loopback addresses with explicit ports are accepted; test query parameters cannot replace official model parameters. Production configuration has no custom endpoint path.
6. Missing leading/interior Qwen sentence IDs cannot form a stable prefix or complete recording. A later arrival can repair the sequence; zero is reserved for ignored heartbeats. This prevents a missing leading negation from being treated as an independently complete command.

## Cost references for an explicitly authorized tiny connection sample

[Qwen's current model page](https://help.aliyun.com/en/model-studio/qwen-audio-3-1-asr-flash-message) lists standard Beijing prices of CNY 6 input / 4.5 output per million tokens and Singapore CNY 6.781 / 5.104. No audio-seconds-to-token conversion or minimum billing rule was established in this audit; a duration-only Qwen cost guarantee would be unsupported.

[Assembly's 2026-10-26 official post](https://www.assemblyai.com/blog/why-assemblyai-is-designed-for-coding-agents) lists Universal-3.6 Pro at USD 0.45/hour, billed per second without minimums. [Its billing FAQ](https://www.assemblyai.com/docs/faq/how-does-universal-streaming-session-based-pricing-work) specifies full open-session duration, including idle time, separately for each session. Therefore the wizard must bound session wall time as well as sample duration and explicitly terminate normal sessions. These are public estimates, not the user's account tariff or a billing guarantee; no paid sample was run.

## Evidence

- `asr-protocol-red.log`: 6 test methods, 21 failed assertions (classification, final immutability, JSON). Loopback endpoint guard already passed.
- `asr-protocol-green.log`: 35 tests / 3 suites passed, including the 6 new methods and the existing Chinese/English protocol suites.
- `asr-boundary-red.log`: 2 test methods, 3 failed assertions (missing consent and invalid Begin identity).
- `asr-sequence-red.log`: 2 test methods, 4 failed assertions (missing leading sentence incorrectly stable/complete, invalid ordinary zero ID).
- `asr-protocol-final-green.log`: **39 tests / 3 suites passed**, including all 10 new test methods; the existing Chinese and English provider suites remain green. This is the final focused source regression.
- Intermediate build-only failures are retained as `asr-boundary-build-failure.log`, `asr-sequence-build-failure.log` (a corrected test initializer argument order) and `asr-final-shared-build-failure.log` (a concurrent wizard Sendable capture corrected by its owner). None are counted as executed test failures or passes.
- Further final regression and local URLSession simulator receipts are recorded separately; simulator responses must not be described as real Qwen/Assembly recognition.
