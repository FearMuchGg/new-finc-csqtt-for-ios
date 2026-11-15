#!/usr/bin/env python3
"""Attach the Design/ folder to the VKTurnProxy app target.

The Xcode project has no synchronized folders (objectVersion 77 but plain
PBXGroup), so a file on disk is invisible until it is named in four places:
PBXFileReference, PBXBuildFile, the group's children, and the target's
Sources/Resources phase. This script makes exactly those four insertions, once,
idempotently, and refuses to run twice.

Usage:  python ci/attach_design_files.py [path/to/project.pbxproj]
"""

from __future__ import annotations

import os
import shutil
import sys

DEFAULT_PROJECT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "VKTurnProxy", "VKTurnProxy.xcodeproj", "project.pbxproj",
)

# 24-hex identifiers, chosen to sort next to nothing existing.
GROUP = "D31A0000000000000000A001"
REF_THEME = "D31A0000000000000000A002"
REF_COMPONENTS = "D31A0000000000000000A003"
REF_ONBOARDING = "D31A0000000000000000A004"
REF_STRINGS = "D31A0000000000000000A005"
BUILD_THEME = "D31A0000000000000000B001"
BUILD_COMPONENTS = "D31A0000000000000000B002"
BUILD_ONBOARDING = "D31A0000000000000000B003"
BUILD_STRINGS = "D31A0000000000000000B004"

APP_GROUP = "9C68AA12FFBB168491B35540"          # VKTurnProxy
APP_SOURCES = "DDF7D137E68B787F0672E4CA"        # Sources (app)
APP_RESOURCES = "B67F24B52097C82D38E1E6A8"      # Resources (app)


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PROJECT
    path = os.path.abspath(path)
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()

    if GROUP in text:
        print("already attached — nothing to do")
        return 0

    for ident in (GROUP, REF_THEME, REF_COMPONENTS, REF_ONBOARDING, REF_STRINGS,
                  BUILD_THEME, BUILD_COMPONENTS, BUILD_ONBOARDING, BUILD_STRINGS):
        if ident in text:
            raise SystemExit(f"identifier {ident} already present, refusing to corrupt the file")

    build_files = (
        f"\t\t{BUILD_THEME} /* CSQTTTheme.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {REF_THEME} /* CSQTTTheme.swift */; }};\n"
        f"\t\t{BUILD_COMPONENTS} /* CSQTTComponents.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {REF_COMPONENTS} /* CSQTTComponents.swift */; }};\n"
        f"\t\t{BUILD_ONBOARDING} /* CSQTTOnboarding.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {REF_ONBOARDING} /* CSQTTOnboarding.swift */; }};\n"
        f"\t\t{BUILD_STRINGS} /* Localizable.xcstrings in Resources */ = {{isa = PBXBuildFile; fileRef = {REF_STRINGS} /* Localizable.xcstrings */; }};\n"
    )

    file_refs = (
        f"\t\t{REF_THEME} /* CSQTTTheme.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CSQTTTheme.swift; sourceTree = \"<group>\"; }};\n"
        f"\t\t{REF_COMPONENTS} /* CSQTTComponents.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CSQTTComponents.swift; sourceTree = \"<group>\"; }};\n"
        f"\t\t{REF_ONBOARDING} /* CSQTTOnboarding.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CSQTTOnboarding.swift; sourceTree = \"<group>\"; }};\n"
        f"\t\t{REF_STRINGS} /* Localizable.xcstrings */ = {{isa = PBXFileReference; lastKnownFileType = text.json.xcstrings; path = Localizable.xcstrings; sourceTree = \"<group>\"; }};\n"
    )

    group_block = (
        f"\t\t{GROUP} /* Design */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t\t{REF_COMPONENTS} /* CSQTTComponents.swift */,\n"
        f"\t\t\t\t{REF_ONBOARDING} /* CSQTTOnboarding.swift */,\n"
        f"\t\t\t\t{REF_THEME} /* CSQTTTheme.swift */,\n"
        f"\t\t\t\t{REF_STRINGS} /* Localizable.xcstrings */,\n"
        f"\t\t\t);\n"
        f"\t\t\tpath = Design;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};\n"
    )

    def insert_after(anchor: str, payload: str) -> None:
        nonlocal text
        if anchor not in text:
            raise SystemExit(f"anchor not found: {anchor[:60]!r}")
        text = text.replace(anchor, anchor + payload, 1)

    insert_after("/* Begin PBXBuildFile section */\n", build_files)
    insert_after("/* Begin PBXFileReference section */\n", file_refs)
    insert_after("/* End PBXGroup section */\n", group_block)

    app_group_anchor = f"\t\t{APP_GROUP} /* VKTurnProxy */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
    insert_after(app_group_anchor, f"\t\t\t\t{GROUP} /* Design */,\n")

    sources_anchor = (
        f"\t\t{APP_SOURCES} /* Sources */ = {{\n"
        f"\t\t\tisa = PBXSourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
    )
    insert_after(
        sources_anchor,
        f"\t\t\t\t{BUILD_THEME} /* CSQTTTheme.swift in Sources */,\n"
        f"\t\t\t\t{BUILD_COMPONENTS} /* CSQTTComponents.swift in Sources */,\n"
        f"\t\t\t\t{BUILD_ONBOARDING} /* CSQTTOnboarding.swift in Sources */,\n",
    )

    resources_anchor = (
        f"\t\t{APP_RESOURCES} /* Resources */ = {{\n"
        f"\t\t\tisa = PBXResourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
    )
    insert_after(resources_anchor, f"\t\t\t\t{BUILD_STRINGS} /* Localizable.xcstrings in Resources */,\n")

    # Sanity checks before touching the disk: the file must still be balanced
    # and every inserted identifier must appear the expected number of times.
    if text.count("{") != text.count("}"):
        raise SystemExit("brace mismatch after edit — refusing to write")
    expected = {
        GROUP: 2,          # definition + parent children entry
        REF_THEME: 3,      # file reference + build file's fileRef + group children
        REF_COMPONENTS: 3,
        REF_ONBOARDING: 3,
        REF_STRINGS: 3,
        BUILD_THEME: 2,    # definition + sources entry
        BUILD_STRINGS: 2,  # definition + resources entry
    }
    for ident, count in expected.items():
        if text.count(ident) != count:
            raise SystemExit(f"{ident} appears {text.count(ident)} times, expected {count}")

    backup = path + ".bak"
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print(f"attached Design/ to the app target ({len(text)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
