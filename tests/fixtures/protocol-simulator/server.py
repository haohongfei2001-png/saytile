#!/usr/bin/env python3
"""Loopback protocol peers, not speech recognition or a cloud-quality benchmark.

The real product clients connect over WebSocket/HTTP. ASR evolution is driven by
received PCM duration and EOS; GPT selections are derived from the actual candidate
manifest supplied by the client. No credential or audio body is written to audit.
"""
import argparse
import asyncio
import hashlib
import json
import signal
import time
from pathlib import Path
from aiohttp import WSMsgType, web

KEY = "simulator-fixture-credential"
MODEL = "gpt-6-astra"
CASES = {}
STARTED = time.monotonic()


def state(request):
    name = request.query.get("case", "default")
    return CASES.setdefault(name, {"connections": [], "gpt_requests": [], "violations": [], "events": []})


def audit(s, event, **values):
    s["events"].append({"event": event, "milliseconds": round((time.monotonic() - STARTED) * 1000, 3), **values})


def require(s, condition, reason):
    if not condition:
        s["violations"].append(reason)
        raise web.HTTPBadRequest(text="simulator request contract mismatch")


def check_auth(request, provider):
    expected = KEY if provider == "assembly" else "Bearer " + KEY
    if request.headers.get("Authorization") != expected or request.query.get("fault") == "auth":
        raise web.HTTPUnauthorized(text='{"error":{"code":"invalid_api_key"}}', content_type="application/json")


def phrase(provider, stage):
    if stage == 1:
        return "请支付50元。" if provider == "qwen" else "请支付15元。"
    if stage == 2:
        return "请不要支付15元。"
    return "请不要支付15元，send the report。"


def utf16_length(value):
    return len(value.encode("utf-16-le")) // 2


