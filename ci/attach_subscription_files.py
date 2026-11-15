#!/usr/bin/env python3
"""Attach the subscription files to the VKTurnProxy app target.

Same four insertions as attach_design_files.py: file references, build files,
the group's children, and the app target's Sources phase. Idempotent.
"""

from __future__ import annotations

import os
import shutil
import sys

DEFAULT_PROJECT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "VKTurnProxy", "VKTurnProxy.xcodeproj", "project.pbxproj",
)

FILES = [
    ("Subscription.swift", "sourcecode.swift"),
    ("SubscriptionParser.swift", "sourcecode.swift"),
    ("SubscriptionStore.swift", "sourcecode.swift"),
    ("ServerPickerMenu.swift", "sourcecode.swift"),
    ("SubscriptionsView.swift", "sourcecode.swift"),
]

GROUP = "9C68AA12FFBB168491B35540"          # VKTurnProxy group
APP_SOURCES = "DDF7D137E68B787F0672E4CA"    # Sources (app)


def main() -> int:
    path = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PROJECT)
    text = open(path, encoding="utf-8").read()

    if "D32A0000000000000000A001" in text:
        print("already attached — nothing to do")
        return 0

    refs, builds = [], []
    group_entries, source_entries = [], []
    for index, (name, _) in enumerate(FILES, start=1):
        ref = f"D32A0000000000000000A{index:03d}"
        build = f"D32A0000000000000000B{index:03d}"
        refs.append(
            f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};\n")
        builds.append(
            f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};\n")
        group_entries.append(f"\t\t\t\t{ref} /* {name} */,\n")
        source_entries.append(f"\t\t\t\t{build} /* {name} in Sources */,\n")

    def insert_after(anchor: str, payload: str) -> None:
        nonlocal text
        if anchor not in text:
            raise SystemExit(f"anchor not found: {anchor[:70]!r}")
        text = text.replace(anchor, anchor + payload, 1)

    insert_after("/* Begin PBXBuildFile section */\n", "".join(builds))
    insert_after("/* Begin PBXFileReference section */\n", "".join(refs))

    group_anchor = (
        f"\t\t{GROUP} /* VKTurnProxy */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
    )
    insert_after(group_anchor, "".join(group_entries))

    sources_anchor = (
        f"\t\t{APP_SOURCES} /* Sources */ = {{\n"
        f"\t\t\tisa = PBXSourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
    )
    insert_after(sources_anchor, "".join(source_entries))

    if text.count("{") != text.count("}"):
        raise SystemExit("brace mismatch after edit — refusing to write")
    for ident in [f"D32A0000000000000000A{i:03d}" for i in range(1, 6)] + \
                 [f"D32A0000000000000000B{i:03d}" for i in range(1, 6)]:
        if text.count(ident) < 2:
            raise SystemExit(f"{ident} missing after edit")

    backup = path + ".bak"
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print(f"attached {len(FILES)} subscription files ({len(text)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
