#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d "${TMPDIR:-/tmp}/saytile-cloud-peer.XXXXXX")
node cloud/test/native-peer.mjs "$tmp" & peer=$!
trap 'kill "$peer" 2>/dev/null || true; wait "$peer" 2>/dev/null || true; rm -rf "$tmp"' EXIT
for _ in {1..200}; do [[ -s "$tmp/port" ]] && break; sleep .05; done
swift build -c debug --product SaytileKit -Xswiftc -enable-testing
bin=$(swift build -c debug --show-bin-path)
map="$bin/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"
[[ -f "$map" ]] || map="$bin/CAudio.build/module.modulemap"
swiftc -swift-version 6 -parse-as-library -I "$bin" -I "$bin/Modules" -I Sources/CSQLite -Xcc "-fmodule-map-file=$map" -L "$bin" -lSaytileKit -lc++ tests/fixtures/HostedGatewayProbe.swift tests/fixtures/HostedAccountProbe.swift -o "$tmp/probe"
if [[ -n "${SAYTILE_TEST_PROBE_OUTPUT:-}" ]]; then install -m 700 "$tmp/probe" "$SAYTILE_TEST_PROBE_OUTPUT"; fi
"$tmp/probe" "$tmp" "$(cat "$tmp/port")"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["started"]==1 and d["ai"]>=1 and d["bytes"]==3200,d; print(d)' "$tmp/counts.json"
