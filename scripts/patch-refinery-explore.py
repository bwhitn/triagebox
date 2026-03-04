#!/usr/bin/env python3
from pathlib import Path
import sys


def main() -> int:
    path = Path(sys.argv[1])
    text = path.read_text(encoding="utf-8")
    needle = "            header = '{e:-<4}[{}]{e:-<{w}}'.format(name, w=width - len(name) - 6, e='')"
    replacement = (
        "            padding = max(0, width - len(name) - 6)\n"
        "            # __NIXBROWSER_EXPLORE_WIDTH_GUARD__\n"
        "            header = '{e:-<4}[{}]{e:-<{w}}'.format(name, w=padding, e='')"
    )
    if needle not in text:
        return 0
    path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
