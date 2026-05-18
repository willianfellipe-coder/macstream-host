#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""
Embed an Info.plist with LSUIElement=true into a Mach-O binary's
`__TEXT,__info_plist` section so macOS LaunchServices treats it as an
accessory (no Dock icon, no AppSwitcher entry).

This is the only path that works for `MacStreamEngine` (upstream
Sunshine binary, C++, no source control on our side). Without it the
engine runs as `.regular` activation policy, claims a Dock icon under
`org.macstream.host`, and the GUI's parent icon stays visible even
when the dashboard is closed.

Invoked by `scripts/package_dmg.sh` right after copying the engine
into the bundle and BEFORE the final `codesign --sign`, because
adding a Mach-O section invalidates any existing signature.

Requires LIEF: `python3 -m pip install --user lief`.
"""

import sys
from pathlib import Path

try:
    import lief
except ImportError:
    sys.stderr.write(
        "ERROR: LIEF is not installed. Run `python3 -m pip install --user lief`.\n"
    )
    sys.exit(2)


PLIST_BYTES = b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIdentifier</key>
    <string>org.macstream.host</string>
</dict>
</plist>
"""


def already_patched(binary: "lief.MachO.Binary") -> bool:
    """Returns True when the binary already carries a __TEXT,__info_plist
    section. Useful for idempotency — rerunning the script on an
    already-patched binary should be a no-op so package_dmg.sh stays
    safe to invoke repeatedly during development."""
    for segment in binary.segments:
        if segment.name != "__TEXT":
            continue
        for section in segment.sections:
            if section.name == "__info_plist":
                return True
    return False


def patch(path: Path) -> None:
    fat = lief.MachO.parse(str(path))
    if fat is None:
        sys.stderr.write(f"ERROR: failed to parse Mach-O at {path}\n")
        sys.exit(3)

    patched_any = False
    for i in range(fat.size):
        binary = fat.at(i)
        if already_patched(binary):
            print(f"[skip] slice {i}: __TEXT,__info_plist already present")
            continue

        section = lief.MachO.Section("__info_plist", list(PLIST_BYTES))
        section.segment_name = "__TEXT"
        binary.add_section(section)
        patched_any = True
        print(f"[ok]   slice {i}: embedded LSUIElement=true ({len(PLIST_BYTES)} bytes)")

    if patched_any:
        fat.write(str(path))
        print(f"Saved {path}")
    else:
        print("No changes — binary already patched.")


def main() -> int:
    if len(sys.argv) != 2:
        sys.stderr.write("Usage: embed_lsuielement.py <path-to-mach-o>\n")
        return 1

    target = Path(sys.argv[1])
    if not target.exists():
        sys.stderr.write(f"ERROR: file not found: {target}\n")
        return 1

    patch(target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
