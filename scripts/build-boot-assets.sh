#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
ASSETS_DIR="${ROOT_DIR}/public/assets"
WORK_DIR="${ROOT_DIR}/.work/rootfs"
EXPORT_DIR="${WORK_DIR}/export"

ROOTFS_TAG="${ROOTFS_TAG:-nixbrowser-v86-alpine-rootfs}"
PLATFORM="${PLATFORM:-linux/386}"
EXTRA_MB="${EXTRA_MB:-96}"
MIN_DISK_MB="${MIN_DISK_MB:-512}"
DISK_MB="${DISK_MB:-}"
MKINITFS_FEATURES="${MKINITFS_FEATURES:-base ata scsi ext4}"
USER_APK_PACKAGES="${USER_APK_PACKAGES:-}"
STRIP_TO_BUSYBOX="${STRIP_TO_BUSYBOX:-1}"
PRUNE_ROOTFS="${PRUNE_ROOTFS:-1}"
AUTO_SHRINK="${AUTO_SHRINK:-1}"
SHRINK_PAD_MB="${SHRINK_PAD_MB:-2}"
SHRINK_MIN_MB="${SHRINK_MIN_MB:-0}"
DOCKER_USE_SUDO="${DOCKER_USE_SUDO:-0}"

DISK_IMAGE="${ASSETS_DIR}/alpine-linux.img"
VMLINUX_OUT="${ASSETS_DIR}/vmlinuz"
INITRD_OUT="${ASSETS_DIR}/initrd.img"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

for cmd in docker tar find sort awk du cp truncate mke2fs grep chmod stat rm; do
    need_cmd "$cmd"
done
if [[ "${DOCKER_USE_SUDO}" == "1" ]]; then
    need_cmd sudo
fi

docker_cmd() {
    if [[ "${DOCKER_USE_SUDO}" == "1" ]]; then
        sudo docker "$@"
    else
        docker "$@"
    fi
}

docker_info_err=""
if ! docker_info_err="$(docker_cmd info 2>&1 >/dev/null)"; then
    cat >&2 <<'ERR'
Cannot access Docker daemon.

If your user is not in the docker group, use one of:
  DOCKER_USE_SUDO=1 make build-disk
  DOCKER_USE_SUDO=1 make build

Or fix it permanently:
  sudo usermod -aG docker $USER
  newgrp docker
ERR
    if [[ -n "${docker_info_err}" ]]; then
        echo "" >&2
        echo "Docker error output:" >&2
        echo "${docker_info_err}" >&2
    fi
    exit 1
fi

echo "[1/5] Building rootfs image (${PLATFORM})"
docker_cmd build \
    --platform "${PLATFORM}" \
    --build-arg "MKINITFS_FEATURES=${MKINITFS_FEATURES}" \
    --build-arg "USER_APK_PACKAGES=${USER_APK_PACKAGES}" \
    --build-arg "STRIP_TO_BUSYBOX=${STRIP_TO_BUSYBOX}" \
    -t "${ROOTFS_TAG}" \
    "${ROOTFS_DIR}"

echo "[2/5] Exporting container filesystem"
rm -rf "${EXPORT_DIR}"
mkdir -p "${EXPORT_DIR}" "${ASSETS_DIR}"

