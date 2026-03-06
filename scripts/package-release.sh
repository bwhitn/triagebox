#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="${ROOT_DIR}/VERSION"
DIST_DIR="${ROOT_DIR}/dist"
INCLUDE_V86_MIN="${INCLUDE_V86_MIN:-1}"
EXPECTED_TAG="${EXPECTED_TAG:-}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-}"
GIT_COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD 2>/dev/null || printf 'unknown')"

if [[ ! -f "${VERSION_FILE}" ]]; then
    echo "Missing VERSION file: ${VERSION_FILE}" >&2
    exit 1
fi

PROJECT_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
if [[ ! "${PROJECT_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must contain MAJOR.MINOR.PATCH (got: ${PROJECT_VERSION})" >&2
    exit 1
fi

TAG_VERSION="v${PROJECT_VERSION}"
if [[ -n "${EXPECTED_TAG}" ]] && [[ "${EXPECTED_TAG}" != "${TAG_VERSION}" ]]; then
    echo "Tag/version mismatch: expected ${TAG_VERSION}, got ${EXPECTED_TAG}" >&2
    exit 1
fi

RELEASE_BASENAME="triagebox-${TAG_VERSION}"
STAGE_DIR="${DIST_DIR}/${RELEASE_BASENAME}"
ARCHIVE_PATH="${DIST_DIR}/${RELEASE_BASENAME}.tar.gz"
SHA256_PATH="${ARCHIVE_PATH}.sha256"
RUNTIME_PUBLIC_DIR="${STAGE_DIR}/public"
RUNTIME_SCRIPTS_DIR="${STAGE_DIR}/scripts"

rm -rf "${STAGE_DIR}" "${ARCHIVE_PATH}" "${SHA256_PATH}"
mkdir -p "${DIST_DIR}"

make -C "${ROOT_DIR}" build

if [[ "${INCLUDE_V86_MIN}" == "1" ]]; then
    make -C "${ROOT_DIR}" build-v86-min
    make -C "${ROOT_DIR}" use-v86-stock
fi

mkdir -p "${RUNTIME_PUBLIC_DIR}" "${RUNTIME_SCRIPTS_DIR}"
rsync -a \
    --exclude 'uploads/*.img' \
    --exclude 'uploads/*.qcow2' \
    --exclude 'uploads/*.iso' \
    "${ROOT_DIR}/public/" "${RUNTIME_PUBLIC_DIR}/"

# Keep only the active v86 asset flavor in release payload to avoid shipping
# duplicate runtime bundles (e.g. v86 and v86-min together).
ACTIVE_V86_FLAVOR="$(sed -n 's/^[[:space:]]*v86AssetFlavor:[[:space:]]*"\([^"]\+\)".*/\1/p' "${RUNTIME_PUBLIC_DIR}/build-config.js" | head -n1)"
if [[ -n "${ACTIVE_V86_FLAVOR}" ]] && [[ -d "${RUNTIME_PUBLIC_DIR}/assets" ]]; then
    while IFS= read -r -d '' candidate; do
        base="$(basename "${candidate}")"
        if [[ "${base}" == "v86"* ]] && [[ "${base}" != "${ACTIVE_V86_FLAVOR}" ]]; then
            rm -rf "${candidate}"
        fi
    done < <(find "${RUNTIME_PUBLIC_DIR}/assets" -maxdepth 1 -mindepth 1 -type d -print0)
fi

# Keep only the configured primary boot disk image under assets/.
ACTIVE_DISK_IMAGE="$(sed -n 's/^[[:space:]]*diskImage:[[:space:]]*"\([^"]\+\)".*/\1/p' "${RUNTIME_PUBLIC_DIR}/vm-config.js" | head -n1)"
if [[ -n "${ACTIVE_DISK_IMAGE}" ]]; then
    ACTIVE_DISK_IMAGE="${ACTIVE_DISK_IMAGE#./}"
fi
if [[ -d "${RUNTIME_PUBLIC_DIR}/assets" ]]; then
    while IFS= read -r -d '' image_file; do
        rel_path="${image_file#${RUNTIME_PUBLIC_DIR}/}"
        base_name="$(basename "${image_file}")"
        if [[ -n "${ACTIVE_DISK_IMAGE}" ]] && [[ "${rel_path}" == "${ACTIVE_DISK_IMAGE}" ]]; then
            continue
        fi
        if [[ "${base_name}" == "initrd.img" ]]; then
            continue
        fi
        rm -f "${image_file}"
    done < <(find "${RUNTIME_PUBLIC_DIR}/assets" -maxdepth 1 -type f \( -name '*.img' -o -name '*.qcow2' -o -name '*.iso' \) -print0)
fi

mkdir -p "${RUNTIME_PUBLIC_DIR}/uploads"
touch "${RUNTIME_PUBLIC_DIR}/uploads/.gitkeep"
install -m 0755 \
    "${ROOT_DIR}/scripts/serve-local.sh" \
    "${ROOT_DIR}/scripts/serve-compressed.py" \
    "${RUNTIME_SCRIPTS_DIR}/"
install -m 0644 "${ROOT_DIR}/VERSION" "${STAGE_DIR}/VERSION"
if [[ -f "${ROOT_DIR}/EMBED_API.md" ]]; then
    install -m 0644 "${ROOT_DIR}/EMBED_API.md" "${STAGE_DIR}/EMBED_API.md"
fi
if [[ -f "${ROOT_DIR}/README.md" ]]; then
    install -m 0644 "${ROOT_DIR}/README.md" "${STAGE_DIR}/README.md"
fi

cat > "${STAGE_DIR}/release-manifest.txt" <<EOF
project=${RELEASE_BASENAME}
version=${PROJECT_VERSION}
tag=${TAG_VERSION}
git_commit=${GIT_COMMIT}
built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
include_v86_min=${INCLUDE_V86_MIN}
EOF

if [[ -n "${RELEASE_NOTES_FILE}" ]] && [[ -f "${RELEASE_NOTES_FILE}" ]]; then
    cp -f "${RELEASE_NOTES_FILE}" "${STAGE_DIR}/RELEASE_NOTES.txt"
fi

tar -C "${DIST_DIR}" -czf "${ARCHIVE_PATH}" "${RELEASE_BASENAME}"
sha256sum "${ARCHIVE_PATH}" > "${SHA256_PATH}"

echo "Created:"
echo "  ${ARCHIVE_PATH}"
echo "  ${SHA256_PATH}"
