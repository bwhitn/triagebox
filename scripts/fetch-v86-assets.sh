#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="${ROOT_DIR}/public/assets/v86"
XTERM_DIR="${ROOT_DIR}/public/assets/xterm"
PRIMARY_BASE_URL="${V86_BASE_URL:-https://copy.sh/v86}"
XTERM_VERSION="${XTERM_VERSION:-5.5.0}"
XTERM_FIT_ADDON_VERSION="${XTERM_FIT_ADDON_VERSION:-0.10.0}"
FETCH_VGA_BIOS="${FETCH_VGA_BIOS:-0}"

if [[ "${FETCH_VGA_BIOS}" != "0" && "${FETCH_VGA_BIOS}" != "1" ]]; then
    echo "FETCH_VGA_BIOS must be 0 or 1 (got: ${FETCH_VGA_BIOS})" >&2
    exit 1
fi

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

need_cmd curl

mkdir -p "${ASSETS_DIR}" "${XTERM_DIR}"

fetch_from_urls() {
    local dest="$1"
    shift
    local urls=("$@")

    local url
    for url in "${urls[@]}"; do
        echo "Downloading ${url}"
        if curl -fL "${url}" -o "${dest}"; then
            return 0
        fi
    done

    echo "Failed to download into ${dest}" >&2
    return 1
}

fetch_v86() {
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
    fetch_from_urls "${ASSETS_DIR}/${dest}" "${urls[@]}"
}

fetch_xterm() {
    local kind="$1"
    local dest="$2"
    local urls=()

    if [[ "${kind}" == "js" ]]; then
        urls=(
            "https://unpkg.com/@xterm/xterm@${XTERM_VERSION}/lib/xterm.js"
            "https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/lib/xterm.js"
            "https://unpkg.com/@xterm/xterm@${XTERM_VERSION}/dist/xterm.js"
            "https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/dist/xterm.js"
            "https://unpkg.com/xterm@${XTERM_VERSION}/lib/xterm.js"
            "https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/lib/xterm.js"
            "https://unpkg.com/xterm@${XTERM_VERSION}/dist/xterm.js"
            "https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/dist/xterm.js"
        )
    elif [[ "${kind}" == "css" ]]; then
        urls=(
            "https://unpkg.com/@xterm/xterm@${XTERM_VERSION}/css/xterm.css"
            "https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/css/xterm.css"
            "https://unpkg.com/@xterm/xterm@${XTERM_VERSION}/dist/xterm.css"
            "https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/dist/xterm.css"
            "https://unpkg.com/xterm@${XTERM_VERSION}/css/xterm.css"
            "https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/css/xterm.css"
            "https://unpkg.com/xterm@${XTERM_VERSION}/dist/xterm.css"
            "https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/dist/xterm.css"
        )
    else
        echo "fetch_xterm: unknown kind '${kind}'" >&2
        return 1
    fi

    fetch_from_urls "${XTERM_DIR}/${dest}" "${urls[@]}"
}

fetch_xterm_fit_addon() {
    local dest="$1"
    local urls=(
        "https://unpkg.com/@xterm/addon-fit@${XTERM_FIT_ADDON_VERSION}/lib/addon-fit.js"
        "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@${XTERM_FIT_ADDON_VERSION}/lib/addon-fit.js"
        "https://unpkg.com/@xterm/addon-fit@${XTERM_FIT_ADDON_VERSION}/dist/addon-fit.js"
        "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@${XTERM_FIT_ADDON_VERSION}/dist/addon-fit.js"
        "https://unpkg.com/@xterm/addon-fit@latest/lib/addon-fit.js"
        "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@latest/lib/addon-fit.js"
        "https://unpkg.com/@xterm/addon-fit@latest/dist/addon-fit.js"
        "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@latest/dist/addon-fit.js"
        "https://unpkg.com/xterm-addon-fit@latest/lib/xterm-addon-fit.js"
        "https://cdn.jsdelivr.net/npm/xterm-addon-fit@latest/lib/xterm-addon-fit.js"
        "https://unpkg.com/xterm-addon-fit@latest/dist/xterm-addon-fit.js"
        "https://cdn.jsdelivr.net/npm/xterm-addon-fit@latest/dist/xterm-addon-fit.js"
    )
    fetch_from_urls "${XTERM_DIR}/${dest}" "${urls[@]}"
}

fetch_v86 "build/libv86.js" "libv86.js"
fetch_v86 "build/v86.wasm" "v86.wasm"
fetch_v86 "bios/seabios.bin" "seabios.bin"
if [[ "${FETCH_VGA_BIOS}" == "1" ]]; then
    fetch_v86 "bios/vgabios.bin" "vgabios.bin"
fi

fetch_xterm "js" "xterm.js"
fetch_xterm "css" "xterm.css"
fetch_xterm_fit_addon "xterm-addon-fit.js"

echo "v86 assets written to ${ASSETS_DIR}"
echo "xterm assets written to ${XTERM_DIR}"
