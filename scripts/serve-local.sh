#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${1:-8080}"

DEFAULT_EXTRA_DISK_MB="${DEFAULT_EXTRA_DISK_MB:-${DEFAULT_DISK_MB:-256}}" "${ROOT_DIR}/scripts/ensure-default-disk.sh"

exec python3 "${ROOT_DIR}/scripts/serve-compressed.py" "${PORT}" "${ROOT_DIR}/public"
