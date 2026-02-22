#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="${ROOT_DIR}/public/build-config.js"
ENABLE_SERIAL="${ENABLE_SERIAL:-1}"

if [[ "${ENABLE_SERIAL}" != "0" && "${ENABLE_SERIAL}" != "1" ]]; then
    echo "ENABLE_SERIAL must be 0 or 1 (got: ${ENABLE_SERIAL})" >&2
    exit 1
fi

if [[ "${ENABLE_SERIAL}" == "1" ]]; then
    serial_flag=true
else
    serial_flag=false
fi

cat > "${OUT_FILE}" <<EOF
window.V86_BUILD_CONFIG = {
  enableSerial: ${serial_flag},
  rootFsType: "ext2",
  rootfsFlavor: "buildroot"
};
EOF

echo "Wrote ${OUT_FILE} (enableSerial=${serial_flag}, rootfsFlavor=buildroot, rootFsType=ext2)"
