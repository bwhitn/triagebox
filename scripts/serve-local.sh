#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${1:-8000}"

exec python3 "${ROOT_DIR}/scripts/serve-compressed.py" "${PORT}" "${ROOT_DIR}/public"
