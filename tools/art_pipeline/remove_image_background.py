from __future__ import annotations

import argparse
import colorsys
from pathlib import Path

from PIL import Image, ImageFilter


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Remove a keyed background and save a transparent WebP image.')
    parser.add_argument('source', type=Path)
    parser.add_argument('target', type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    source: Path = args.source
    target: Path = args.target
    image = Image.open(source).convert('RGBA')
    mask = Image.new('L', image.size, 255)
    mask_pixels = mask.load()
    source_pixels = image.load()
    if mask_pixels is None or source_pixels is None:
        raise RuntimeError('Image pixel access is unavailable')

    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, _ = source_pixels[x, y]
            hue, saturation, _ = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
            keyed = (
                0.20 <= hue <= 0.40
                and saturation >= 0.22
                and green > red * 1.08
                and green > blue * 1.18
                and green > 105
            )
            mask_pixels[x, y] = 0 if keyed else 255

    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.65))
    image.putalpha(mask)
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, 'WEBP', lossless=True, method=6)
    print(f'Saved transparent cutout to {target}')


if __name__ == '__main__':
    main()
