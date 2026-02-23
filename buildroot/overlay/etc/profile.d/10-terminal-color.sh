#!/bin/sh

case "${TERM:-}" in
    ""|linux|vt100|vt220)
        export TERM=xterm
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
