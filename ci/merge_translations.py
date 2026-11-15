#!/usr/bin/env python3
"""Merge ci/translations.json into Design/Localizable.xcstrings.

The String Catalog is keyed by the English UI string itself: SwiftUI's
`Text("Servers")` already looks up "Servers" in Localizable.strings, so a
translation needs no source change — only a catalog entry whose key is that
literal. This script adds/updates those entries (en = the key, ru = the
translation) and leaves every existing `csqtt.*` key untouched.

Usage: python ci/merge_translations.py
"""

from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
CATALOG = os.path.join(ROOT, "VKTurnProxy", "VKTurnProxy", "Design", "Localizable.xcstrings")
TRANSLATIONS = os.path.join(HERE, "translations.json")
STRINGS = os.path.join(HERE, "ui_strings.json")


def main() -> int:
    with open(CATALOG, encoding="utf-8") as fh:
        catalog = json.load(fh)
    with open(TRANSLATIONS, encoding="utf-8") as fh:
        translations = json.load(fh)

    known = set(catalog["strings"])
    # Report keys that are not in the extracted set: a typo here would be a
    # translation that never matches anything at runtime.
    if os.path.exists(STRINGS):
        with open(STRINGS, encoding="utf-8") as fh:
            extracted = set(json.load(fh))
        unknown = sorted(set(translations) - extracted)
        if unknown:
            print(f"warning: {len(unknown)} translation key(s) not seen in sources:")
            for key in unknown[:10]:
                print("  -", key)

    added = updated = 0
    for english, russian in translations.items():
        entry = catalog["strings"].setdefault(english, {})
        localizations = entry.setdefault("localizations", {})
        if english in known:
            updated += 1
        else:
            added += 1
        localizations["en"] = {"stringUnit": {"state": "translated", "value": english}}
        localizations["ru"] = {"stringUnit": {"state": "translated", "value": russian}}

    with open(CATALOG, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(catalog, fh, ensure_ascii=False, indent=2, sort_keys=True)
        fh.write("\n")

    total = len(catalog["strings"])
    print(f"catalog: {added} added, {updated} updated, {total} keys total")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
