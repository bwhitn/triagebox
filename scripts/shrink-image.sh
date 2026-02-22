#!/usr/bin/env bash
set -euo pipefail

IMAGE_PATH="${1:-public/assets/buildroot-linux.img}"
PAD_MB="${PAD_MB:-32}"
MIN_MB="${MIN_MB:-0}"
BACKUP_PATH="${BACKUP_PATH:-}"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

for cmd in e2fsck resize2fs dumpe2fs awk truncate stat cp; do
    need_cmd "$cmd"
done

if [[ ! -f "${IMAGE_PATH}" ]]; then
    echo "Image not found: ${IMAGE_PATH}" >&2
    exit 1
fi

if ! [[ "${PAD_MB}" =~ ^[0-9]+$ ]]; then
    echo "PAD_MB must be an integer >= 0 (got: ${PAD_MB})" >&2
    exit 1
fi
if ! [[ "${MIN_MB}" =~ ^[0-9]+$ ]]; then
    echo "MIN_MB must be an integer >= 0 (got: ${MIN_MB})" >&2
    exit 1
fi

if [[ -n "${BACKUP_PATH}" ]]; then
    echo "Creating backup: ${BACKUP_PATH}"
    cp -a "${IMAGE_PATH}" "${BACKUP_PATH}"
fi

run_e2fsck() {
    local rc=0
    e2fsck -fy "$1" || rc=$?
    if (( rc > 1 )); then
        echo "e2fsck failed with exit code ${rc}" >&2
        exit "${rc}"
    fi
}

read_fs_meta() {
    dumpe2fs -h "$1" 2>/dev/null | awk '
        /Block count:/ {bc=$3}
        /Block size:/ {bs=$3}
        END {printf "%s %s\n", bc, bs}
    '
}

echo "Checking filesystem before resize"
run_e2fsck "${IMAGE_PATH}"

echo "Shrinking filesystem to minimum"
resize2fs -M "${IMAGE_PATH}"

read -r min_blocks block_size < <(read_fs_meta "${IMAGE_PATH}")
if [[ -z "${min_blocks:-}" || -z "${block_size:-}" ]]; then
    echo "Unable to read filesystem metadata after minimum resize" >&2
    exit 1
fi

min_bytes=$((min_blocks * block_size))
target_bytes=$((min_bytes + PAD_MB * 1024 * 1024))
if (( MIN_MB > 0 )); then
    min_floor_bytes=$((MIN_MB * 1024 * 1024))
    if (( target_bytes < min_floor_bytes )); then
        target_bytes="${min_floor_bytes}"
    fi
fi

if (( target_bytes > min_bytes )); then
    target_kib=$(((target_bytes + 1023) / 1024))
    echo "Growing filesystem to target size (${target_kib} KiB, PAD_MB=${PAD_MB}, MIN_MB=${MIN_MB})"
    resize2fs "${IMAGE_PATH}" "${target_kib}K"
fi

read -r final_blocks final_block_size < <(read_fs_meta "${IMAGE_PATH}")
if [[ -z "${final_blocks:-}" || -z "${final_block_size:-}" ]]; then
    echo "Unable to read final filesystem metadata" >&2
    exit 1
fi

final_bytes=$((final_blocks * final_block_size))
echo "Truncating image file to ${final_bytes} bytes"
truncate -s "${final_bytes}" "${IMAGE_PATH}"

echo "Running final filesystem check"
run_e2fsck "${IMAGE_PATH}"

echo "Shrink complete: ${IMAGE_PATH}"
echo "final_size_bytes=$(stat -c '%s' "${IMAGE_PATH}")"
echo "Use ./scripts/disk-usage.sh ${IMAGE_PATH} to verify usage"
