# Production transport protocol integration — NO_API_ENGINEERING_READY

This evidence uses the production `URLSessionWebSocketTask` / HTTP streaming clients, provider parsers, `GPTReviewSession`, `MultiRecognitionSession`, `SingleTranscriptEngine`, SQLite store, and automatic connection-check backend. Only the endpoint and credential supplier are replaced. The peer is a stateful `aiohttp 3.14.5` server bound to `127.0.0.1` on an ephemeral port. No provider API, real credential, microphone, user recording, or production database was accessed.

**This is protocol simulation, not LIVE_VERIFIED, speech accuracy, or a real account/model entitlement test.** The peer emits deterministic changing ASR hypotheses as PCM arrives. It hashes the actual binary PCM and validates framing, configuration, EOS, model, evidence identity, and request lineage. Its GPT decisions reference candidate IDs/spans actually received; it does not perform language inference or acoustic recognition. Recognition quality and real-provider latency remain unverified.

## Reproduction and result

Run `scripts/test-protocol-simulator.sh` on macOS with Command Line Tools. It installs the pinned free test dependency into an isolated `/tmp` virtual environment if needed, launches the peer, runs the explicitly opted-in Swift suite, closes the server, and rejects any peer contract violation. The ordinary native unit command skips this suite when `SAYTILE_PROTOCOL_BASE_URL` is absent.

Final result: **11 test functions / 51 parameter scenarios passed**, with **49 actual network cases and zero peer contract violations**. Two invalid-budget scenarios deliberately fail before opening a socket. The protocol suite elapsed 6.627 seconds excluding build. See `native-network.log` and `wire-audit.json`; `source-manifest.json` binds the relevant source files and artifacts to their SHA-256 hashes. The source base is PR #6 `3cd8ebcbc94e7536ea8d4ccfd4474b72e9fd2b46` plus the recorded changes, not a claim that the original base passed these new tests.

| Coverage | Observed result |
| --- | --- |
| Qwen and Assembly production clients | Same complete PCM byte count and SHA-256 at both peers; partial changes followed by explicit EOS/final/termination |
| ASR faults | Auth/quota, disconnect, malformed event, absent final, timeout, server failure cannot become completed transcripts |
| Repeated/delayed events | Final text remains one sequence, with no duplicated transcript |
| Persistent GPT WebSocket | Actual `response.create`, scoped `stream_id`, `previous_response_id`, full manifest and changed-evidence deltas; foreign/stale events ignored |
| Cache/connection recovery | One bounded full-evidence rebuild after cache loss, service connection-limit event, or real socket disconnect |
| Unsupported WebSocket | Same configured model through production HTTP/SSE; one failed upgrade per unchanged session/configuration, then direct HTTP |
| GPT failures | Wrong applied model, invalid JSON/schema, auth/quota/rate/server faults, streamed error/failed responses, timeout, cancellation stay explicit failures |
| Publication boundary | Unbacked candidate UUID/span is rejected; no dispatchable final publication; saved audio and ASR-supported display remain |
| Real connection-check backend | Bundled synthetic PCM, actual two-provider wire traffic, accepted model readiness, first text, GPT live review, EOS review and store completion |

The bundled connection-check sample is 6.2720625 seconds, SHA-256 `5d29f5fc799a571b27d80bcf442004ba78a619c0d6e847258bb2b6b8b075387a`. It was paced in 100 ms blocks. Each of the four backend scenarios had exactly two ASR connections, each receiving the complete matching PCM and EOS. The check-specific policy permits one live review plus EOS and at most six attempted GPT requests; ordinary recognition keeps its existing unrestricted review policy.

| Paced connection-check scenario | Actual GPT response requests received | Backend result |
| --- | ---: | --- |
| Normal | 2 WebSocket | Pipeline completed, all three services verified in simulation |
| Hypothesis changes on every PCM block | 2 WebSocket | Completed within the check budget |
| WebSocket unsupported | 2 HTTP, one rejected upgrade | Completed through the same-model HTTP client |
| Socket disconnect on each initial review attempt | 4 WebSocket | Both reviews recovered with full evidence |

All actual GPT request bodies above carried `max_output_tokens: 4096`. Invalid values 0 and 128001 were rejected before socket creation. The connection report always remained `NO_API_ENGINEERING_READY`, `live=false`, `canEnableCloud=false`; simulated verified service states cannot enable real cloud recognition.

## Reproduced defects and fixes

1. **macOS socket disconnect was not retried.** The real WebSocket test produced `NSPOSIXErrorDomain` code 57; handling only `URLError` missed this path. The production socket now classifies a small set of genuine disconnect codes for one bounded reconnect, rebuilding the complete current evidence. `network-first-red.log` also contains two separately identified simulator quota-frame mistakes; those were corrected to the official Assembly Error shape and are not claimed as product defects.
2. **Unsupported transport repeatedly consumed the check budget.** Repeated WebSocket upgrade failures plus HTTP fallback exhausted the automatic check despite successful HTTP responses. `wizard-fallback-red.log` reproduces this. The session now remembers unsupported WebSocket for the exact configuration/credential fingerprint; reset, changed credentials/configuration, or cancellation invalidates it. The connection-check owner separately reserved enough budget for EOS. That red log also has an obsolete assertion that expected invalid GPT evidence to publish; the final test correctly requires rejection and no dispatchable publication.
3. **Streamed account errors lost their category.** Real WS `response.failed` and HTTP 200 SSE `error` / `response.failed` were misreported as incomplete output. `stream-errors-red.log` contains the three failing diagnostics. Known provider codes now produce safe quota/rate/permission/connection categories without exposing arbitrary messages. That red log also records the check-only policy changing from two live reviews to one; the final expected retry count matches the final policy.

The pure GPT/evidence regression separately passed 19 test functions in two suites (`gpt-regression.log`). Shell syntax, Python syntax, and `git diff --check` passed. Full native product regression, actual UI interaction, packaging, local recognition, and external input are recorded by their separate owners; this report does not substitute for those checks.

## Boundaries

- The loopback endpoint seams are internal and reject non-loopback hosts, missing ports, user information, and fragments. Default production endpoints are unchanged.
- The simulator's only accepted credential is a fixed synthetic string in its fixture source. Wire artifacts record counts, hashes, model/configuration metadata and event identity, not credential values or PCM bodies.
- No real paid call, account entitlement, regional access, provider deployment, ASR accuracy, subjective speech experience, or cloud latency is claimed.
- A mock model returning a fluent result cannot prove accuracy; the test asserts transport, evidence, state, cancellation, storage and publication behavior only.

Protocol references: [OpenAI WebSocket mode](https://developers.openai.com/api/docs/guides/websocket-mode), [aiohttp server reference](https://docs.aiohttp.org/en/stable/web_reference.html). ASR request/frame contracts and their official references are recorded in the ASR provider review evidence.
