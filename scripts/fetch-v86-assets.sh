#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="${ROOT_DIR}/public/assets/v86"
XTERM_DIR="${ROOT_DIR}/public/assets/xterm"
PRIMARY_BASE_URL="${V86_BASE_URL:-https://copy.sh/v86}"
XTERM_VERSION="${XTERM_VERSION:-5.5.0}"
XTERM_FIT_ADDON_VERSION="${XTERM_FIT_ADDON_VERSION:-0.10.0}"
XTERM_KEYPAD_ADDON_VERSION="${XTERM_KEYPAD_ADDON_VERSION:-latest}"
FETCH_VGA_BIOS="${FETCH_VGA_BIOS:-0}"

if [[ "${FETCH_VGA_BIOS}" != "0" && "${FETCH_VGA_BIOS}" != "1" ]]; then
    echo "FETCH_VGA_BIOS must be 0 or 1 (got: ${FETCH_VGA_BIOS})" >&2
    exit 1
fi

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

need_cmd curl

mkdir -p "${ASSETS_DIR}" "${XTERM_DIR}"

fetch_from_urls() {
    local dest="$1"
    shift
    local urls=("$@")

    local url
    for url in "${urls[@]}"; do
        echo "Downloading ${url}"
        if curl -fL "${url}" -o "${dest}"; then
            return 0
        fi
    done

    echo "Failed to download into ${dest}" >&2
    return 1
}

fetch_optional_from_urls() {
    local dest="$1"
    shift
    local urls=("$@")

    local url
    for url in "${urls[@]}"; do
        echo "Downloading ${url}"
        if curl -fL "${url}" -o "${dest}"; then
            return 0
        fi
    done
    return 1
}

fetch_v86() {
    local src="$1"
    local dest="$2"
    local urls=("${PRIMARY_BASE_URL}/${src}")
    if [[ "${PRIMARY_BASE_URL}" != "https://copy.sh/v86" ]]; then
        urls+=("https://copy.sh/v86/${src}")
    fi
    urls+=(
        "https://unpkg.com/v86@latest/${src}"
        "https://cdn.jsdelivr.net/npm/v86@latest/${src}"
    )
    fetch_from_urls "${ASSETS_DIR}/${dest}" "${urls[@]}"
}

fetch_xterm() {
    local kind="$1"
    local dest="$2"
    local urls=()

    if [[ "${kind}" == "js" ]]; then
        urls=(
            "https://unpkg.com/@xterm/xterm@${XTERM_VERSION}/lib/xterm.js"
            "https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/lib/xterm.js"
            "https://unpkg.com/@xterm/xterm@${XTERM_VERSION}/dist/xterm.js"
            "https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/dist/xterm.js"
            "https://unpkg.com/xterm@${XTERM_VERSION}/lib/xterm.js"
            "https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/lib/xterm.js"
            "https://unpkg.com/xterm@${XTERM_VERSION}/dist/xterm.js"
            "https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/dist/xterm.js"
        )
    elif [[ "${kind}" == "css" ]]; then
        urls=(
            "https://unpkg.com/@xterm/xterm@${XTERM_VERSION}/css/xterm.css"
            "https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/css/xterm.css"
            "https://unpkg.com/@xterm/xterm@${XTERM_VERSION}/dist/xterm.css"
            "https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/dist/xterm.css"
            "https://unpkg.com/xterm@${XTERM_VERSION}/css/xterm.css"
            "https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/css/xterm.css"
            "https://unpkg.com/xterm@${XTERM_VERSION}/dist/xterm.css"
            "https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/dist/xterm.css"
        )
    else
        echo "fetch_xterm: unknown kind '${kind}'" >&2
        return 1
    fi

    fetch_from_urls "${XTERM_DIR}/${dest}" "${urls[@]}"
}

