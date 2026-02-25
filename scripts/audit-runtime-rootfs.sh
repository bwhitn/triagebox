#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${ROOT_DIR}/.work/buildroot/output/target"
ROOTFS_TAR="${ROOT_DIR}/.work/buildroot/output/images/rootfs.tar"

scan_mode=""

if [[ -f "${ROOTFS_TAR}" ]]; then
    scan_mode="tar"
elif [[ -d "${TARGET_DIR}" ]] && find "${TARGET_DIR}" -mindepth 1 \( -type f -o -type l \) -print -quit | grep -q .; then
    scan_mode="target"
else
    echo "No rootfs artifact found to audit." >&2
    echo "Expected one of:" >&2
    echo "  - ${ROOTFS_TAR}" >&2
    echo "  - non-empty ${TARGET_DIR}" >&2
    echo "" >&2
    echo "Build first, then rerun this script." >&2
    exit 2
fi

list_paths() {
    if [[ "${scan_mode}" == "tar" ]]; then
        tar -tf "${ROOTFS_TAR}" | sed 's#^\./##'
    else
        (
            cd "${TARGET_DIR}"
            find . -type f -o -type l | sed 's#^\./##'
        )
    fi
}

is_complete_rootfs() {
    if [[ "${scan_mode}" == "tar" ]]; then
        tar -tf "${ROOTFS_TAR}" | sed 's#^\./##' | grep -Eq '^(bin/busybox|bin/sh|usr/bin/python|usr/bin/python3)$'
    else
        [[ -x "${TARGET_DIR}/bin/busybox" ]] || [[ -x "${TARGET_DIR}/bin/sh" ]] || \
            [[ -x "${TARGET_DIR}/usr/bin/python" ]] || [[ -x "${TARGET_DIR}/usr/bin/python3" ]]
    fi
}

echo "Audit source: ${scan_mode}"
if [[ "${scan_mode}" == "tar" ]]; then
    echo "Path: ${ROOTFS_TAR}"
else
    echo "Path: ${TARGET_DIR}"
fi
echo ""

if ! is_complete_rootfs; then
    echo "The selected rootfs appears incomplete (no shell/runtime binaries found)." >&2
    if [[ -f "${TARGET_DIR}/THIS_IS_NOT_YOUR_ROOT_FILESYSTEM" ]]; then
        echo "It looks like a Buildroot placeholder target directory." >&2
    fi
    echo "Run this audit after a successful Buildroot build/export." >&2
    exit 3
fi

tool_regex='^((usr/)?(bin|sbin)/(gcc|cc|g\+\+|cpp|ld|as|ar|nm|ranlib|objdump|objcopy|readelf|make|cmake|ninja|meson|pkg-config|pkgconf|python3-config|pip|pip3))$'
pybuild_regex='site-packages/(pip|setuptools|wheel|installer|build|pyproject_hooks|hatch|scikit_build|scikit_build_core)(/|$)'
devmeta_regex='^(usr/include/|usr/lib/pkgconfig/|usr/share/pkgconfig/)'

mapfile -t tool_hits < <(list_paths | grep -E "${tool_regex}" | sort -u || true)
mapfile -t pybuild_hits < <(list_paths | grep -E "${pybuild_regex}" | sort -u || true)
mapfile -t devmeta_hits < <(list_paths | grep -E "${devmeta_regex}" | sort -u || true)

echo "Potential build-tool binaries in runtime:"
if ((${#tool_hits[@]} == 0)); then
    echo "  none"
else
    for p in "${tool_hits[@]}"; do
        echo "  ${p}"
    done
fi
echo ""

echo "Potential Python build-only packages in runtime:"
if ((${#pybuild_hits[@]} == 0)); then
    echo "  none"
else
    for p in "${pybuild_hits[@]}"; do
        echo "  ${p}"
    done
fi
echo ""

echo "Development metadata paths in runtime:"
if ((${#devmeta_hits[@]} == 0)); then
    echo "  none"
else
    for p in "${devmeta_hits[@]}"; do
        echo "  ${p}"
    done
fi
echo ""

if ((${#tool_hits[@]} == 0 && ${#pybuild_hits[@]} == 0 && ${#devmeta_hits[@]} == 0)); then
    echo "Result: OK (no obvious build-time residues detected)"
else
    echo "Result: REVIEW (one or more potential build-time residues detected)"
fi
