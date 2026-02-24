#!/bin/sh

case "${TERM:-}" in
    ""|linux|vt100|vt220)
        export TERM=xterm
        ;;
esac

# Some tools crash when terminal width/height resolve to zero.
case "${COLUMNS:-}" in
    ""|*[!0-9]*|0)
        export COLUMNS=120
        ;;
esac
case "${LINES:-}" in
    ""|*[!0-9]*|0)
        export LINES=40
        ;;
esac

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
