#!/bin/sh

# Keep root shell HOME stable even when launched via non-standard getty/login paths.
if [ "$(id -u)" -eq 0 ]; then
    export HOME=/root
    [ -d /root ] || mkdir -p /root
fi
