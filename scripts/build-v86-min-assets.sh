#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="${ROOT_DIR}/public/assets/v86-min"
WORK_DIR="${ROOT_DIR}/.work/v86-src"
V86_SRC_DIR="${V86_SRC_DIR:-}"
V86_REPO_URL="${V86_REPO_URL:-https://github.com/copy/v86.git}"
V86_REF="${V86_REF:-master}"
V86_GIT_UPDATE="${V86_GIT_UPDATE:-1}"
V86_NPM_INSTALL="${V86_NPM_INSTALL:-ci}"
V86_BUILD_COMMAND="${V86_BUILD_COMMAND:-auto}"
NODE_BIN="${NODE_BIN:-}"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

resolve_node_bin() {
    if [[ -n "${NODE_BIN}" ]]; then
        command -v "${NODE_BIN}" >/dev/null 2>&1 || {
            echo "Configured NODE_BIN not found in PATH: ${NODE_BIN}" >&2
            exit 1
        }
        return 0
    fi

    if command -v node >/dev/null 2>&1; then
        NODE_BIN="node"
        return 0
    fi
    if command -v nodejs >/dev/null 2>&1; then
        NODE_BIN="nodejs"
        return 0
    fi

    echo "Missing required command: node (or nodejs)" >&2
    exit 1
}

has_npm_script() {
    local pkg="$1"
    local script_name="$2"
    "${NODE_BIN}" -e '
const fs = require("fs");
const pkg = process.argv[1];
const scriptName = process.argv[2];
const data = JSON.parse(fs.readFileSync(pkg, "utf8"));
process.exit(data.scripts && data.scripts[scriptName] ? 0 : 1);
' "${pkg}" "${script_name}"
}

resolve_source_dir() {
    if [[ -n "${V86_SRC_DIR}" ]]; then
        if [[ ! -d "${V86_SRC_DIR}" ]]; then
            echo "V86_SRC_DIR does not exist: ${V86_SRC_DIR}" >&2
            exit 1
        fi
        echo "${V86_SRC_DIR}"
        return 0
    fi

    need_cmd git
    mkdir -p "$(dirname "${WORK_DIR}")"

    if [[ ! -d "${WORK_DIR}/.git" ]]; then
        echo "Cloning v86 source into ${WORK_DIR}" >&2
        git clone --depth 1 --branch "${V86_REF}" "${V86_REPO_URL}" "${WORK_DIR}"
    elif [[ "${V86_GIT_UPDATE}" == "1" ]]; then
        echo "Updating v86 source in ${WORK_DIR} to ${V86_REF}" >&2
        git -C "${WORK_DIR}" fetch --depth 1 origin "${V86_REF}"
        git -C "${WORK_DIR}" checkout -q FETCH_HEAD
    fi

    echo "${WORK_DIR}"
}

run_make_build() {
    local src="$1"
    if ! command -v make >/dev/null 2>&1; then
        return 1
    fi
    local missing_tools=()
    command -v java >/dev/null 2>&1 || missing_tools+=("java")
    command -v clang >/dev/null 2>&1 || missing_tools+=("clang")
    command -v wasm-ld >/dev/null 2>&1 || missing_tools+=("wasm-ld")
    if ((${#missing_tools[@]} > 0)); then
        echo "Skipping make-based v86 build: missing ${missing_tools[*]}"
        return 1
    fi
    echo "Trying make-based v86 build"
    (cd "${src}" && make build/libv86.js build/v86.wasm)
}

run_npm_build() {
    local src="$1"
    local pkg="${src}/package.json"
    local install_mode="${V86_NPM_INSTALL}"
    resolve_node_bin
    need_cmd npm
    [[ -f "${pkg}" ]] || {
        echo "Missing ${pkg}; cannot run npm build fallback." >&2
        return 1
    }

    if [[ "${install_mode}" == "ci" ]] && [[ ! -f "${src}/package-lock.json" ]] && [[ ! -f "${src}/npm-shrinkwrap.json" ]]; then
        echo "No npm lockfile found; switching from npm ci to npm install"
        install_mode="install"
    fi

    case "${install_mode}" in
        ci)
            echo "Running npm ci"
            (cd "${src}" && npm ci)
            ;;
        install)
            echo "Running npm install"
            (cd "${src}" && npm install)
            ;;
        skip)
            echo "Skipping npm dependency install (V86_NPM_INSTALL=${V86_NPM_INSTALL})"
            ;;
        *)
            echo "Unsupported V86_NPM_INSTALL value: ${V86_NPM_INSTALL}" >&2
            return 1
            ;;
    esac

    if has_npm_script "${pkg}" build; then
        echo "Running npm run build"
        (cd "${src}" && npm run build)
        return 0
    fi
    if has_npm_script "${pkg}" build-release; then
        echo "Running npm run build-release"
        (cd "${src}" && npm run build-release)
        return 0
    fi
    if has_npm_script "${pkg}" dist; then
        echo "Running npm run dist"
        (cd "${src}" && npm run dist)
        return 0
    fi

    echo "No known npm build script found in ${pkg}" >&2
    echo "This v86 tree likely requires the make toolchain path (java clang wasm-ld)." >&2
    return 1
}

verify_artifacts() {
    local src="$1"
    local missing=()
    [[ -f "${src}/build/libv86.js" ]] || missing+=("${src}/build/libv86.js")
    [[ -f "${src}/build/v86.wasm" ]] || missing+=("${src}/build/v86.wasm")
    [[ -f "${src}/bios/seabios.bin" ]] || missing+=("${src}/bios/seabios.bin")

    if ((${#missing[@]} > 0)); then
        echo "v86 build completed but required artifacts are missing:" >&2
        printf '  %s\n' "${missing[@]}" >&2
        exit 1
    fi
}

copy_artifacts() {
    local src="$1"
    mkdir -p "${ASSETS_DIR}"
    install -m 0644 "${src}/build/libv86.js" "${ASSETS_DIR}/libv86.js"
    install -m 0644 "${src}/build/v86.wasm" "${ASSETS_DIR}/v86.wasm"
    install -m 0644 "${src}/bios/seabios.bin" "${ASSETS_DIR}/seabios.bin"
    if [[ -f "${src}/bios/vgabios.bin" ]]; then
        install -m 0644 "${src}/bios/vgabios.bin" "${ASSETS_DIR}/vgabios.bin"
    else
        rm -f "${ASSETS_DIR}/vgabios.bin"
    fi
}

main() {
    local src
    src="$(resolve_source_dir)"

    if [[ "${V86_BUILD_COMMAND}" != "auto" ]]; then
        echo "Running custom build command: ${V86_BUILD_COMMAND}"
        (cd "${src}" && bash -lc "${V86_BUILD_COMMAND}")
    else
        if ! run_make_build "${src}"; then
            echo "make build path failed; trying npm build fallback"
            run_npm_build "${src}"
        fi
    fi

    verify_artifacts "${src}"
    copy_artifacts "${src}"

    echo "v86 source: ${src}"
    echo "v86 custom assets written to ${ASSETS_DIR}"
}

main "$@"
