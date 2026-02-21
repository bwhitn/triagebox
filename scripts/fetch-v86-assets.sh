#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="${ROOT_DIR}/public/assets/v86"
PRIMARY_BASE_URL="${V86_BASE_URL:-https://copy.sh/v86}"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

need_cmd curl

mkdir -p "${ASSETS_DIR}"

fetch_one() {
    local src="$1"
    local dest="$2"
    local urls=("${PRIMARY_BASE_URL}/${src}")
    if [[ "${PRIMARY_BASE_URL}" != "https://copy.sh/v86" ]]; then
        urls+=("https://copy.sh/v86/${src}")
    fi
    urls+=(
        "https://unpkg.com/v86@latest/${src}"
        "https://cdn.jsdelivr.net/npm/v86@latest/${src}"
    )

    local url
    for url in "${urls[@]}"; do
        echo "Downloading ${url}"
        if curl -fL "${url}" -o "${ASSETS_DIR}/${dest}"; then
            return 0
        fi
    done

    echo "Failed to download ${src} from all configured mirrors." >&2
    return 1
}

fetch_one "build/libv86.js" "libv86.js"
fetch_one "build/v86.wasm" "v86.wasm"
fetch_one "bios/seabios.bin" "seabios.bin"
fetch_one "bios/vgabios.bin" "vgabios.bin"

echo "v86 assets written to ${ASSETS_DIR}"
