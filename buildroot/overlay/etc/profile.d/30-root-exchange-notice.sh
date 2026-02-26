#!/bin/sh

# Show a brief root-exchange notice on interactive login shells.
if [ -n "${PS1:-}" ]; then
    echo ""
    echo "Root exchange: files from the web UI appear in /root (9p mount may take a few seconds)."
    echo "Root exchange: files saved in /root can be downloaded from the web UI /root monitor."
fi
