#!/bin/sh

run_stty() {
    if command -v stty >/dev/null 2>&1; then
        stty "$@"
        return
    fi
    if /bin/busybox --list 2>/dev/null | grep -qx "stty"; then
        /bin/busybox stty "$@"
        return
    fi
    return 127
}

case "${TERM:-}" in
    ""|linux|vt100|vt220)
        export TERM=xterm
        ;;
esac

# Some tools crash when terminal width/height resolve to zero.
if [ -t 0 ]; then
    set -- $(run_stty size 2>/dev/null || echo "0 0")
    _rows="$1"
    _cols="$2"
else
    _rows="${LINES:-0}"
    _cols="${COLUMNS:-0}"
fi

case "${_cols:-}" in
    ""|*[!0-9]*|0)
        _cols=120
        ;;
esac
case "${_rows:-}" in
    ""|*[!0-9]*|0)
        _rows=40
        ;;
esac

if [ -t 0 ]; then
    run_stty rows "$_rows" cols "$_cols" 2>/dev/null || true
fi

export COLUMNS="$_cols"
export LINES="$_rows"
unset _rows _cols

if [ -n "${PS1:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    esc="$(printf '\033')"
    if [ "$(id -u)" -eq 0 ]; then
        export PS1="${esc}[1;31m# ${esc}[0m"
    else
        export PS1="${esc}[1;32m$ ${esc}[0m"
    fi
    unset esc
fi

if [ "${TERM:-dumb}" != "dumb" ] && ls --help 2>/dev/null | grep -q -- '--color'; then
    alias ls='ls --color=auto'
    alias ll='ls -alF --color=auto'
fi
