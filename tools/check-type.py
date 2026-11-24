#!/usr/bin/env python3
"""Type-system check for the iOS app and widgets (rules T1-T5 in Shared/Typography.swift).

Every font call in a .swift file must come from a role in Shared/Typography.swift. This script fails on a call that
skips the roles. It runs as a pre-build script, so a new violation fails the build.

Usage: check-type.py [ios-root]       exit 1 and print each violation as file:line: rule message
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent)
SCAN = ["CactusPeak", "CactusPeakWidgets", "Shared"]
# The one file allowed to build fonts.
OWNER = "Shared/Typography.swift"

RULES = [
    ("T1", re.compile(r"\bFont\.custom\(|\.custom\(\s*\"|UIFont\(name:|\.archivo\w*\(|\.eyebrowStyle\("),
     "Archivo comes only from .brandFont(_:)"),
    ("T2", re.compile(r"\.font\(\s*(Font)?\.(largeTitle|title|title2|title3)\b"),
     "display text styles are brand headlines: use .brandFont(_:) for text or .symbolFont(_:) for an SF Symbol"),
    ("T3", re.compile(r"design:\s*\.monospaced|\.monospaced\(\)"),
     "SF Mono comes only from .codeFont(_:)"),
    ("T4", re.compile(r"design:\s*\.(rounded|serif)|\.fontDesign\(|\.fontWidth\("),
     "SF Rounded comes only from .countFont(_:) or .monogramFont(diameter:); no other design or width"),
    ("T5", re.compile(r"\.font\(\s*(Font)?\.system\(\s*size:"),
     "no fixed point sizes in .font(_:): use a role, or .symbolFont(_:) for an SF Symbol"),
]


def strip_comment(line: str) -> str:
    # Good enough for this codebase: a // outside a string starts a comment.
    in_str = False
    for i, ch in enumerate(line):
        if ch == '"' and (i == 0 or line[i - 1] != "\\"):
            in_str = not in_str
        elif not in_str and line.startswith("//", i):
            return line[:i]
    return line


def main() -> int:
    found = []
    for top in SCAN:
        for path in sorted((ROOT / top).rglob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            if rel == OWNER:
                continue
            for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                line = strip_comment(raw)
                for rule, pattern, message in RULES:
                    if pattern.search(line):
                        found.append(f"{ROOT / rel}:{n}: error: [{rule}] {message}")
    for f in found:
        print(f)
    if found:
        print(f"check-type: {len(found)} violation(s). Rules: {OWNER}", file=sys.stderr)
        return 1
    print("check-type: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
