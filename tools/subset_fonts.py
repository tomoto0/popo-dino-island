#!/usr/bin/env python3
"""Subset M PLUS Rounded 1c (OFL) to the characters the game uses.

Kana, CJK/fullwidth punctuation, ASCII and symbols are always kept; kanji are taken
from every text source in the project, so re-run this after changing any Japanese text:

    python3 tools/subset_fonts.py /path/to/MPLUSRounded1c-Medium.ttf /path/to/MPLUSRounded1c-ExtraBold.ttf
"""
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/game/fonts"
SOURCES = ["scripts/**/*.gd", "data/stages/*.json", "localization/*.json", "autoload/*.gd", "web/*.html"]
RANGES = [
    (0x20, 0x7E), (0xA0, 0xFF), (0x2010, 0x206F), (0x2160, 0x216F), (0x2190, 0x21FF),
    (0x25A0, 0x25FF), (0x2600, 0x266F), (0x3000, 0x30FF), (0xFF00, 0xFFEF),
]


def used_chars() -> set[int]:
    chars: set[int] = set()
    for pattern in SOURCES:
        for path in ROOT.glob(pattern):
            chars.update(ord(c) for c in path.read_text(encoding="utf-8", errors="ignore") if ord(c) >= 0x3400)
    for lo, hi in RANGES:
        chars.update(range(lo, hi + 1))
    return chars


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    chars = used_chars()
    for src in sys.argv[1:]:
        font = TTFont(src)
        cmap = font.getBestCmap()
        keep = sorted(c for c in chars if c in cmap)
        options = subset.Options()
        options.flavor = "woff2"
        options.layout_features = ["*"]
        options.name_IDs = ["*"]
        options.notdef_outline = True
        sub = subset.Subsetter(options)
        sub.populate(unicodes=keep)
        sub.subset(font)
        name = pathlib.Path(src).stem + ".subset.woff2"
        font.flavor = "woff2"
        font.save(OUT / name)
        print(name, len(keep), "codepoints", (OUT / name).stat().st_size, "bytes")


if __name__ == "__main__":
    main()
