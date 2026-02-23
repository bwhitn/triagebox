#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="${ROOT_DIR}/public/assets"
WORK_DIR="${ROOT_DIR}/.work/buildroot"
SRC_PARENT="${WORK_DIR}/src"
OUT_DIR="${WORK_DIR}/output"
DL_DIR="${WORK_DIR}/dl"
EXPORT_DIR="${WORK_DIR}/export"
OVERLAY_DIR="${ROOT_DIR}/buildroot/overlay"
BR2_EXTERNAL_DIR="${ROOT_DIR}/buildroot-external"

BUILDROOT_VERSION="${BUILDROOT_VERSION:-2025.11.1}"
BUILDROOT_ARCHIVE_URL="${BUILDROOT_ARCHIVE_URL:-https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz}"
BUILDROOT_ARCHIVE="${WORK_DIR}/buildroot-${BUILDROOT_VERSION}.tar.xz"
BUILDROOT_SRC="${SRC_PARENT}/buildroot-${BUILDROOT_VERSION}"
BUILDROOT_DEFCONFIG="${BUILDROOT_DEFCONFIG:-qemu_x86_defconfig}"
BUILDROOT_JOBS="${BUILDROOT_JOBS:-$(nproc)}"
BUILDROOT_PRIMARY_SITE="${BUILDROOT_PRIMARY_SITE:-https://sources.buildroot.net}"
BUILDROOT_PRIMARY_SITE_ONLY="${BUILDROOT_PRIMARY_SITE_ONLY:-0}"
BUILDROOT_GLOBAL_PATCH_DIR="${BUILDROOT_GLOBAL_PATCH_DIR:-${ROOT_DIR}/buildroot/patches}"
BINARY_REFINERY_VERSION="${BINARY_REFINERY_VERSION:-0.9.26}"
PYTHON_LIEF_VERSION="${PYTHON_LIEF_VERSION:-0.17.3}"
BUILD_PROFILE="${BUILD_PROFILE:-optimized}"
PREFETCH_DOWNLOADS="${PREFETCH_DOWNLOADS:-1}"
PREFETCH_REFINERY_WHEELS="${PREFETCH_REFINERY_WHEELS:-1}"
REFINERY_WHEELHOUSE_DIR="${REFINERY_WHEELHOUSE_DIR:-${DL_DIR}/python-binary-refinery-wheelhouse}"
REFINERY_WHEEL_PLATFORM_PRIMARY="${REFINERY_WHEEL_PLATFORM_PRIMARY:-manylinux_2_28_i686}"
REFINERY_WHEEL_PLATFORM_FALLBACK="${REFINERY_WHEEL_PLATFORM_FALLBACK:-manylinux2014_i686}"
REFINERY_WHEEL_STRICT="${REFINERY_WHEEL_STRICT:-1}"
REFINERY_SDIST_FALLBACK="${REFINERY_SDIST_FALLBACK:-1}"
REFINERY_SDIST_BUILD_JOBS="${REFINERY_SDIST_BUILD_JOBS:-${BUILDROOT_JOBS}}"
REFINERY_SDIST_SKIP_PACKAGES="${REFINERY_SDIST_SKIP_PACKAGES:-pikepdf icicle-emu speakeasy-emulator-refined lief pyppmd}"
REFINERY_REQUIRE_BUILDROOT_TARGET="${REFINERY_REQUIRE_BUILDROOT_TARGET:-1}"
REFINERY_MISSING_WHEELS_REPORT="${REFINERY_MISSING_WHEELS_REPORT:-${ASSETS_DIR}/binary-refinery-missing-wheels.txt}"
REFINERY_BUILDROOT_PROVIDED_REPORT="${REFINERY_BUILDROOT_PROVIDED_REPORT:-${ASSETS_DIR}/binary-refinery-buildroot-provided.txt}"
REFINERY_MISSING_BUILDROOT_REPORT="${REFINERY_MISSING_BUILDROOT_REPORT:-${ASSETS_DIR}/binary-refinery-missing-buildroot-packages.txt}"
BUILD_LEGAL_INFO="${BUILD_LEGAL_INFO:-1}"
LEGAL_INFO_ARCHIVE="${LEGAL_INFO_ARCHIVE:-${ASSETS_DIR}/buildroot-legal-info.tar.gz}"

EXTRA_MB="${EXTRA_MB:-32}"
MIN_DISK_MB="${MIN_DISK_MB:-64}"
DISK_MB="${DISK_MB:-}"
AUTO_SHRINK="${AUTO_SHRINK:-1}"
SHRINK_PAD_MB="${SHRINK_PAD_MB:-2}"
SHRINK_MIN_MB="${SHRINK_MIN_MB:-0}"

DISK_IMAGE="${ASSETS_DIR}/buildroot-linux.img"
VMLINUX_OUT="${ASSETS_DIR}/vmlinuz"
INITRD_OUT="${ASSETS_DIR}/initrd.img"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

for cmd in curl tar make nproc find sort awk du cp truncate mke2fs gzip cpio stat rm mkdir date mktemp chmod grep dirname wc tr; do
    need_cmd "$cmd"
done

mkdir -p "${ASSETS_DIR}" "${WORK_DIR}" "${SRC_PARENT}" "${DL_DIR}"
rm -f "${REFINERY_MISSING_WHEELS_REPORT}"
rm -f "${REFINERY_BUILDROOT_PROVIDED_REPORT}"
rm -f "${REFINERY_MISSING_BUILDROOT_REPORT}"
if [[ -z "${REFINERY_WHEEL_PLATFORM_PRIMARY}" ]] || [[ -z "${REFINERY_WHEEL_PLATFORM_FALLBACK}" ]]; then
    echo "REFINERY_WHEEL_PLATFORM_PRIMARY and REFINERY_WHEEL_PLATFORM_FALLBACK must be non-empty" >&2
    exit 1