cid="$(docker_cmd create --platform "${PLATFORM}" "${ROOTFS_TAG}")"
cleanup() {
    docker_cmd rm -f "${cid}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Device nodes from docker export are not needed and may fail to extract without root.
docker_cmd export "${cid}" | tar -x -C "${EXPORT_DIR}" --exclude='dev/*' --exclude='./dev/*'
mkdir -p "${EXPORT_DIR}/dev" "${EXPORT_DIR}/proc" "${EXPORT_DIR}/sys" "${EXPORT_DIR}/run" "${EXPORT_DIR}/tmp"
chmod 1777 "${EXPORT_DIR}/tmp"

# Some minimal distros include execute-only helper binaries (for example /bin/bbsuid).
# mke2fs -d reads files as the invoking user, so unreadable files must be fixed in staging.
if find "${EXPORT_DIR}" -type f ! -readable -print -quit | grep -q .; then
    echo "Normalizing unreadable files in export tree for mke2fs"
    find "${EXPORT_DIR}" -type f ! -readable -exec chmod u+r {} +
fi

VMLINUX_PATH="$(find "${EXPORT_DIR}/boot" -maxdepth 1 -type f \( -name 'vmlinuz-*' -o -name 'vmlinuz' \) | sort | tail -n 1)"
INITRD_PATH="$(find "${EXPORT_DIR}/boot" -maxdepth 1 -type f \( -name 'initrd.img-*' -o -name 'initrd*' -o -name 'initramfs-*' -o -name 'initramfs*' \) | sort | tail -n 1)"

if [[ -z "${VMLINUX_PATH}" || -z "${INITRD_PATH}" ]]; then
    echo "Unable to find kernel/initrd in ${EXPORT_DIR}/boot" >&2
    exit 1
fi

cp "${VMLINUX_PATH}" "${VMLINUX_OUT}"
cp "${INITRD_PATH}" "${INITRD_OUT}"

if [[ "${PRUNE_ROOTFS}" == "1" ]]; then
    echo "Pruning runtime rootfs content not needed in this VM profile"
    rm -rf \
        "${EXPORT_DIR}/boot" \
        "${EXPORT_DIR}/lib/modules" \
        "${EXPORT_DIR}/lib/firmware" \
        "${EXPORT_DIR}/usr/lib/firmware" \
        "${EXPORT_DIR}/usr/share/man" \
        "${EXPORT_DIR}/usr/share/doc" \
        "${EXPORT_DIR}/usr/share/info" \
        "${EXPORT_DIR}/usr/share/locale" \
        "${EXPORT_DIR}/var/cache/apk"
elif [[ "${PRUNE_ROOTFS}" != "0" ]]; then
    echo "PRUNE_ROOTFS must be 0 or 1 (got: ${PRUNE_ROOTFS})" >&2
    exit 1
fi

echo "Cleaning transient files from export tree"
for dir in tmp var/tmp var/cache var/log; do
    if [[ -d "${EXPORT_DIR}/${dir}" ]]; then
        find "${EXPORT_DIR}/${dir}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    fi
done
mkdir -p "${EXPORT_DIR}/tmp" "${EXPORT_DIR}/var/tmp"
chmod 1777 "${EXPORT_DIR}/tmp" "${EXPORT_DIR}/var/tmp" || true

echo "[3/5] Building ext4 disk image"
rootfs_mb="$(du -sm "${EXPORT_DIR}" | awk '{print $1}')"
if [[ -n "${DISK_MB}" ]]; then
    if ! [[ "${DISK_MB}" =~ ^[0-9]+$ ]] || (( DISK_MB < 64 )); then
        echo "DISK_MB must be an integer >= 64 (got: ${DISK_MB})" >&2
        exit 1
    fi
    planned_disk_mb="${DISK_MB}"
else
    planned_disk_mb="$((rootfs_mb + EXTRA_MB))"
    if (( planned_disk_mb < MIN_DISK_MB )); then
        planned_disk_mb="${MIN_DISK_MB}"
    fi
fi

echo "rootfs size: ${rootfs_mb}MB"
echo "planned disk size: ${planned_disk_mb}MB"

rm -f "${DISK_IMAGE}"
truncate -s "${planned_disk_mb}M" "${DISK_IMAGE}"
mke2fs -q -t ext4 -L rootfs -F -d "${EXPORT_DIR}" "${DISK_IMAGE}"

if [[ "${AUTO_SHRINK}" == "1" ]]; then
    echo "[4/5] Auto-shrinking disk image"
    PAD_MB="${SHRINK_PAD_MB}" MIN_MB="${SHRINK_MIN_MB}" "${ROOT_DIR}/scripts/shrink-image.sh" "${DISK_IMAGE}"
else
    echo "[4/5] Auto-shrinking skipped (AUTO_SHRINK=${AUTO_SHRINK})"
fi

final_disk_bytes="$(stat -c '%s' "${DISK_IMAGE}")"
final_disk_mb="$(((final_disk_bytes + 1048575) / 1048576))"
echo "final disk size: ${final_disk_mb}MB"

echo "[5/5] Writing metadata"
cat > "${ASSETS_DIR}/boot-image-info.txt" <<META
built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
platform=${PLATFORM}
rootfs_tag=${ROOTFS_TAG}
disk_size_mb=${final_disk_mb}
kernel=$(basename "${VMLINUX_PATH}")
initrd=$(basename "${INITRD_PATH}")
META

echo ""
echo "Artifacts generated:"
echo "  ${DISK_IMAGE}"
echo "  ${VMLINUX_OUT}"
echo "  ${INITRD_OUT}"
echo ""
echo "If you change rootfs/Dockerfile or rootfs/overlay/, rerun:"
echo "  make build-disk"
