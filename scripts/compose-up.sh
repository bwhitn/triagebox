#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_USE_SUDO="${DOCKER_USE_SUDO:-0}"

DEFAULT_EXTRA_DISK_MB="${DEFAULT_EXTRA_DISK_MB:-${DEFAULT_DISK_MB:-256}}" "${ROOT_DIR}/scripts/ensure-default-disk.sh"

if command -v docker-compose >/dev/null 2>&1; then
    if [[ "${DOCKER_USE_SUDO}" == "1" ]]; then
        exec sudo docker-compose -f "${ROOT_DIR}/docker-compose.yml" up --build
    fi
    exec docker-compose -f "${ROOT_DIR}/docker-compose.yml" up --build
fi

if [[ "${DOCKER_USE_SUDO}" == "1" ]]; then
    if sudo docker compose version >/dev/null 2>&1; then
        exec sudo docker compose -f "${ROOT_DIR}/compose.yaml" up --build
    fi
else
    if docker compose version >/dev/null 2>&1; then
        exec docker compose -f "${ROOT_DIR}/compose.yaml" up --build
    fi
fi

echo "No compose command found. Install docker-compose or docker compose plugin." >&2
exit 1
