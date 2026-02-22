#!/usr/bin/env bash
set -euo pipefail

IMAGE_PATH="${1:-public/assets/buildroot-linux.img}"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

for cmd in dumpe2fs awk stat du numfmt; do
    need_cmd "$cmd"
done

if [[ ! -f "${IMAGE_PATH}" ]]; then
    echo "Image not found: ${IMAGE_PATH}" >&2
    exit 1
fi

read -r block_count free_blocks reserved_blocks block_size < <(
    dumpe2fs -h "${IMAGE_PATH}" 2>/dev/null | awk '
        /Block count:/ {bc=$3}
        /Free blocks:/ {fb=$3}
        /Reserved block count:/ {rb=$4}
        /Block size:/ {bs=$3}
        END {printf "%s %s %s %s\n", bc, fb, rb, bs}
    '
)

if [[ -z "${block_count:-}" || -z "${free_blocks:-}" || -z "${block_size:-}" ]]; then
    echo "Unable to parse ext filesystem metadata from: ${IMAGE_PATH}" >&2
    exit 1
fi

used_blocks=$((block_count - free_blocks))
total_bytes=$((block_count * block_size))
used_bytes=$((used_blocks * block_size))
free_bytes=$((free_blocks * block_size))
reserved_bytes=$((reserved_blocks * block_size))
file_bytes="$(stat -c '%s' "${IMAGE_PATH}")"

echo "image: ${IMAGE_PATH}"
echo "file_size_bytes=${file_bytes}"
echo "file_size_human=$(numfmt --to=iec-i --suffix=B "${file_bytes}")"
echo "fs_block_size=${block_size}"
echo "fs_blocks_total=${block_count}"
echo "fs_blocks_used=${used_blocks}"
echo "fs_blocks_free=${free_blocks}"
echo "fs_blocks_reserved=${reserved_blocks}"
echo "fs_bytes_total=${total_bytes}"
echo "fs_bytes_used=${used_bytes}"
echo "fs_bytes_free=${free_bytes}"
echo "fs_bytes_reserved=${reserved_bytes}"
echo "fs_mib_total=$(awk "BEGIN {printf \"%.2f\", ${total_bytes}/1048576}")"
echo "fs_mib_used=$(awk "BEGIN {printf \"%.2f\", ${used_bytes}/1048576}")"
echo "fs_mib_free=$(awk "BEGIN {printf \"%.2f\", ${free_bytes}/1048576}")"
