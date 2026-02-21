#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
ASSETS_DIR="${ROOT_DIR}/public/assets"
WORK_DIR="${ROOT_DIR}/.work/rootfs"
EXPORT_DIR="${WORK_DIR}/export"

ROOTFS_TAG="${ROOTFS_TAG:-nixbrowser-v86-trixie-rootfs}"
PLATFORM="${PLATFORM:-linux/386}"
EXTRA_MB="${EXTRA_MB:-512}"
MIN_DISK_MB="${MIN_DISK_MB:-1024}"
DOCKER_USE_SUDO="${DOCKER_USE_SUDO:-0}"

DISK_IMAGE="${ASSETS_DIR}/debian-trixie.img"
VMLINUX_OUT="${ASSETS_DIR}/vmlinuz"
INITRD_OUT="${ASSETS_DIR}/initrd.img"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

for cmd in docker tar find sort awk du cp truncate mke2fs; do
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

if ! docker_cmd info >/dev/null 2>&1; then
    cat >&2 <<'ERR'
Cannot access Docker daemon.

If your user is not in the docker group, use one of:
  DOCKER_USE_SUDO=1 make build-disk
  DOCKER_USE_SUDO=1 make build

Or fix it permanently:
  sudo usermod -aG docker $USER
  newgrp docker
ERR
    exit 1
fi

echo "[1/4] Building rootfs image (${PLATFORM})"
docker_cmd build --platform "${PLATFORM}" -t "${ROOTFS_TAG}" "${ROOTFS_DIR}"

echo "[2/4] Exporting container filesystem"
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

VMLINUX_PATH="$(find "${EXPORT_DIR}/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | sort | tail -n 1)"
INITRD_PATH="$(find "${EXPORT_DIR}/boot" -maxdepth 1 -type f -name 'initrd.img-*' | sort | tail -n 1)"

if [[ -z "${VMLINUX_PATH}" || -z "${INITRD_PATH}" ]]; then
    echo "Unable to find kernel/initrd in ${EXPORT_DIR}/boot" >&2
    exit 1
fi

cp "${VMLINUX_PATH}" "${VMLINUX_OUT}"
cp "${INITRD_PATH}" "${INITRD_OUT}"

echo "[3/4] Building ext4 disk image"
rootfs_mb="$(du -sm "${EXPORT_DIR}" | awk '{print $1}')"
disk_mb="$((rootfs_mb + EXTRA_MB))"
if (( disk_mb < MIN_DISK_MB )); then
    disk_mb="${MIN_DISK_MB}"
fi

rm -f "${DISK_IMAGE}"
truncate -s "${disk_mb}M" "${DISK_IMAGE}"
mke2fs -q -t ext4 -L rootfs -F -d "${EXPORT_DIR}" "${DISK_IMAGE}"

echo "[4/4] Writing metadata"
cat > "${ASSETS_DIR}/boot-image-info.txt" <<META
built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
platform=${PLATFORM}
rootfs_tag=${ROOTFS_TAG}
disk_size_mb=${disk_mb}
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
