#!/bin/sh

if [ -n "${PS1:-}" ]; then
    # BusyBox ash line editing/completion can render incorrectly when PS1
    # contains raw ANSI escapes, so keep prompt plain here.
    if [ "$(id -u)" -eq 0 ]; then
        export PS1="\\w # "
    else
        export PS1="\\w $ "
    fi
fi

if [ "${TERM:-dumb}" != "dumb" ] && ls --help 2>/dev/null | grep -q -- '--color'; then
    alias ls='ls --color=auto'
    alias ll='ls -alF --color=auto'
fi
