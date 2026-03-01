#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="${ROOT_DIR}/VERSION"

usage() {
    echo "Usage: $0 <version>" >&2
    echo "Example: $0 v0.0.1" >&2
    exit 1
}

[[ $# -eq 1 ]] || usage

raw_version="$1"
version=""

if [[ "${raw_version}" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    version="${BASH_REMATCH[1]}"
elif [[ "${raw_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    version="${raw_version}"
else
    echo "Version must match vMAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH (got: ${raw_version})" >&2
    exit 1
fi

printf '%s\n' "${version}" > "${VERSION_FILE}"
echo "Updated project version to v${version}"

