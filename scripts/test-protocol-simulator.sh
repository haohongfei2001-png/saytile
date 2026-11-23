#!/bin/bash
# Local wire-level integration only. Never reads API keys, user audio or production data.
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_SIM_VENV="${SAYTILE_SIM_VENV:-/tmp/saytile-no-api-protocol-venv}"
SAYTILE_SIM_EVIDENCE="${SAYTILE_SIM_EVIDENCE:-evidence/no-api-product/protocol}"
mkdir -p "$SAYTILE_SIM_EVIDENCE"
if [[ ! -x "$SAYTILE_SIM_VENV/bin/python" ]]; then python3 -m venv "$SAYTILE_SIM_VENV"; fi
if ! "$SAYTILE_SIM_VENV/bin/python" -c 'import aiohttp; assert aiohttp.__version__ == "3.14.5"' 2>/dev/null; then
  "$SAYTILE_SIM_VENV/bin/python" -m pip install -r tests/fixtures/protocol-simulator/requirements.txt
fi
SAYTILE_SIM_RUN="$(mktemp -d /tmp/saytile-protocol-peer.XXXXXX)"
"$SAYTILE_SIM_VENV/bin/python" tests/fixtures/protocol-simulator/server.py --ready "$SAYTILE_SIM_RUN/ready.json" --audit "$SAYTILE_SIM_RUN/audit.json" > "$SAYTILE_SIM_EVIDENCE/server.log" 2>&1 &
SAYTILE_SIM_PID=$!
cleanup() {
  kill -TERM "$SAYTILE_SIM_PID" 2>/dev/null || true
  wait "$SAYTILE_SIM_PID" 2>/dev/null || true
  if [[ -f "$SAYTILE_SIM_RUN/audit.json" ]]; then cp "$SAYTILE_SIM_RUN/audit.json" "$SAYTILE_SIM_EVIDENCE/wire-audit.json"; fi
  rm -rf "$SAYTILE_SIM_RUN"
}
trap cleanup EXIT
for _ in {1..100}; do
  [[ -f "$SAYTILE_SIM_RUN/ready.json" ]] && break
  kill -0 "$SAYTILE_SIM_PID" 2>/dev/null || { cat "$SAYTILE_SIM_EVIDENCE/server.log"; exit 1; }
  sleep 0.05
done
SAYTILE_SIM_PORT="$("$SAYTILE_SIM_VENV/bin/python" -c 'import json,sys; print(json.load(open(sys.argv[1]))["port"])' "$SAYTILE_SIM_RUN/ready.json")"
SAYTILE_SIM_FILTER=(--filter ProtocolNetworkIntegrationTests)
if [[ "${SAYTILE_SIM_FULL_SUITE:-0}" == 1 ]]; then SAYTILE_SIM_FILTER=(); fi
SAYTILE_PROTOCOL_BASE_URL="http://127.0.0.1:$SAYTILE_SIM_PORT" SAYTILE_TEST_SCRATCH="${SAYTILE_TEST_SCRATCH:-/tmp/saytile-no-api-protocol-swift}" SAYTILE_TEST_LOG="$SAYTILE_SIM_EVIDENCE/native-network.log" scripts/test-native.sh ${SAYTILE_SIM_FILTER[@]+"${SAYTILE_SIM_FILTER[@]}"}

cleanup
trap - EXIT
"$SAYTILE_SIM_VENV/bin/python" - "$SAYTILE_SIM_EVIDENCE/wire-audit.json" <<'PY_AUDIT'
import json,sys
value=json.load(open(sys.argv[1]))
violations={key: item["violations"] for key,item in value["cases"].items() if item["violations"]}
if violations:
    raise SystemExit("Protocol peer rejected client contract: " + str(violations))
print("WIRE_AUDIT cases=" + str(len(value["cases"])) + " protocol_violations=0 scope=SIMULATED_PROTOCOL_NOT_LIVE_CLOUD")
PY_AUDIT
