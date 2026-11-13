#!/usr/bin/env bash
# Debug run with throw-away data, signed in against a local DEV_AUTH server if
# DUEBAR_DEV_EMAIL is set (see Scripts/integration_test.sh for starting one).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export DUEBAR_DATA_DIR="${DUEBAR_DATA_DIR:-$HOME/Library/Application Support/DueBar-dev}"
exec swift run DueBar
