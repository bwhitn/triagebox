#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v docker-compose >/dev/null 2>&1; then
    exec docker-compose -f "${ROOT_DIR}/docker-compose.yml" up --build
fi

if docker compose version >/dev/null 2>&1; then
    exec docker compose -f "${ROOT_DIR}/compose.yaml" up --build
fi

echo "No compose command found. Install docker-compose or docker compose plugin." >&2
exit 1
