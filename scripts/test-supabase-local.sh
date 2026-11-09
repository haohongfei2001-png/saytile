#!/bin/bash
# Creates only a fresh local stack with a private home and random ports; never links a hosted project.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/saytile-local-auth.XXXXXX")
umask 077
export SUPABASE_HOME="$tmp/home"
mkdir -p "$tmp/project/supabase" "$SUPABASE_HOME"
cli="${SAYTILE_FIXTURE_SUPABASE_CLI:-}"
if [[ -z "$cli" ]]; then
  npm install --no-audit --no-fund --prefix "$tmp/tools" supabase@3.1.0 >/dev/null
  cli="$tmp/tools/node_modules/.bin/supabase"
fi
cd "$tmp/project"
cat >supabase/config.toml <<'TOML'
project_id = "saytile-isolated-test"
[experimental]
stack = true
[auth.email]
enable_confirmations = true
[auth.email.template.confirmation]
subject = "Saytile isolated code"
content_path = "./supabase/otp.html"
[auth.email.template.magic_link]
subject = "Saytile isolated code"
content_path = "./supabase/otp.html"
TOML
echo '<p>Saytile fixture: {{ .Token }}</p>' >supabase/otp.html
cleanup() { "$cli" stack destroy --yes >"$tmp/stop.log" 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT
"$cli" start --runtime native --exclude realtime,storage,functions,studio,analytics,pooler --output-format json >"$tmp/start.json"
SAYTILE_EPHEMERAL_STACK=1 node "$root/cloud/test/auth-stack.mjs" "$tmp/start.json"