fetch_xterm_fit_addon() {
    local dest="$1"
    local urls=(
        "https://unpkg.com/@xterm/addon-fit@${XTERM_FIT_ADDON_VERSION}/lib/addon-fit.js"
        "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@${XTERM_FIT_ADDON_VERSION}/lib/addon-fit.js"
        "https://unpkg.com/@xterm/addon-fit@${XTERM_FIT_ADDON_VERSION}/dist/addon-fit.js"
        "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@${XTERM_FIT_ADDON_VERSION}/dist/addon-fit.js"
        "https://unpkg.com/@xterm/addon-fit@latest/lib/addon-fit.js"
        "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@latest/lib/addon-fit.js"
        "https://unpkg.com/@xterm/addon-fit@latest/dist/addon-fit.js"
        "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@latest/dist/addon-fit.js"
        "https://unpkg.com/xterm-addon-fit@latest/lib/xterm-addon-fit.js"
        "https://cdn.jsdelivr.net/npm/xterm-addon-fit@latest/lib/xterm-addon-fit.js"
        "https://unpkg.com/xterm-addon-fit@latest/dist/xterm-addon-fit.js"
        "https://cdn.jsdelivr.net/npm/xterm-addon-fit@latest/dist/xterm-addon-fit.js"
    )
    fetch_from_urls "${XTERM_DIR}/${dest}" "${urls[@]}"
}