fi
if [[ "${REFINERY_REQUIRE_BUILDROOT_TARGET}" != "0" ]] && [[ "${REFINERY_REQUIRE_BUILDROOT_TARGET}" != "1" ]]; then
    echo "REFINERY_REQUIRE_BUILDROOT_TARGET must be 0 or 1 (got: ${REFINERY_REQUIRE_BUILDROOT_TARGET})" >&2
    exit 1
fi
if ! [[ "${REFINERY_SDIST_BUILD_JOBS}" =~ ^[0-9]+$ ]] || (( REFINERY_SDIST_BUILD_JOBS < 1 )); then
    echo "REFINERY_SDIST_BUILD_JOBS must be an integer >= 1 (got: ${REFINERY_SDIST_BUILD_JOBS})" >&2
    exit 1
fi
if [[ ! -d "${OVERLAY_DIR}" ]]; then
    echo "Missing Buildroot overlay directory: ${OVERLAY_DIR}" >&2
    exit 1
fi
if [[ ! -d "${BR2_EXTERNAL_DIR}" ]]; then
    echo "Missing Buildroot external directory: ${BR2_EXTERNAL_DIR}" >&2
    exit 1
fi
if [[ -n "${BUILDROOT_GLOBAL_PATCH_DIR}" ]] && [[ ! -d "${BUILDROOT_GLOBAL_PATCH_DIR}" ]]; then
    echo "BUILDROOT_GLOBAL_PATCH_DIR does not exist: ${BUILDROOT_GLOBAL_PATCH_DIR}" >&2
    exit 1
fi

if [[ ! -d "${BUILDROOT_SRC}" ]]; then
    echo "[1/8] Downloading Buildroot ${BUILDROOT_VERSION}"
    if [[ ! -f "${BUILDROOT_ARCHIVE}" ]]; then
        curl -fL "${BUILDROOT_ARCHIVE_URL}" -o "${BUILDROOT_ARCHIVE}"
    fi
    tar -xf "${BUILDROOT_ARCHIVE}" -C "${SRC_PARENT}"
fi

refinery_requirements_source="${BR2_EXTERNAL_DIR}/package/python-binary-refinery/requirements-all.txt"
refinery_pip_requirements="${WORK_DIR}/refinery-pip-requirements.txt"
refinery_buildroot_requirements="${WORK_DIR}/refinery-buildroot-provided.txt"
refinery_buildroot_symbols="${WORK_DIR}/refinery-buildroot-symbols.txt"
refinery_buildroot_map="${WORK_DIR}/refinery-buildroot-requirement-symbol-map.tsv"
refinery_buildroot_required_missing="${WORK_DIR}/refinery-buildroot-required-missing.txt"

if [[ ! -f "${refinery_requirements_source}" ]]; then
    echo "Missing binary-refinery requirements file: ${refinery_requirements_source}" >&2
    exit 1
fi

: > "${refinery_pip_requirements}"
: > "${refinery_buildroot_requirements}"
: > "${refinery_buildroot_symbols}"
: > "${refinery_buildroot_map}"
: > "${refinery_buildroot_required_missing}"

normalize_requirement_name() {
    local requirement_line="$1"
    local req_name

    req_name="${requirement_line%%;*}"
    req_name="${req_name%%[*}"
    req_name="${req_name//[[:space:]]/}"
    req_name="${req_name%%<*}"
    req_name="${req_name%%>*}"
    req_name="${req_name%%=*}"
    req_name="${req_name%%!*}"
    req_name="${req_name%%~*}"
    req_name="${req_name,,}"
    printf '%s' "$(printf '%s' "${req_name}" | tr -cd '[:alnum:]')"
}

normalize_package_base_name() {
    local package_base="$1"
    printf '%s' "$(printf '%s' "${package_base,,}" | tr -cd '[:alnum:]')"
}

append_unique_requirement_line() {
    local line="$1"
    local file="$2"
    if ! grep -Fxq "${line}" "${file}"; then
        printf '%s\n' "${line}" >> "${file}"
    fi
}

