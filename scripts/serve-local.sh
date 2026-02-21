#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${1:-8080}"

exec python3 -m http.server "${PORT}" --directory "${ROOT_DIR}/public"