fetch_xterm_keypad_addon() {
    local dest="$1"
    local urls=(
        "https://unpkg.com/xtermjs-addon-keypad@${XTERM_KEYPAD_ADDON_VERSION}/dist/xtermjs-addon-keypad.js"
        "https://cdn.jsdelivr.net/npm/xtermjs-addon-keypad@${XTERM_KEYPAD_ADDON_VERSION}/dist/xtermjs-addon-keypad.js"
        "https://unpkg.com/xtermjs-addon-keypad@${XTERM_KEYPAD_ADDON_VERSION}/lib/xtermjs-addon-keypad.js"
        "https://cdn.jsdelivr.net/npm/xtermjs-addon-keypad@${XTERM_KEYPAD_ADDON_VERSION}/lib/xtermjs-addon-keypad.js"
        "https://unpkg.com/xtermjs-addon-keypad@${XTERM_KEYPAD_ADDON_VERSION}/xtermjs-addon-keypad.js"
        "https://cdn.jsdelivr.net/npm/xtermjs-addon-keypad@${XTERM_KEYPAD_ADDON_VERSION}/xtermjs-addon-keypad.js"
        "https://unpkg.com/xtermjs-addon-keypad@${XTERM_KEYPAD_ADDON_VERSION}/index.js"
        "https://cdn.jsdelivr.net/npm/xtermjs-addon-keypad@${XTERM_KEYPAD_ADDON_VERSION}/index.js"
        "https://unpkg.com/xterm-addon-keypad@${XTERM_KEYPAD_ADDON_VERSION}/dist/xterm-addon-keypad.js"
        "https://cdn.jsdelivr.net/npm/xterm-addon-keypad@${XTERM_KEYPAD_ADDON_VERSION}/dist/xterm-addon-keypad.js"
        "https://unpkg.com/xterm-addon-keypad@${XTERM_KEYPAD_ADDON_VERSION}/lib/xterm-addon-keypad.js"
        "https://cdn.jsdelivr.net/npm/xterm-addon-keypad@${XTERM_KEYPAD_ADDON_VERSION}/lib/xterm-addon-keypad.js"
        "https://unpkg.com/xtermjs-addon-keyboard@${XTERM_KEYPAD_ADDON_VERSION}/dist/xtermjs-addon-keyboard.js"
        "https://cdn.jsdelivr.net/npm/xtermjs-addon-keyboard@${XTERM_KEYPAD_ADDON_VERSION}/dist/xtermjs-addon-keyboard.js"
        "https://unpkg.com/xtermjs-addon-keyboard@${XTERM_KEYPAD_ADDON_VERSION}/lib/xtermjs-addon-keyboard.js"
        "https://cdn.jsdelivr.net/npm/xtermjs-addon-keyboard@${XTERM_KEYPAD_ADDON_VERSION}/lib/xtermjs-addon-keyboard.js"
        "https://unpkg.com/xtermjs-addon-keyboard@${XTERM_KEYPAD_ADDON_VERSION}/index.js"
        "https://cdn.jsdelivr.net/npm/xtermjs-addon-keyboard@${XTERM_KEYPAD_ADDON_VERSION}/index.js"
    )

    if fetch_optional_from_urls "${XTERM_DIR}/${dest}" "${urls[@]}"; then
        return 0
    fi

    echo "Warning: unable to fetch xterm keypad addon; writing local compatibility addon ${dest}" >&2
    cat >"${XTERM_DIR}/${dest}" <<'EOF'
;(function(global){
    if (!global) {
        return;
    }
    function sendInput(term, text) {
        if (!term || typeof text !== "string" || text.length === 0) {
            return;
        }
        if (typeof term.input === "function") {
            term.input(text, true);
            return;
        }
        if (term._core && term._core.coreService && typeof term._core.coreService.triggerDataEvent === "function") {
            term._core.coreService.triggerDataEvent(text, true);
        }
    }

    function createButton(doc, label, text, title, termRef) {
        var btn = doc.createElement("button");
        btn.type = "button";
        btn.className = "xterm-keypad-btn";
        btn.textContent = label;
        if (title) {
            btn.title = title;
        }
        btn.addEventListener("click", function(ev) {
            ev.preventDefault();
            ev.stopPropagation();
            if (typeof termRef.get === "function") {
                sendInput(termRef.get(), text);
            }
        });
        return btn;
    }

    function KeypadAddon(options) {
        this._options = options || {};
        this._terminal = null;
        this._root = null;
        this._host = null;
    }

    KeypadAddon.prototype.activate = function(term) {
        this._terminal = term || null;
        var host = this._options.container || null;
        if (!host && term && term.element && term.element.parentElement) {
            host = term.element.parentElement;
        }
        if (host) {
            this.open(host);
        }
    };

    KeypadAddon.prototype.dispose = function() {
        if (this._root && this._root.parentNode) {
            this._root.parentNode.removeChild(this._root);
        }
        this._root = null;
        this._host = null;
        this._terminal = null;
    };

    KeypadAddon.prototype.open = function(host) {
        if (!host || !host.ownerDocument) {
            return;
        }
        if (this._root && this._host === host) {
            return;
        }
        if (this._root && this._root.parentNode) {
            this._root.parentNode.removeChild(this._root);
        }

        var doc = host.ownerDocument;
        var root = doc.createElement("div");
        root.className = "xterm-keypad";

        var termRef = {
            get: function() {
                return this._terminal;
            }.bind(this)
        };

        var keys = [
            ["Ctrl+C", "\x03", "Interrupt"],
            ["Ctrl+D", "\x04", "EOF"],
            ["Ctrl+Z", "\x1a", "Suspend"],
            ["Ctrl+L", "\x0c", "Clear"],
            ["Esc", "\x1b", ""],
            ["Tab", "\x09", ""],
            ["Up", "\x1b[A", ""],
            ["Down", "\x1b[B", ""],
            ["Left", "\x1b[D", ""],
            ["Right", "\x1b[C", ""],
            ["PgUp", "\x1b[5~", ""],
            ["PgDn", "\x1b[6~", ""]
        ];

        for (var i = 0; i < keys.length; i++) {
            var k = keys[i];
            root.appendChild(createButton(doc, k[0], k[1], k[2], termRef));
        }

        host.appendChild(root);
        this._host = host;
        this._root = root;
    };

    KeypadAddon.prototype.attach = KeypadAddon.prototype.open;
    KeypadAddon.prototype.mount = KeypadAddon.prototype.open;
    KeypadAddon.prototype.render = KeypadAddon.prototype.open;
    KeypadAddon.prototype.show = function() {
        if (this._root) {
            this._root.style.display = "flex";
        }
    };
    KeypadAddon.prototype.hide = function() {
        if (this._root) {
            this._root.style.display = "none";
        }
    };

    global.XtermAddonKeypad = global.XtermAddonKeypad || {};
    global.XtermAddonKeypad.KeypadAddon = KeypadAddon;
    if (!global.KeypadAddon) {
        global.KeypadAddon = KeypadAddon;
    }
})(typeof window !== "undefined" ? window : this);
EOF
}

fetch_v86 "build/libv86.js" "libv86.js"
fetch_v86 "build/v86.wasm" "v86.wasm"
fetch_v86 "bios/seabios.bin" "seabios.bin"
if [[ "${FETCH_VGA_BIOS}" == "1" ]]; then
    fetch_v86 "bios/vgabios.bin" "vgabios.bin"
fi

fetch_xterm "js" "xterm.js"
fetch_xterm "css" "xterm.css"
fetch_xterm_fit_addon "xterm-addon-fit.js"
fetch_xterm_keypad_addon "xterm-addon-keypad.js"

echo "v86 assets written to ${ASSETS_DIR}"
echo "xterm assets written to ${XTERM_DIR}"
