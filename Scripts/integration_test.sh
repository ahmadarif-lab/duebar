#!/usr/bin/env bash
# Starts a throw-away API server (DEV_AUTH on, in-process Postgres) from a checkout of the
# private duebar-api repository and runs the Swift sync tests against it.
# DUEBAR_API_DIR defaults to ../duebar-api.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-3391}"
TMP="$(mktemp -d)"
API="${DUEBAR_API_DIR:-$ROOT/../duebar-api}"
[ -f "$API/test/dev-server.js" ] || { echo "duebar-api checkout not found at $API (set DUEBAR_API_DIR); skipping."; exit 0; }
cd "$API"
[ -d node_modules ] || npm ci --silent
PORT="$PORT" node test/dev-server.js >"$TMP/server.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true; rm -rf "$TMP"' EXIT
for _ in $(seq 1 50); do curl -fs "http://127.0.0.1:$PORT/health" >/dev/null && break; sleep 0.1; done
cd "$ROOT"
DUEBAR_TEST_SERVER="http://127.0.0.1:$PORT" swift test --filter SyncIntegrationTests