async def asr(request):
    provider = request.match_info["provider"]
    s, fault = state(request), request.query.get("fault", "normal")
    check_auth(request, provider)
    if fault == "server_error":
        raise web.HTTPServiceUnavailable(text="synthetic service outage")
    ws = web.WebSocketResponse(heartbeat=None, max_msg_size=1_000_000)
    await ws.prepare(request)
    entry = {"provider": provider, "pcm_bytes": 0, "blocks": [], "eos": False, "closed": False}
    s["connections"].append(entry)
    digest, stage, task_id = hashlib.sha256(), 0, None
    audit(s, provider + ".connected")
    if provider == "assembly":
        required = {"speech_model": "universal-3-6-pro", "mode": "max_accuracy", "sample_rate": "16000", "encoding": "pcm_s16le", "include_partial_turns": "true", "language_detection": "true", "filter_profanity": "false"}
        require(s, all(request.query.get(k) == v for k, v in required.items()), "assembly query")
        if fault == "quota":
            await ws.send_json({"type": "Error", "error_code": 1008, "error": "Unauthorized Connection: Insufficient funds DO_NOT_SURFACE_SECRET"})
        else:
            await ws.send_json({"type": "Begin", "id": "assembly-fixture", "expires_at": 9999999999,
                                "configuration": {"model": required["speech_model"], "mode": "max_accuracy"}})
    async def result(current_stage, final=False):
        text = phrase(provider, current_stage)
        if fault == "churn" and not final:
            text += " 继续" + str(entry["pcm_bytes"] // 1600)
        end = max(20, entry["pcm_bytes"] // 32)
        if provider == "qwen":
            event = {"header": {"task_id": task_id, "event": "result-generated"},
                     "payload": {"output": {"sentence": {"sentence_id": 1, "text": text,
                     "begin_time": 0, "end_time": end, "sentence_end": final,
                     "words": [{"text": text, "begin_time": 0, "end_time": end}]}}}}
        else:
            event = {"type": "Turn", "turn_order": 0, "transcript": text,
                     "end_of_turn": final, "turn_is_formatted": final, "language_code": "zh",
                     "words": [{"text": text, "start": 0, "end": end, "word_is_final": final}]}
        await ws.send_json(event)
        if fault == "duplicate":
            await ws.send_json(event)
        audit(s, provider + (".final" if final else ".partial"), text=text, pcm_bytes=entry["pcm_bytes"])
    try:
        async for message in ws:
            if message.type == WSMsgType.BINARY:
                require(s, task_id is not None or provider == "assembly", "PCM before task start")
                block = message.data
                require(s, len(block) > 0 and len(block) % 2 == 0, "PCM alignment")
                if provider == "assembly":
                    require(s, 640 <= len(block) <= 32000, "Assembly PCM duration")
                entry["pcm_bytes"] += len(block); entry["blocks"].append(len(block)); digest.update(block)
                if fault == "disconnect" and entry["pcm_bytes"] >= 6400:
                    await ws.close(code=1011, message=b"synthetic network failure"); break
                if fault == "malformed":
                    await ws.send_str("{bad-json"); continue
                if fault == "timeout":
                    continue
                next_stage = 1 if entry["pcm_bytes"] < 8000 else 2 if entry["pcm_bytes"] < 16000 else 3
                if next_stage > stage or fault == "churn":
                    stage = next_stage
                    if fault == "delay":
                        await asyncio.sleep(0.12)
                    await result(stage)
            elif message.type == WSMsgType.TEXT:
                value = json.loads(message.data)
                if provider == "qwen" and value.get("header", {}).get("action") == "run-task":
                    header, payload = value["header"], value["payload"]
                    task_id = header.get("task_id")
                    require(s, bool(task_id) and header.get("streaming") == "duplex", "Qwen task identity")
                    params = payload.get("parameters", {})
                    require(s, payload.get("model") == "qwen-audio-3.1-asr-flash-message" and params.get("format") == "pcm" and params.get("sample_rate") == 16000 and params.get("intermediate_result_enabled") is True, "Qwen model/PCM")
                    entry["task_id"] = task_id
                    if fault == "quota":
                        await ws.send_json({"header": {"task_id": task_id, "event": "task-failed", "error_code": "QuotaExceeded", "error_message": "DO_NOT_SURFACE_SECRET"}})
                        continue
                    await ws.send_json({"header": {"task_id": task_id, "event": "task-started"}})
                elif provider == "assembly" and value.get("type") == "UpdateConfiguration":
                    require(s, isinstance(value.get("prompt"), str), "Assembly context")
                    entry["context_received"] = True
                elif provider == "qwen" and value.get("header", {}).get("action") == "finish-task" or provider == "assembly" and value.get("type") == "Terminate":
                    if provider == "qwen":
                        require(s, value["header"].get("task_id") == task_id, "Qwen EOS identity")
                    entry["eos"] = True; audit(s, provider + ".eos", pcm_bytes=entry["pcm_bytes"])
                    if fault == "timeout":
                        continue
                    if fault != "missing_final":
                        await result(3, final=True)
                    if provider == "qwen":
                        await ws.send_json({"header": {"task_id": task_id, "event": "task-finished"}})
                    else:
                        await ws.send_json({"type": "Termination", "audio_duration_seconds": entry["pcm_bytes"] / 32000})
                else:
                    require(s, False, "unknown ASR client message")
            elif message.type == WSMsgType.ERROR:
                break
    finally:
        entry["sha256"] = digest.hexdigest(); entry["closed"] = True
        audit(s, provider + ".closed", pcm_bytes=entry["pcm_bytes"])
    return ws


def evidence_payload(s, value):
    require(s, value.get("model") == MODEL and value.get("store") is False, "GPT exact model/store")
    require(s, value.get("text", {}).get("format", {}).get("type") == "json_schema", "GPT structured schema")
    require(s, value.get("text", {}).get("format", {}).get("strict") is True, "GPT strict schema")
    require(s, value.get("tools") in (None, []), "GPT no tools")
    items = value.get("input", [])
    require(s, len(items) == 1 and items[0].get("role") == "user", "GPT input")
    return json.loads(items[0]["content"])


def response_object(identifier, manifest):
    # The simulator never writes new text: its decision references received evidence.
    candidates = list(manifest.values())
    selected = max(candidates, key=lambda c: (bool(c.get("isComplete")), utf16_length(c["text"]), c["text"])) if candidates else None
    resolved = bool(candidates) and all(c.get("isComplete") for c in candidates) and len({c["text"] for c in candidates}) == 1
    selection = [{"candidateID": selected["candidateID"], "utf16Start": 0, "utf16End": utf16_length(selected["text"])}] if selected and selected["text"] else []
    decision = {"selections": selection, "unresolved": not resolved, "needsAudioReview": False, "reasonCode": "protocol-fixture-evidence"}
    return {"id": identifier, "model": MODEL, "status": "completed", "output": [{"type": "message", "status": "completed", "content": [{"type": "output_text", "text": json.dumps(decision, ensure_ascii=False)}]}], "usage": {"input_tokens": len(candidates) * 10, "output_tokens": 12,
        "input_tokens_details": {"cached_tokens": 3}, "output_tokens_details": {"reasoning_tokens": 5}}}


def streamed_failure(fault, identifier):
    if fault == "stream_quota":
        return {"type": "error", "code": "insufficient_quota", "message": "DO_NOT_SURFACE_SECRET"}
    if fault == "failed_rate":
        return {"type": "response.failed", "response": {"id": identifier, "model": MODEL, "status": "failed",
            "error": {"code": "rate_limit_exceeded", "message": "DO_NOT_SURFACE_SECRET"}}}
    return None


async def responses(request):
    s, fault = state(request), request.query.get("fault", "normal")
    check_auth(request, "gpt")
    if request.method == "GET" and fault == "unsupported":
        s["unsupported_upgrades"] = s.get("unsupported_upgrades", 0) + 1
        audit(s, "gpt.websocket_unsupported")
        raise web.HTTPUpgradeRequired()
    if request.method == "POST" and fault in ("quota", "rate_limit", "server_error"):
        code, status = {"quota": ("insufficient_quota", 429), "rate_limit": ("rate_limit_exceeded", 429), "server_error": ("server_error", 503)}[fault]
        return web.json_response({"error": {"code": code, "message": "DO_NOT_SURFACE_SECRET"}}, status=status)
    if request.method == "POST":
        value = await request.json()
        require(s, "stream_id" not in value and "type" not in value and value.get("stream") is True, "HTTP must not contain WebSocket envelope")
        payload = evidence_payload(s, value)
        candidates = payload["candidates"]
        identifier = "resp_http_" + str(len(s["gpt_requests"]) + 1)
        s["gpt_requests"].append({"transport": "http", "candidate_count": len(candidates), "model": value["model"], "max_output_tokens": value.get("max_output_tokens")})
        result = response_object(identifier, {c["candidateID"]: c for c in candidates})
        response = web.StreamResponse(headers={"Content-Type": "text/event-stream", "x-request-id": identifier})
        await response.prepare(request)
        if fault == "malformed":
            await response.write(b"data: {broken-json\n\n")
            await response.write_eof()
            return response
        terminal = streamed_failure(fault, identifier) or {"type": "response.completed", "response": result}
        for event in [{"type": "response.created", "response": {"id": identifier, "model": MODEL}}, {"type": "response.output_text.delta", "response_id": identifier, "delta": "{partial"}, terminal]:
            await response.write(("data: " + json.dumps(event, ensure_ascii=False) + "\n\n").encode())
            await asyncio.sleep(0.015)
        await response.write_eof(); audit(s, "gpt.http_completed")
        return response
    ws = web.WebSocketResponse(heartbeat=None)
    await ws.prepare(request)
    entry = {"provider": "gpt", "closed": False}
    s["connections"].append(entry)
    connection_number = sum(c["provider"] == "gpt" for c in s["connections"])
    manifests, previous = {}, {}
    audit(s, "gpt.connected", connection=connection_number)
    try:
        async for message in ws:
            if message.type != WSMsgType.TEXT:
                continue
            value = json.loads(message.data)
            require(s, value.get("type") == "response.create" and "stream" not in value, "GPT WS envelope")
            lane = value.get("stream_id")
            require(s, isinstance(lane, str) and 1 <= len(lane) <= 256, "GPT lane")
            payload = evidence_payload(s, value)
            request_number = len(s["gpt_requests"]) + 1
            s["gpt_requests"].append({"transport": "websocket", "connection": connection_number, "stream_id": lane,
                "previous_response_id": value.get("previous_response_id"), "reset": payload.get("resetEvidence"),
                "candidate_count": len(payload["candidates"]), "manifest_count": len(payload.get("currentManifest", [])), "model": value["model"], "max_output_tokens": value.get("max_output_tokens")})
            audit(s, "gpt.request", request=request_number)
            if fault in ("quota", "rate_limit", "server_error"):
                code, status = {"quota": ("insufficient_quota", 429), "rate_limit": ("rate_limit_exceeded", 429), "server_error": ("server_error", 503)}[fault]
                await ws.send_json({"type": "error", "stream_id": lane, "status": status, "error": {"code": code, "message": "DO_NOT_SURFACE_SECRET"}})
                continue
            if fault == "reconnect" and request_number == 2 or fault == "each_reconnect" and request_number % 2 == 1:
                await ws.close(code=1011, message=b"synthetic disconnect"); break
            if fault == "cache_miss" and request_number == 2:
                await ws.send_json({"type": "error", "stream_id": lane, "status": 400, "error": {"code": "previous_response_not_found"}}); continue
            if fault == "limit" and request_number == 2:
                await ws.send_json({"type": "error", "status": 400, "error": {"code": "websocket_connection_limit_reached"}}); continue
            if payload.get("resetEvidence") is True:
                require(s, value.get("previous_response_id") is None, "GPT reset lineage")
                manifests[lane] = {}
            else:
                require(s, value.get("previous_response_id") == previous.get(lane), "GPT previous response lineage")
            manifest = manifests.setdefault(lane, {})
            for candidate in payload["candidates"]:
                manifest[candidate["candidateID"]] = candidate
            current_ids = {item["candidateID"] for item in payload["currentManifest"]}
            manifest = {identifier: candidate for identifier, candidate in manifest.items() if identifier in current_ids}
            manifests[lane] = manifest
            require(s, set(manifest) == current_ids, "GPT incomplete evidence manifest")
            identifier = f"resp_{connection_number}_{request_number}"
            if fault == "malformed":
                await ws.send_str("{broken-json"); continue
            if fault == "old_events" and previous.get(lane):
                await ws.send_json({"type": "response.completed", "stream_id": lane, "response": response_object(previous[lane], manifest)})
            # A foreign lane must never be mistaken for this request.
            await ws.send_json({"type": "response.created", "stream_id": "unrelated-lane", "response": {"id": "foreign", "model": MODEL}})
            model = "wrong-model" if fault == "wrong_model" else MODEL
            await ws.send_json({"type": "response.created", "stream_id": lane, "response": {"id": identifier, "model": model, "status": "in_progress"}})
            if failure := streamed_failure(fault, identifier):
                await ws.send_json(dict(failure, stream_id=lane)); continue
            if fault in ("timeout", "cancel"):
                continue
            if fault == "delay":
                await asyncio.sleep(0.18)
            await ws.send_json({"type": "response.output_text.delta", "stream_id": lane, "response_id": identifier, "delta": "{partial-json"})
            if fault == "old_events":
                await ws.send_json({"type": "response.completed", "stream_id": lane, "response": {"id": "stale-response", "model": MODEL, "status": "completed"}})
            result = response_object(identifier, manifest)
            if fault == "invalid_schema":
                result["output"][0]["content"][0]["text"] = json.dumps({"unsupported_text": "invented"})
            if fault == "unbacked_selection":
                decision = json.loads(result["output"][0]["content"][0]["text"])
                decision["selections"] = [{"candidateID": "00000000-0000-4000-8000-000000000099", "utf16Start": 0, "utf16End": 999}]
                result["output"][0]["content"][0]["text"] = json.dumps(decision)
            await ws.send_json({"type": "response.completed", "stream_id": lane, "response": result})
            previous[lane] = identifier
            audit(s, "gpt.completed", response_id=identifier)
    finally:
        entry["closed"] = True
        audit(s, "gpt.closed", connection=connection_number)
    return ws


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ready", type=Path, required=True)
    parser.add_argument("--audit", type=Path, required=True)
    args = parser.parse_args()
    app = web.Application(client_max_size=2_000_000)
    app.router.add_get("/{provider:qwen|assembly}", asr)
    app.router.add_route("*", "/responses", responses)
    app.router.add_get("/state/{case}", lambda request: web.json_response(CASES.get(request.match_info["case"], {})))
    runner = web.AppRunner(app, access_log=None, shutdown_timeout=1)
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", 0)
    await site.start()
    port = site._server.sockets[0].getsockname()[1]
    args.ready.write_text(json.dumps({"port": port, "scope": "loopback-protocol-simulation"}))
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    await stop.wait()
    await runner.cleanup()
    args.audit.write_text(json.dumps({"scope": "SIMULATED_PROTOCOL_NOT_LIVE_CLOUD", "cases": CASES}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
