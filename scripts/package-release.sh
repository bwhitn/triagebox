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

RELEASE_BASENAME="nixbrowser-${TAG_VERSION}"
STAGE_DIR="${DIST_DIR}/${RELEASE_BASENAME}"
ARCHIVE_PATH="${DIST_DIR}/${RELEASE_BASENAME}.tar.gz"
SHA256_PATH="${ARCHIVE_PATH}.sha256"

rm -rf "${STAGE_DIR}" "${ARCHIVE_PATH}" "${SHA256_PATH}"
mkdir -p "${DIST_DIR}"

make -C "${ROOT_DIR}" build

if [[ "${INCLUDE_V86_MIN}" == "1" ]]; then
    make -C "${ROOT_DIR}" build-v86-min
    make -C "${ROOT_DIR}" use-v86-stock
fi

mkdir -p "${STAGE_DIR}"
rsync -a \
    --exclude '.git/' \
    --exclude '.github/' \
    --exclude '.work/' \
    --exclude 'dist/' \
    --exclude '.venv/' \
    --exclude '__pycache__/' \
    --exclude '*.pyc' \
    "${ROOT_DIR}/" "${STAGE_DIR}/"

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

