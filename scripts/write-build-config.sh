#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="${ROOT_DIR}/public/build-config.js"
VERSION_FILE="${ROOT_DIR}/VERSION"
ENABLE_SERIAL="${ENABLE_SERIAL:-1}"
V86_ASSET_FLAVOR="${V86_ASSET_FLAVOR:-v86}"
PROJECT_VERSION="0.0.0"

if [[ "${ENABLE_SERIAL}" != "0" && "${ENABLE_SERIAL}" != "1" ]]; then
    echo "ENABLE_SERIAL must be 0 or 1 (got: ${ENABLE_SERIAL})" >&2
    exit 1
fi

if [[ ! "${V86_ASSET_FLAVOR}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "V86_ASSET_FLAVOR contains unsupported characters: ${V86_ASSET_FLAVOR}" >&2
    exit 1
fi

if [[ -f "${VERSION_FILE}" ]]; then
    PROJECT_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
fi

if [[ "${ENABLE_SERIAL}" == "1" ]]; then
    serial_flag=true
else
    serial_flag=false
fi

cat > "${OUT_FILE}" <<EOF
window.V86_BUILD_CONFIG = {
  projectVersion: "${PROJECT_VERSION}",
  enableSerial: ${serial_flag},
  bios: "assets/${V86_ASSET_FLAVOR}/seabios.bin",
  libv86Path: "assets/${V86_ASSET_FLAVOR}/libv86.js",
  wasmPath: "assets/${V86_ASSET_FLAVOR}/v86.wasm",
  v86AssetFlavor: "${V86_ASSET_FLAVOR}",
  rootFsType: "ext2",
  rootfsFlavor: "buildroot"
};
EOF

echo "Wrote ${OUT_FILE} (projectVersion=${PROJECT_VERSION}, enableSerial=${serial_flag}, v86AssetFlavor=${V86_ASSET_FLAVOR}, rootfsFlavor=buildroot, rootFsType=ext2)"
