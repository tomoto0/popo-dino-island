#!/usr/bin/env python3
"""Import the 24 stage-specific BGM tracks from the verified CC0 source archive.

Download source:
https://opengameart.org/content/42-monster-rpg-2-music-tracks

Example:
  python3 tools/import_cc0_bgm.py "/path/to/Monster RPG 2 OGG Music - Revised"

This only copies the original OGG Vorbis files.  See docs/audio-credits.md for
track-to-stage assignments, source URL and license information.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "assets" / "game" / "audio" / "stages"

# Stage ID -> original CC0 source filename.
TRACKS = {
    "w1_1": "jungle.ogg",
    "w1_2": "beach.ogg",
    "w1_3": "happtroll.ogg",
    "w1_4": "battle.ogg",
    "w2_1": "seaside_repaired.ogg",
    "w2_2": "Flowey.ogg",
    "w2_3": "loadsave.ogg",
    "w2_4": "boss.ogg",
    "w3_1": "underground.ogg",
    "w3_2": "moon.ogg",
    "w3_3": "chase.ogg",
    "w3_4": "fortress.ogg",
    "w4_1": "mountains.ogg",
    "w4_2": "moon2.ogg",
    "w4_3": "shmup2.ogg",
    "w4_4": "Muttrace.ogg",
    "w5_1": "forest.ogg",
    "w5_2": "shyzu.ogg",
    "w5_3": "monastery.ogg",
    "w5_4": "burned_village.ogg",
    "w6_1": "volcano.ogg",
    "w6_2": "castle.ogg",
    "w6_3": "title.ogg",
    "w6_4": "final_boss.ogg",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="Copy CC0 stage BGM into the game assets.")
    parser.add_argument("source_dir", type=Path, help="Extracted Monster RPG 2 OGG directory")
    args = parser.parse_args()

    source_dir = args.source_dir.resolve()
    if not source_dir.is_dir():
        raise SystemExit(f"Source directory does not exist: {source_dir}")

    missing = [name for name in TRACKS.values() if not (source_dir / name).is_file()]
    if missing:
        raise SystemExit("Archive is missing expected tracks: " + ", ".join(missing))

    DESTINATION.mkdir(parents=True, exist_ok=True)
    for stage_id, source_name in TRACKS.items():
        source = source_dir / source_name
        destination = DESTINATION / f"{stage_id}.ogg"
        shutil.copy2(source, destination)
        print(f"{stage_id}\t{source_name}\t{destination.stat().st_size}\t{sha256(destination)}")


if __name__ == "__main__":
    main()
