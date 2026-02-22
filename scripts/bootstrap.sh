#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${ROOT_DIR}/scripts/check-build-deps.sh"
"${ROOT_DIR}/scripts/fetch-v86-assets.sh"
"${ROOT_DIR}/scripts/build-boot-assets-buildroot.sh"
"${ROOT_DIR}/scripts/write-build-config.sh"
