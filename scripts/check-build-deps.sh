#!/usr/bin/env bash
set -euo pipefail

missing=()

need_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        missing+=("${cmd}")
    fi
}

need_node_cmd() {
    if command -v node >/dev/null 2>&1; then
        return 0
    fi
    if command -v nodejs >/dev/null 2>&1; then
        return 0
    fi
    missing+=("node (or nodejs)")
}

# Core host tools for this project and Buildroot compilation.
required_cmds=(
    awk
    bc
    bison
    cpio
    curl
    du
    e2fsck
    find
    flex
    gcc
    grep
    gzip
    java
    make
    mke2fs
    nproc
    patch
    perl
    resize2fs
    rsync
    sort
    stat
    tar
    truncate
    unzip
    wc
    python3
)

for cmd in "${required_cmds[@]}"; do
    need_cmd "${cmd}"
done

check_v86_min="${CHECK_V86_MIN:-0}"
if [[ "${check_v86_min}" == "1" ]]; then
    need_cmd git
    need_cmd npm
    need_cmd java
    need_cmd clang
    need_cmd wasm-ld
    need_node_cmd
fi

prefetch_wheels="${PREFETCH_REFINERY_WHEELS:-1}"
require_buildroot_target="${REFINERY_REQUIRE_BUILDROOT_TARGET:-1}"
if [[ "${prefetch_wheels}" == "1" ]] && [[ "${require_buildroot_target}" != "1" ]]; then
    if ! python3 -m pip --version >/dev/null 2>&1; then
        missing+=("python3-pip (python3 -m pip)")
    fi
fi

if ((${#missing[@]} > 0)); then
    echo "Missing build dependencies:" >&2
    for dep in "${missing[@]}"; do
        echo "  - ${dep}" >&2
    done
    echo "" >&2
    echo "Install prerequisites listed in README.md and rerun make." >&2
    exit 1
fi

echo "Build dependency check passed."
