#!/usr/bin/env python3
"""Slice AI-generated sprite sheets and prepare seamless backgrounds/terrain for the game.

Raw masters stay outside the project (default /home/ubuntu/yoshi_art/raw).
Usage: python3 tools/art_pipeline/build_game_art.py [--only sprites|bg|tex] [--raw DIR]
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "game"

# sheet -> (cols, rows, [ (cell_index, set_name, frame_name, anchor) ... ], {set_name: store_height})
SHEETS = {
    "hero_sheet": (3, 2, [
        (0, "hero", "idle", "bottom"), (1, "hero", "walk_1", "bottom"), (2, "hero", "walk_2", "bottom"),
        (3, "hero", "jump", "bottom"), (4, "hero", "flutter", "bottom"), (5, "hero", "throw", "bottom")],
        {"hero": 176}),
    "enemy_a": (3, 2, [
        (0, "acorn", "walk_1", "bottom"), (1, "acorn", "walk_2", "bottom"), (2, "acorn", "flat", "bottom"),
        (3, "beetle", "walk_1", "bottom"), (4, "beetle", "walk_2", "bottom"), (5, "beetle", "shell", "bottom")],
        {"acorn": 112, "beetle": 108}),
    "enemy_b": (3, 2, [
        (0, "bat", "fly_1", "center"), (1, "bat", "fly_2", "center"),
        (2, "hedgehog", "walk_1", "bottom"), (3, "hedgehog", "walk_2", "bottom"),
        (4, "ghost", "chase", "center"), (5, "ghost", "shy", "center")],
        {"bat": 104, "hedgehog": 104, "ghost": 132}),
    "enemy_c": (3, 2, [
        (0, "skeleton", "walk_1", "bottom"), (1, "skeleton", "walk_2", "bottom"), (2, "skeleton", "pile", "bottom"),
        (3, "fire_spirit", "idle", "center"), (4, "cannonball", "fly", "center"), (5, "cannon", "idle", "bottom")],
        {"skeleton": 150, "fire_spirit": 96, "cannonball": 84, "cannon": 124}),
    "boss_sheet": (2, 2, [
        (0, "golem", "idle", "bottom"), (1, "golem", "stomp", "bottom"), (2, "golem", "hurt", "bottom"),
        (3, "boss_fireball", "fly", "center")],
        {"golem": 380, "boss_fireball": 96}),
    "items_sheet": (4, 3, [
        (0, "items", "coin", "center"), (1, "items", "medal", "center"), (2, "items", "heart", "center"),
        (3, "items", "apple", "center"), (4, "items", "star", "center"), (5, "items", "egg", "center"),
        (6, "items", "spring", "bottom"), (7, "items", "spikeball", "center"), (8, "blocks", "item", "square"),
        (9, "blocks", "used", "square"), (10, "blocks", "brick", "square"), (11, "blocks", "crate", "square")],
        {"items": 0, "blocks": 104}),
    "props_sheet": (3, 2, [
        (0, "props", "goal", "bottom"), (1, "props", "checkpoint", "bottom"), (2, "props", "stump", "bottom"),
        (3, "props", "log_platform", "center"), (4, "props", "rock_platform", "center"), (5, "props", "spikes", "bottom")],
        {"props": 0}),
}
# Individually sized sprites (set height 0): longest edge in stored pixels.
ITEM_SIZES = {"coin": 72, "medal": 104, "heart": 72, "apple": 80, "star": 88, "egg": 60, "spring": 88, "spikeball": 84,
              "goal": 440, "checkpoint": 230, "stump": 420, "log_platform": 420, "rock_platform": 420, "spikes": 320}


def cell_sprites(path: Path, cols: int, rows: int):
    image = Image.open(path).convert("RGBA")
    rgba = np.array(image)
    alpha = rgba[:, :, 3]
    mask = alpha > 20
    labels, count = ndimage.label(ndimage.binary_dilation(mask, iterations=6))
    h, w = alpha.shape
    cells = {}
    for index, box in enumerate(ndimage.find_objects(labels), start=1):
        if box is None:
            continue
        component = (labels[box] == index) & mask[box]
        area = int(component.sum())
        if area < 150:
            continue
        ys, xs = np.nonzero(component)
        cy = box[0].start + ys.mean()
        cx = box[1].start + xs.mean()
        cell = int(min(rows - 1, cy // (h / rows)) * cols + min(cols - 1, cx // (w / cols)))
        cells.setdefault(cell, []).append((area, box, index))
    result = {}
    for cell, parts in cells.items():
        biggest = max(p[0] for p in parts)
        keep = np.zeros_like(mask)
        for area, box, index in parts:
            # Drop stray specks far smaller than the subject; keep attached effects.
            if area >= biggest * 0.004:
                keep[box] |= (labels[box] == index) & mask[box]
        ys, xs = np.nonzero(keep)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        crop = rgba[y0:y1, x0:x1].copy()
        crop[:, :, 3] = np.where(keep[y0:y1, x0:x1] | (alpha[y0:y1, x0:x1] > 0) & ndimage.binary_dilation(keep[y0:y1, x0:x1], iterations=2), crop[:, :, 3], 0)
        result[cell] = Image.fromarray(crop, "RGBA")
    return result


def clean_alpha(im: Image.Image) -> Image.Image:
    arr = np.array(im)
    a = arr[:, :, 3].astype(np.float32)
    a[a < 12] = 0
    arr[:, :, 3] = a.astype(np.uint8)
    # Zero colour under fully transparent pixels to avoid dark/bright halos when filtered.
    arr[arr[:, :, 3] == 0, :3] = 0
    return Image.fromarray(arr, "RGBA")


def save(im: Image.Image, path: Path, lossless=False, quality=92):
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "WEBP", lossless=lossless, quality=quality, method=6)


def build_sprites(raw: Path, report: dict):
    for sheet, (cols, rows, frames, heights) in SHEETS.items():
        src = raw / f"{sheet}.png"
        if not src.exists():
            print("missing", src)
            continue
        sprites = cell_sprites(src, cols, rows)
        missing = [f for f in frames if f[0] not in sprites]
        if missing:
            raise SystemExit(f"{sheet}: cells without sprite {[m[0] for m in missing]}")
        by_set = {}
        for cell, set_name, frame, anchor in frames:
            by_set.setdefault(set_name, []).append((sprites[cell], frame, anchor))
        for set_name, members in by_set.items():
            target = heights[set_name]
            if target == 0:
                for im, frame, anchor in members:
                    edge = ITEM_SIZES[frame]
                    scale = edge / max(im.size)
                    out = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
                    out = clean_alpha(out)
                    dest = OUT / set_name / f"{frame}.webp"
                    save(out, dest)
                    report[str(dest.relative_to(ROOT))] = list(out.size)
                continue
            if members[0][2] == "square":
                for im, frame, _ in members:
                    out = clean_alpha(im.resize((target, target), Image.LANCZOS))
                    dest = OUT / set_name / f"{frame}.webp"
                    save(out, dest)
                    report[str(dest.relative_to(ROOT))] = list(out.size)
                continue
            scale = target / max(im.height for im, _, _ in members)
            scaled = [(im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS), frame, anchor) for im, frame, anchor in members]
            cw = max(im.width for im, _, _ in scaled) + 8
            ch = max(im.height for im, _, _ in scaled) + 8
            for im, frame, anchor in scaled:
                canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
                x = (cw - im.width) // 2
                y = ch - 4 - im.height if anchor == "bottom" else (ch - im.height) // 2
                canvas.alpha_composite(im, (x, y))
                canvas = clean_alpha(canvas)
                dest = OUT / set_name / f"{frame}.webp"
                save(canvas, dest)
                report[str(dest.relative_to(ROOT))] = [cw, ch]


def seamless_x(arr: np.ndarray, blend: int) -> np.ndarray:
    w = arr.shape[1]
    out = arr[:, : w - blend].astype(np.float32).copy()
    t = np.linspace(0.0, 1.0, blend, dtype=np.float32)[None, :, None]
    out[:, :blend] = arr[:, :blend].astype(np.float32) * t + arr[:, w - blend:].astype(np.float32) * (1 - t)
    return out


def seamless_y(arr: np.ndarray, blend: int) -> np.ndarray:
    return np.transpose(seamless_x(np.transpose(arr, (1, 0, 2)), blend), (1, 0, 2))


def build_backgrounds(raw: Path, report: dict):
    for world in range(1, 7):
        src = raw / f"bg_w{world}_fix.png"
        if not src.exists():
            src = raw / f"bg_w{world}.png"
        arr = np.array(Image.open(src).convert("RGB"))
        out = seamless_x(arr, int(arr.shape[1] * 0.08))
        im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")
        im = im.resize((round(im.width * 900 / im.height), 900), Image.LANCZOS)
        dest = OUT / "backgrounds" / f"world_{world}.webp"
        save(im.convert("RGB"), dest, quality=86)
        report[str(dest.relative_to(ROOT))] = list(im.size)


def build_textures(raw: Path, report: dict):
    for name in ["grass", "plains", "cave", "cloud", "forest", "castle", "lava"]:
        src = raw / f"tex_{name}.png"
        if not src.exists():
            print("missing", src)
            continue
        arr = np.array(Image.open(src).convert("RGB")).astype(np.float32)
        top = seamless_x(arr, int(arr.shape[1] * 0.1))
        top_im = Image.fromarray(np.clip(top, 0, 255).astype(np.uint8)).resize((256, 256), Image.LANCZOS)
        h = arr.shape[0]
        lower = arr[int(h * 0.42):, :, :]
        fill = seamless_y(seamless_x(lower, int(lower.shape[1] * 0.1)), int(lower.shape[0] * 0.14))
        fill_im = Image.fromarray(np.clip(fill, 0, 255).astype(np.uint8)).resize((256, 256), Image.LANCZOS)
        for suffix, im in (("top", top_im), ("fill", fill_im)):
            dest = OUT / "terrain" / f"{name}_{suffix}.webp"
            save(im, dest, quality=90)
            report[str(dest.relative_to(ROOT))] = list(im.size)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw", default="/home/ubuntu/yoshi_art/raw")
    parser.add_argument("--only", choices=["sprites", "bg", "tex"])
    args = parser.parse_args()
    raw = Path(args.raw)
    report = {}
    if args.only in (None, "sprites"):
        build_sprites(raw, report)
    if args.only in (None, "bg"):
        build_backgrounds(raw, report)
    if args.only in (None, "tex"):
        build_textures(raw, report)
    print(json.dumps(report, indent=0))


if __name__ == "__main__":
    main()