declare -A buildroot_python_symbol_by_norm=()
register_python_package_symbol() {
    local package_name="$1"
    local package_base="${package_name#python-}"
    local package_norm
    local package_symbol
    local package_norm_without_python_prefix=""

    package_norm="$(normalize_package_base_name "${package_base}")"
    if [[ -z "${package_norm}" ]]; then
        return
    fi
    package_symbol="BR2_PACKAGE_$(printf '%s' "${package_name}" | tr '[:lower:]-.' '[:upper:]__')"
    if [[ -z "${buildroot_python_symbol_by_norm[$package_norm]:-}" ]]; then
        buildroot_python_symbol_by_norm["${package_norm}"]="${package_symbol}"
    fi

    if [[ "${package_norm}" == python* ]] && (( ${#package_norm} > 6 )); then
        package_norm_without_python_prefix="${package_norm#python}"
        if [[ -n "${package_norm_without_python_prefix}" ]] && [[ -z "${buildroot_python_symbol_by_norm[$package_norm_without_python_prefix]:-}" ]]; then
            buildroot_python_symbol_by_norm["${package_norm_without_python_prefix}"]="${package_symbol}"
        fi
    fi
}

for package_dir in "${BUILDROOT_SRC}"/package/python-*; do
    [[ -d "${package_dir}" ]] || continue
    [[ -f "${package_dir}/Config.in" ]] || continue
    register_python_package_symbol "$(basename "${package_dir}")"
done
for package_dir in "${BR2_EXTERNAL_DIR}"/package/python-*; do
    [[ -d "${package_dir}" ]] || continue
    [[ -f "${package_dir}/Config.in" ]] || continue
    register_python_package_symbol "$(basename "${package_dir}")"
done

declare -A refinery_buildroot_seen_symbols=()
declare -A refinery_requirement_symbol_alias=(
    [pefile]="BR2_PACKAGE_PYTHON_PEFILE_TARGET"
    [wheel]="BR2_PACKAGE_PYTHON_WHEEL_TARGET"
)
resolve_refinery_requirement() {
    local requirement_line="$1"
    local req_norm
    local req_norm_no_python_prefix=""
    local req_symbol

    req_norm="$(normalize_requirement_name "${requirement_line}")"
    if [[ "${req_norm}" == python* ]] && (( ${#req_norm} > 6 )); then
        req_norm_no_python_prefix="${req_norm#python}"
    fi

    req_symbol="${refinery_requirement_symbol_alias[$req_norm]:-}"
    if [[ -z "${req_symbol}" ]] && [[ -n "${req_norm_no_python_prefix}" ]]; then
        req_symbol="${refinery_requirement_symbol_alias[$req_norm_no_python_prefix]:-}"
    fi

    if [[ -z "${req_symbol}" ]] && [[ -n "${req_norm}" ]] && [[ -n "${buildroot_python_symbol_by_norm[$req_norm]:-}" ]]; then
        req_symbol="${buildroot_python_symbol_by_norm[$req_norm]}"
    elif [[ -z "${req_symbol}" ]] && [[ -n "${req_norm_no_python_prefix}" ]] && [[ -n "${buildroot_python_symbol_by_norm[$req_norm_no_python_prefix]:-}" ]]; then
        req_symbol="${buildroot_python_symbol_by_norm[$req_norm_no_python_prefix]}"
    fi

    if [[ -n "${req_symbol}" ]]; then
        append_unique_requirement_line "${requirement_line}" "${refinery_buildroot_requirements}"
        printf '%s\t%s\n' "${requirement_line}" "${req_symbol}" >> "${refinery_buildroot_map}"
        if [[ -z "${refinery_buildroot_seen_symbols[$req_symbol]:-}" ]]; then
            refinery_buildroot_seen_symbols["${req_symbol}"]=1
            printf '%s\n' "${req_symbol}=y" >> "${refinery_buildroot_symbols}"
        fi
    else
        if [[ "${REFINERY_REQUIRE_BUILDROOT_TARGET}" == "1" ]]; then
            append_unique_requirement_line "${requirement_line}" "${refinery_buildroot_required_missing}"
        else
            append_unique_requirement_line "${requirement_line}" "${refinery_pip_requirements}"
        fi
    fi
}

while IFS= read -r requirement_line; do
    [[ -z "${requirement_line}" ]] && continue
    [[ "${requirement_line:0:1}" == "#" ]] && continue
    resolve_refinery_requirement "${requirement_line}"
done < "${refinery_requirements_source}"

resolve_refinery_requirement "lief==${PYTHON_LIEF_VERSION}"

echo "[2/8] Configuring Buildroot (${BUILDROOT_DEFCONFIG})"
rm -rf "${OUT_DIR}"
make -C "${BUILDROOT_SRC}" \
    O="${OUT_DIR}" \
    BR2_DL_DIR="${DL_DIR}" \
    BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" \
    PYTHON_BINARY_REFINERY_VERSION="${BINARY_REFINERY_VERSION}" \
    PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR="${REFINERY_WHEELHOUSE_DIR}" \
    PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_PRIMARY="${REFINERY_WHEEL_PLATFORM_PRIMARY}" \
    PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_FALLBACK="${REFINERY_WHEEL_PLATFORM_FALLBACK}" \
    PYTHON_BINARY_REFINERY_REQUIRE_PREFETCH=0 \
    PYTHON_LIEF_VERSION="${PYTHON_LIEF_VERSION}" \
    "${BUILDROOT_DEFCONFIG}"

linux_hash_file="${BUILDROOT_SRC}/linux/linux.hash"
adjusted_linux_kernel_version=""
disable_force_hashes="0"
if [[ -f "${linux_hash_file}" ]] && grep -q '^BR2_DOWNLOAD_FORCE_CHECK_HASHES=y$' "${OUT_DIR}/.config"; then
    configured_linux_kernel_version="$(sed -n 's/^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="\(.*\)"$/\1/p' "${OUT_DIR}/.config" | head -n1)"
    if [[ "${configured_linux_kernel_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if ! grep -Eq "[[:space:]]linux-${configured_linux_kernel_version}\\.tar\\.xz$" "${linux_hash_file}"; then
            configured_linux_kernel_series="${configured_linux_kernel_version%.*}"
            adjusted_linux_kernel_version="$(
                awk '/linux-[0-9]+\.[0-9]+\.[0-9]+\.tar\.xz$/ {print $NF}' "${linux_hash_file}" \
                    | sed -e 's/^linux-//' -e 's/\.tar\.xz$//' \
                    | awk -v series="${configured_linux_kernel_series}" '$0 ~ ("^" series "\\.[0-9]+$")' \
                    | sort -V \
                    | tail -n1
            )"
            if [[ -n "${adjusted_linux_kernel_version}" ]] && [[ "${adjusted_linux_kernel_version}" != "${configured_linux_kernel_version}" ]]; then
                echo "Adjusting kernel version for hash compatibility: ${configured_linux_kernel_version} -> ${adjusted_linux_kernel_version}"
            elif [[ -z "${adjusted_linux_kernel_version}" ]]; then
                echo "No hashed linux tarball found for kernel series ${configured_linux_kernel_series}; disabling BR2_DOWNLOAD_FORCE_CHECK_HASHES." >&2
                disable_force_hashes="1"
            fi
        fi
    fi
fi

primary_site="${BUILDROOT_PRIMARY_SITE:-}"
primary_site_only="${BUILDROOT_PRIMARY_SITE_ONLY:-0}"
case "${BUILD_PROFILE}" in
    optimized)
        optimization_config=$'BR2_OPTIMIZE_3=y\nBR2_ENABLE_LTO=y'
        ;;
    fast)
        optimization_config=$'BR2_OPTIMIZE_0=y\n# BR2_ENABLE_LTO is not set'
        ;;
    *)
        echo "BUILD_PROFILE must be 'optimized' or 'fast' (got: ${BUILD_PROFILE})" >&2
        exit 1
        ;;
esac
cat >> "${OUT_DIR}/.config" <<EOF
BR2_ROOTFS_OVERLAY="${OVERLAY_DIR}"
BR2_TARGET_ROOTFS_TAR=y
BR2_TARGET_ROOTFS_CPIO=y
BR2_x86_pentium_m=y
BR2_GCC_TARGET_ARCH="pentium-m"
BR2_TOOLCHAIN_BUILDROOT_CXX=y
BR2_INSTALL_LIBSTDCPP=y
BR2_PACKAGE_PYTHON3=y
BR2_PACKAGE_PYTHON_BINARY_REFINERY=y
BR2_TARGET_GENERIC_GETTY_PORT="ttyS0"
EOF
if [[ -n "${adjusted_linux_kernel_version}" ]]; then
    cat >> "${OUT_DIR}/.config" <<EOF
BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="${adjusted_linux_kernel_version}"
BR2_LINUX_KERNEL_VERSION="${adjusted_linux_kernel_version}"
EOF
fi
if [[ "${disable_force_hashes}" == "1" ]]; then
    cat >> "${OUT_DIR}/.config" <<EOF
# BR2_DOWNLOAD_FORCE_CHECK_HASHES is not set
EOF
fi
printf '%s\n' "${optimization_config}" >> "${OUT_DIR}/.config"
if [[ -s "${refinery_buildroot_symbols}" ]]; then
    cat "${refinery_buildroot_symbols}" >> "${OUT_DIR}/.config"
fi
if [[ -n "${primary_site}" ]]; then
    cat >> "${OUT_DIR}/.config" <<EOF
BR2_PRIMARY_SITE="${primary_site}"
EOF
    if [[ "${primary_site_only}" == "1" ]]; then
        cat >> "${OUT_DIR}/.config" <<EOF
BR2_PRIMARY_SITE_ONLY=y
EOF
    fi
fi
if [[ -n "${BUILDROOT_GLOBAL_PATCH_DIR}" ]]; then
    cat >> "${OUT_DIR}/.config" <<EOF
BR2_GLOBAL_PATCH_DIR="${BUILDROOT_GLOBAL_PATCH_DIR}"
EOF
fi
make -C "${BUILDROOT_SRC}" \
    O="${OUT_DIR}" \
    BR2_DL_DIR="${DL_DIR}" \
    BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" \
    PYTHON_BINARY_REFINERY_VERSION="${BINARY_REFINERY_VERSION}" \
    PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR="${REFINERY_WHEELHOUSE_DIR}" \
    PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_PRIMARY="${REFINERY_WHEEL_PLATFORM_PRIMARY}" \
    PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_FALLBACK="${REFINERY_WHEEL_PLATFORM_FALLBACK}" \
    PYTHON_BINARY_REFINERY_REQUIRE_PREFETCH=0 \
    PYTHON_LIEF_VERSION="${PYTHON_LIEF_VERSION}" \
    olddefconfig

refinery_buildroot_requirements_active="${WORK_DIR}/refinery-buildroot-provided-active.txt"
: > "${refinery_buildroot_requirements_active}"
if [[ -s "${refinery_buildroot_map}" ]]; then
    while IFS=$'\t' read -r requirement_line requirement_symbol; do
        [[ -z "${requirement_line}" ]] && continue
        [[ -z "${requirement_symbol}" ]] && continue
        if grep -q "^${requirement_symbol}=y$" "${OUT_DIR}/.config"; then
            append_unique_requirement_line "${requirement_line}" "${refinery_buildroot_requirements_active}"
        else
            if [[ "${REFINERY_REQUIRE_BUILDROOT_TARGET}" == "1" ]]; then
                append_unique_requirement_line "${requirement_line}" "${refinery_buildroot_required_missing}"
            else
                append_unique_requirement_line "${requirement_line}" "${refinery_pip_requirements}"
            fi
        fi
    done < "${refinery_buildroot_map}"
fi
mv "${refinery_buildroot_requirements_active}" "${refinery_buildroot_requirements}"
if [[ -s "${refinery_buildroot_requirements}" ]]; then
    cp "${refinery_buildroot_requirements}" "${REFINERY_BUILDROOT_PROVIDED_REPORT}"
else
    rm -f "${REFINERY_BUILDROOT_PROVIDED_REPORT}"
fi
if [[ "${REFINERY_REQUIRE_BUILDROOT_TARGET}" == "1" ]]; then
    if [[ -s "${refinery_buildroot_required_missing}" ]]; then
        sort -u "${refinery_buildroot_required_missing}" -o "${refinery_buildroot_required_missing}"
        cp "${refinery_buildroot_required_missing}" "${REFINERY_MISSING_BUILDROOT_REPORT}"
        missing_buildroot_count="$(wc -l < "${refinery_buildroot_required_missing}" | awk '{print $1}')"
        echo "Missing Buildroot target package coverage for ${missing_buildroot_count} binary-refinery optional requirement(s)." >&2
        echo "Missing requirements:" >&2
        sed 's/^/  - /' "${refinery_buildroot_required_missing}" >&2
        echo "See: ${REFINERY_MISSING_BUILDROOT_REPORT}" >&2
        echo "Create Buildroot packages for these requirements or set REFINERY_REQUIRE_BUILDROOT_TARGET=0 to allow pip wheel resolution." >&2
        exit 1
    fi
    rm -f "${REFINERY_MISSING_BUILDROOT_REPORT}"
fi

require_prefetched_wheels=0
if [[ "${PREFETCH_DOWNLOADS}" == "1" ]]; then
    echo "[3/8] Prefetching Buildroot sources"
    make -C "${BUILDROOT_SRC}" \
        O="${OUT_DIR}" \
        BR2_DL_DIR="${DL_DIR}" \
        BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" \
        PYTHON_BINARY_REFINERY_VERSION="${BINARY_REFINERY_VERSION}" \
        PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR="${REFINERY_WHEELHOUSE_DIR}" \
        PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_PRIMARY="${REFINERY_WHEEL_PLATFORM_PRIMARY}" \
        PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_FALLBACK="${REFINERY_WHEEL_PLATFORM_FALLBACK}" \
        PYTHON_BINARY_REFINERY_REQUIRE_PREFETCH=0 \
        PYTHON_LIEF_VERSION="${PYTHON_LIEF_VERSION}" \
        source

    if [[ "${REFINERY_REQUIRE_BUILDROOT_TARGET}" == "1" ]]; then
        echo "Skipping binary-refinery wheel prefetch (REFINERY_REQUIRE_BUILDROOT_TARGET=1)"
        rm -rf "${REFINERY_WHEELHOUSE_DIR}"
        mkdir -p "${REFINERY_WHEELHOUSE_DIR}"
        : > "${REFINERY_WHEELHOUSE_DIR}/requirements-resolved.txt"
        rm -f "${REFINERY_WHEELHOUSE_DIR}/requirements-missing.txt"
        require_prefetched_wheels=1
    elif [[ "${PREFETCH_REFINERY_WHEELS}" == "1" ]]; then
        if ! python3 -m pip --version >/dev/null 2>&1; then
            echo "python3 -m pip is required for PREFETCH_REFINERY_WHEELS=1" >&2
            echo "Install python3-pip or run with PREFETCH_REFINERY_WHEELS=0" >&2
            exit 1
        fi
        requirements_src="${refinery_pip_requirements}"
        if [[ ! -f "${requirements_src}" ]]; then
            echo "Missing binary-refinery requirements file: ${requirements_src}" >&2
            exit 1
        fi
        python3_version_major="$(awk -F ' = ' '/^PYTHON3_VERSION_MAJOR = / {print $2; exit}' "${BUILDROOT_SRC}/package/python3/python3.mk")"
        if [[ -z "${python3_version_major}" ]]; then
            echo "Could not determine PYTHON3_VERSION_MAJOR from Buildroot python3.mk" >&2
            exit 1
        fi
        python3_tag="cp${python3_version_major//./}"
        python3_compact="${python3_version_major//./}"
        requirements_tmp="${WORK_DIR}/prefetch-requirements-all.txt"
        resolved_tmp="${WORK_DIR}/prefetch-requirements-resolved.txt"
        missing_tmp="${WORK_DIR}/prefetch-requirements-missing.txt"
        sdist_dl_dir="${WORK_DIR}/prefetch-sdist-dl"
        sdist_wheel_dir="${WORK_DIR}/prefetch-sdist-wheel"
        declare -A refinery_sdist_skip=()
        if [[ -n "${REFINERY_SDIST_SKIP_PACKAGES}" ]]; then
            for skip_pkg in ${REFINERY_SDIST_SKIP_PACKAGES}; do
                skip_norm="$(normalize_requirement_name "${skip_pkg}")"
                [[ -n "${skip_norm}" ]] && refinery_sdist_skip["${skip_norm}"]=1
            done
        fi
        cp "${requirements_src}" "${requirements_tmp}"
        mkdir -p "${REFINERY_WHEELHOUSE_DIR}"
        : > "${resolved_tmp}"
        : > "${missing_tmp}"
        rm -rf "${sdist_dl_dir}" "${sdist_wheel_dir}"
        mkdir -p "${sdist_dl_dir}" "${sdist_wheel_dir}"
        echo "Prefetching binary-refinery wheel dependencies into ${REFINERY_WHEELHOUSE_DIR}"
        while IFS= read -r requirement; do
            [[ -z "${requirement}" ]] && continue
            [[ "${requirement:0:1}" == "#" ]] && continue
            echo "  - ${requirement}"
            requirement_norm="$(normalize_requirement_name "${requirement}")"
            skip_sdist_for_req=0
            if [[ -n "${requirement_norm}" ]] && [[ -n "${refinery_sdist_skip[$requirement_norm]:-}" ]]; then
                skip_sdist_for_req=1
            fi
            if PIP_DISABLE_PIP_VERSION_CHECK=1 \
                PIP_NO_CACHE_DIR=1 \
                python3 -m pip download \
                    --only-binary=:all: \
                    --platform "${REFINERY_WHEEL_PLATFORM_PRIMARY}" \
                    --platform "${REFINERY_WHEEL_PLATFORM_FALLBACK}" \
                    --implementation cp \
                    --python-version "${python3_compact}" \
                    --abi "${python3_tag}" \
                    --dest "${REFINERY_WHEELHOUSE_DIR}" \
                    "${requirement}"
            then
                printf '%s\n' "${requirement}" >> "${resolved_tmp}"
            else
                if PIP_DISABLE_PIP_VERSION_CHECK=1 \
                    PIP_NO_CACHE_DIR=1 \
                    python3 -m pip download \
                        --only-binary=:all: \
                        --no-deps \
                        --platform "${REFINERY_WHEEL_PLATFORM_PRIMARY}" \
                        --platform "${REFINERY_WHEEL_PLATFORM_FALLBACK}" \
                        --implementation cp \
                        --python-version "${python3_compact}" \
                        --abi "${python3_tag}" \
                        --dest "${REFINERY_WHEELHOUSE_DIR}" \
                        "${requirement}"
                then
                    printf '%s\n' "${requirement}" >> "${resolved_tmp}"
                elif [[ "${REFINERY_SDIST_FALLBACK}" == "1" ]] && [[ "${skip_sdist_for_req}" == "0" ]]; then
                    rm -rf "${sdist_dl_dir}"/* "${sdist_wheel_dir}"/*
                    if PIP_DISABLE_PIP_VERSION_CHECK=1 \
                        PIP_NO_CACHE_DIR=1 \
                        python3 -m pip download \
                            --no-binary=:all: \
                            --no-deps \
                            --dest "${sdist_dl_dir}" \
                            "${requirement}"
                    then
                        sdist_path="$(find "${sdist_dl_dir}" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.zip' -o -name '*.tar.bz2' -o -name '*.tar.xz' \) -print -quit || true)"
                        if [[ -n "${sdist_path}" ]] && \
                            MAKEFLAGS="-j${REFINERY_SDIST_BUILD_JOBS}" \
                            CMAKE_BUILD_PARALLEL_LEVEL="${REFINERY_SDIST_BUILD_JOBS}" \
                            NINJAFLAGS="-j${REFINERY_SDIST_BUILD_JOBS}" \
                            MAX_JOBS="${REFINERY_SDIST_BUILD_JOBS}" \
                            CARGO_BUILD_JOBS="${REFINERY_SDIST_BUILD_JOBS}" \
                            NPY_NUM_BUILD_JOBS="${REFINERY_SDIST_BUILD_JOBS}" \
                            PIP_DISABLE_PIP_VERSION_CHECK=1 \
                            PIP_NO_CACHE_DIR=1 \
                            python3 -m pip wheel \
                                --no-deps \
                                --wheel-dir "${sdist_wheel_dir}" \
                                "${sdist_path}"
                        then
                            built_wheel="$(find "${sdist_wheel_dir}" -maxdepth 1 -type f -name '*.whl' -print -quit || true)"
                            if [[ -n "${built_wheel}" ]] && [[ "${built_wheel}" == *"-none-any.whl" ]]; then
                                cp -f "${built_wheel}" "${REFINERY_WHEELHOUSE_DIR}/"
                                printf '%s\n' "${requirement}" >> "${resolved_tmp}"
                                continue
                            fi
                        fi
                    fi
                elif [[ "${skip_sdist_for_req}" == "1" ]]; then
                    echo "    skipping sdist fallback for ${requirement} (known native package; wheel-only on i686 path)"
                fi
                printf '%s\n' "${requirement}" >> "${missing_tmp}"
            fi
        done < "${requirements_tmp}"

        cp "${resolved_tmp}" "${REFINERY_WHEELHOUSE_DIR}/requirements-resolved.txt"
        if [[ -s "${missing_tmp}" ]]; then
            cp "${missing_tmp}" "${REFINERY_WHEELHOUSE_DIR}/requirements-missing.txt"
            cp "${missing_tmp}" "${REFINERY_MISSING_WHEELS_REPORT}"
            missing_count="$(wc -l < "${missing_tmp}" | awk '{print $1}')"
            echo "Missing i686 manylinux wheels for ${missing_count} binary-refinery optional requirement(s)."
            echo "See: ${REFINERY_MISSING_WHEELS_REPORT}"
            if [[ "${REFINERY_WHEEL_STRICT}" == "1" ]]; then
                echo "REFINERY_WHEEL_STRICT=1 set; stopping due to missing wheels." >&2
                exit 1
            fi
            echo "Continuing with best-effort optional dependency coverage (REFINERY_WHEEL_STRICT=${REFINERY_WHEEL_STRICT})."
        else
            rm -f "${REFINERY_WHEELHOUSE_DIR}/requirements-missing.txt"
        fi
        rm -f "${requirements_tmp}" "${resolved_tmp}" "${missing_tmp}"
        rm -rf "${sdist_dl_dir}" "${sdist_wheel_dir}"
        require_prefetched_wheels=1
    else
        echo "Skipping binary-refinery wheel prefetch (PREFETCH_REFINERY_WHEELS=${PREFETCH_REFINERY_WHEELS})"
    fi
else
    echo "[3/8] Prefetch skipped (PREFETCH_DOWNLOADS=${PREFETCH_DOWNLOADS})"
fi

echo "[4/8] Building Buildroot output (jobs=${BUILDROOT_JOBS})"
make -C "${BUILDROOT_SRC}" \
    O="${OUT_DIR}" \
    BR2_DL_DIR="${DL_DIR}" \
    BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" \
    PYTHON_BINARY_REFINERY_VERSION="${BINARY_REFINERY_VERSION}" \
    PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR="${REFINERY_WHEELHOUSE_DIR}" \
    PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_PRIMARY="${REFINERY_WHEEL_PLATFORM_PRIMARY}" \
    PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_FALLBACK="${REFINERY_WHEEL_PLATFORM_FALLBACK}" \
    PYTHON_BINARY_REFINERY_REQUIRE_PREFETCH="${require_prefetched_wheels}" \
    PYTHON_LIEF_VERSION="${PYTHON_LIEF_VERSION}" \
    -j"${BUILDROOT_JOBS}"

legal_info_archive_name=""
legal_info_archive_size_mb=0
missing_wheels_report_name=""
buildroot_provided_report_name=""
missing_buildroot_report_name=""
if [[ -f "${REFINERY_MISSING_WHEELS_REPORT}" ]]; then
    missing_wheels_report_name="$(basename "${REFINERY_MISSING_WHEELS_REPORT}")"
fi
if [[ -f "${REFINERY_BUILDROOT_PROVIDED_REPORT}" ]]; then
    buildroot_provided_report_name="$(basename "${REFINERY_BUILDROOT_PROVIDED_REPORT}")"
fi
if [[ -f "${REFINERY_MISSING_BUILDROOT_REPORT}" ]]; then
    missing_buildroot_report_name="$(basename "${REFINERY_MISSING_BUILDROOT_REPORT}")"
fi
if [[ "${BUILD_LEGAL_INFO}" == "1" ]]; then
    echo "[5/8] Building Buildroot legal-info"
    make -C "${BUILDROOT_SRC}" \
        O="${OUT_DIR}" \
        BR2_DL_DIR="${DL_DIR}" \
        BR2_EXTERNAL="${BR2_EXTERNAL_DIR}" \
        PYTHON_BINARY_REFINERY_VERSION="${BINARY_REFINERY_VERSION}" \
        PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR="${REFINERY_WHEELHOUSE_DIR}" \
        PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_PRIMARY="${REFINERY_WHEEL_PLATFORM_PRIMARY}" \
        PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_FALLBACK="${REFINERY_WHEEL_PLATFORM_FALLBACK}" \
        PYTHON_BINARY_REFINERY_REQUIRE_PREFETCH="${require_prefetched_wheels}" \
        PYTHON_LIEF_VERSION="${PYTHON_LIEF_VERSION}" \
        legal-info

    legal_info_dir="${OUT_DIR}/legal-info"
    if [[ ! -d "${legal_info_dir}" ]]; then
        echo "Buildroot legal-info output not found at ${legal_info_dir}" >&2
        exit 1
    fi

    rm -f "${LEGAL_INFO_ARCHIVE}"
    mkdir -p "$(dirname "${LEGAL_INFO_ARCHIVE}")"
    tar -C "${OUT_DIR}" -czf "${LEGAL_INFO_ARCHIVE}" legal-info
    legal_info_archive_name="$(basename "${LEGAL_INFO_ARCHIVE}")"
    legal_info_archive_bytes="$(stat -c '%s' "${LEGAL_INFO_ARCHIVE}")"
    legal_info_archive_size_mb="$(((legal_info_archive_bytes + 1048575) / 1048576))"
else
    echo "[5/8] legal-info skipped (BUILD_LEGAL_INFO=${BUILD_LEGAL_INFO})"
    rm -f "${LEGAL_INFO_ARCHIVE}"
fi

VMLINUX_PATH="${OUT_DIR}/images/bzImage"
ROOTFS_TAR="${OUT_DIR}/images/rootfs.tar"
ROOTFS_CPIO_GZ="${OUT_DIR}/images/rootfs.cpio.gz"
ROOTFS_CPIO="${OUT_DIR}/images/rootfs.cpio"

if [[ ! -f "${VMLINUX_PATH}" ]]; then
    echo "Buildroot kernel image not found at ${VMLINUX_PATH}" >&2
    exit 1
fi
if [[ ! -f "${ROOTFS_TAR}" ]]; then
    echo "Buildroot rootfs tar not found at ${ROOTFS_TAR}" >&2
    exit 1
fi

echo "[6/8] Exporting kernel/initrd and creating ext2 root disk"
cp "${VMLINUX_PATH}" "${VMLINUX_OUT}"
if [[ -f "${ROOTFS_CPIO_GZ}" ]]; then
    cp "${ROOTFS_CPIO_GZ}" "${INITRD_OUT}"
elif [[ -f "${ROOTFS_CPIO}" ]]; then
    gzip -c "${ROOTFS_CPIO}" > "${INITRD_OUT}"
else
    # Fallback: create a minimal empty initramfs.
    TMP_CPIO_DIR="$(mktemp -d "${WORK_DIR}/empty-initrd.XXXXXX")"
    trap 'rm -rf "${TMP_CPIO_DIR}"' EXIT
    (
        cd "${TMP_CPIO_DIR}"
        find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -9 > "${INITRD_OUT}"
    )
fi

rm -rf "${EXPORT_DIR}"
mkdir -p "${EXPORT_DIR}"
tar -xf "${ROOTFS_TAR}" -C "${EXPORT_DIR}" --exclude='dev/*' --exclude='./dev/*'
rm -rf "${EXPORT_DIR}/dev"
mkdir -p "${EXPORT_DIR}/dev" "${EXPORT_DIR}/proc" "${EXPORT_DIR}/sys" "${EXPORT_DIR}/run" "${EXPORT_DIR}/tmp"
chmod 1777 "${EXPORT_DIR}/tmp"

if find "${EXPORT_DIR}" -type f ! -readable -print -quit | grep -q .; then
    echo "Normalizing unreadable files in export tree for mke2fs"
    find "${EXPORT_DIR}" -type f ! -readable -exec chmod u+r {} +
fi

for dir in tmp var/tmp var/cache var/log root/.cache; do
    if [[ -d "${EXPORT_DIR}/${dir}" ]]; then
        find "${EXPORT_DIR}/${dir}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    fi
done
mkdir -p "${EXPORT_DIR}/tmp" "${EXPORT_DIR}/var/tmp"
chmod 1777 "${EXPORT_DIR}/tmp" "${EXPORT_DIR}/var/tmp" || true

rootfs_mb="$(du -sm "${EXPORT_DIR}" | awk '{print $1}')"
if [[ -n "${DISK_MB}" ]]; then
    if ! [[ "${DISK_MB}" =~ ^[0-9]+$ ]] || (( DISK_MB < 32 )); then
        echo "DISK_MB must be an integer >= 32 (got: ${DISK_MB})" >&2
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
# ext2 keeps metadata overhead lower than ext4 and avoids journal traffic.
mke2fs -q -t ext2 -L rootfs -F -d "${EXPORT_DIR}" "${DISK_IMAGE}"

if [[ "${AUTO_SHRINK}" == "1" ]]; then
    echo "[7/8] Auto-shrinking disk image"
    PAD_MB="${SHRINK_PAD_MB}" MIN_MB="${SHRINK_MIN_MB}" "${ROOT_DIR}/scripts/shrink-image.sh" "${DISK_IMAGE}"
else
    echo "[7/8] Auto-shrinking skipped (AUTO_SHRINK=${AUTO_SHRINK})"
fi

final_disk_bytes="$(stat -c '%s' "${DISK_IMAGE}")"
final_disk_mb="$(((final_disk_bytes + 1048575) / 1048576))"

echo "[8/8] Writing metadata"
cat > "${ASSETS_DIR}/boot-image-info.txt" <<META
built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
flavor=buildroot
buildroot_version=${BUILDROOT_VERSION}
buildroot_defconfig=${BUILDROOT_DEFCONFIG}
build_profile=${BUILD_PROFILE}
buildroot_global_patch_dir=${BUILDROOT_GLOBAL_PATCH_DIR}
prefetch_downloads=${PREFETCH_DOWNLOADS}
prefetch_refinery_wheels=${PREFETCH_REFINERY_WHEELS}
kernel_version_adjusted_for_hash=$( [[ -n "${adjusted_linux_kernel_version}" ]] && printf '%s' "${adjusted_linux_kernel_version}" || printf 'no')
download_force_check_hashes_overridden=$( [[ "${disable_force_hashes}" == "1" ]] && printf 'yes' || printf 'no')
refinery_require_buildroot_target=${REFINERY_REQUIRE_BUILDROOT_TARGET}
refinery_wheel_strict=${REFINERY_WHEEL_STRICT}
refinery_sdist_fallback=${REFINERY_SDIST_FALLBACK}
refinery_sdist_build_jobs=${REFINERY_SDIST_BUILD_JOBS}
refinery_sdist_skip_packages=${REFINERY_SDIST_SKIP_PACKAGES}
refinery_wheel_platform_primary=${REFINERY_WHEEL_PLATFORM_PRIMARY}
refinery_wheel_platform_fallback=${REFINERY_WHEEL_PLATFORM_FALLBACK}
refinery_missing_wheels_report=${missing_wheels_report_name}
refinery_buildroot_provided_report=${buildroot_provided_report_name}
refinery_missing_buildroot_report=${missing_buildroot_report_name}
legal_info_enabled=${BUILD_LEGAL_INFO}
legal_info_archive=${legal_info_archive_name}
legal_info_archive_size_mb=${legal_info_archive_size_mb}
binary_refinery_version=${BINARY_REFINERY_VERSION}
python_lief_version=${PYTHON_LIEF_VERSION}
disk_size_mb=${final_disk_mb}
kernel=$(basename "${VMLINUX_PATH}")
rootfs_source=$(basename "${ROOTFS_TAR}")
META

echo ""
echo "Artifacts generated:"
echo "  ${DISK_IMAGE}"
echo "  ${VMLINUX_OUT}"
echo "  ${INITRD_OUT}"
if [[ -f "${REFINERY_MISSING_WHEELS_REPORT}" ]]; then
    echo "  ${REFINERY_MISSING_WHEELS_REPORT}"
fi
if [[ -f "${REFINERY_BUILDROOT_PROVIDED_REPORT}" ]]; then
    echo "  ${REFINERY_BUILDROOT_PROVIDED_REPORT}"
fi
if [[ -f "${REFINERY_MISSING_BUILDROOT_REPORT}" ]]; then
    echo "  ${REFINERY_MISSING_BUILDROOT_REPORT}"
fi
if [[ -f "${LEGAL_INFO_ARCHIVE}" ]]; then
    echo "  ${LEGAL_INFO_ARCHIVE}"
fi
echo ""
echo "If you change buildroot/overlay/, rerun:"
echo "  make build-disk"
