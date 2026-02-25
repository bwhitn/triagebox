#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_EXTRA_DISK_PATH="${DEFAULT_EXTRA_DISK_PATH:-${DEFAULT_DISK_PATH:-${ROOT_DIR}/public/assets/default-extra.img}}"
DEFAULT_EXTRA_DISK_MB="${DEFAULT_EXTRA_DISK_MB:-${DEFAULT_DISK_MB:-256}}"
DEFAULT_EXTRA_DISK_LABEL="${DEFAULT_EXTRA_DISK_LABEL:-data}"

if [[ -f "${DEFAULT_EXTRA_DISK_PATH}" ]]; then
    exit 0
fi

if ! [[ "${DEFAULT_EXTRA_DISK_MB}" =~ ^[0-9]+$ ]] || (( DEFAULT_EXTRA_DISK_MB < 16 )); then
    echo "DEFAULT_EXTRA_DISK_MB must be an integer >= 16 (got: ${DEFAULT_EXTRA_DISK_MB})" >&2
    exit 1
fi

if ! command -v truncate >/dev/null 2>&1; then
    echo "Cannot create default extra disk: missing required command 'truncate'" >&2
    exit 1
fi

MKFS_EXT2_BIN=""
if command -v mke2fs >/dev/null 2>&1; then
    MKFS_EXT2_BIN="$(command -v mke2fs)"
elif command -v mkfs.ext2 >/dev/null 2>&1; then
    MKFS_EXT2_BIN="$(command -v mkfs.ext2)"
else
    echo "Cannot create default extra disk: missing 'mke2fs' or 'mkfs.ext2'" >&2
    exit 1
fi

mkdir -p "$(dirname "${DEFAULT_EXTRA_DISK_PATH}")"

tmp_disk="${DEFAULT_EXTRA_DISK_PATH}.tmp.$$"
cleanup() {
    rm -f "${tmp_disk}"
}
trap cleanup EXIT

echo "Default extra disk image missing; creating blank ext2 disk at ${DEFAULT_EXTRA_DISK_PATH} (${DEFAULT_EXTRA_DISK_MB} MiB)"

truncate -s "${DEFAULT_EXTRA_DISK_MB}M" "${tmp_disk}"
"${MKFS_EXT2_BIN}" -q -t ext2 -L "${DEFAULT_EXTRA_DISK_LABEL}" -F "${tmp_disk}"

mv -f "${tmp_disk}" "${DEFAULT_EXTRA_DISK_PATH}"
trap - EXIT
