from __future__ import annotations

import argparse
import colorsys
from pathlib import Path

from PIL import Image, ImageFilter


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Convert keyed animation frames into aligned WebP sprites.')
    parser.add_argument('source_dir', nargs='?', type=Path)
    parser.add_argument('target_dir', nargs='?', type=Path)
    parser.add_argument('--pattern', default='frame_*.png')
    parser.add_argument('--prefix', default='frame')
    parser.add_argument('--canvas', type=int, default=192)
    parser.add_argument('--content', type=int, default=176)
    parser.add_argument(
        '--state',
        action='append',
        default=[],
        nargs=3,
        metavar=('SOURCE_DIR', 'TARGET_DIR', 'PREFIX'),
        help='Process one state as SOURCE_DIR TARGET_DIR PREFIX. Repeat to process every state in one shared pass.',
    )
    parser.add_argument(
        '--shared-bounds-source',
        action='append',
        default=[],
        type=Path,
        help='Additional state directory included when computing the shared crop and scale. Repeat for every state.',
    )
    parser.add_argument('--report-bounds', action='store_true', help='Print the Alpha bounds of every inspected frame.')
    args = parser.parse_args()
    if args.state:
        if args.source_dir is not None or args.target_dir is not None:
            parser.error('Use either repeated --state arguments or the positional source_dir and target_dir, not both')
    elif args.source_dir is None or args.target_dir is None:
        parser.error('source_dir and target_dir are required unless at least one --state is provided')
    return args


def build_mask(image: Image.Image) -> Image.Image:
    mask = Image.new('L', image.size, 255)
    mask_pixels = mask.load()
    pixels = image.load()
    if mask_pixels is None or pixels is None:
        raise RuntimeError('Image pixel access is unavailable')
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, _ = pixels[x, y]
            hue, saturation, _ = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
            keyed = (
                0.18 <= hue <= 0.45 and saturation >= 0.22 and green > red * 1.06 and green > blue * 1.12 and green > 85
            )
            mask_pixels[x, y] = 0 if keyed else 255
    return mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))


def load_foreground(path: Path, threshold_table: list[int]) -> tuple[Image.Image, tuple[int, int, int, int]]:
    with Image.open(path) as source:
        image = source.convert('RGBA')
    mask = build_mask(image)
    image.putalpha(mask)
    bbox = mask.point(threshold_table).getbbox()
    if bbox is None:
        raise RuntimeError(f'No foreground found in {path}')
    return image, bbox


def process(args: argparse.Namespace) -> None:
    canvas_size: int = args.canvas
    content_size: int = args.content
    if canvas_size <= 0 or content_size <= 0 or content_size > canvas_size:
        raise ValueError('Canvas and content sizes must be positive, with content no larger than canvas')

    if args.state:
        states = [(Path(source), Path(target), prefix) for source, target, prefix in args.state]
    else:
        states = [(args.source_dir, args.target_dir, args.prefix)]

    seen_sources: set[Path] = set()
    seen_targets: set[Path] = set()
    for source_dir, target_dir, _ in states:
        source_resolved = source_dir.resolve()
        target_resolved = target_dir.resolve()
        if source_resolved in seen_sources:
            raise ValueError(f'Each state source directory must be unique: {source_dir}')
        if target_resolved in seen_targets:
            raise ValueError(f'Each state target directory must be unique: {target_dir}')
        seen_sources.add(source_resolved)
        seen_targets.add(target_resolved)

    bounds_sources = [source_dir for source_dir, _, _ in states]
    for shared_source in args.shared_bounds_source:
        if shared_source.resolve() not in seen_sources:
            bounds_sources.append(shared_source)
            seen_sources.add(shared_source.resolve())

    threshold_table = [0 if value <= 28 else 255 for value in range(256)]
    expected_size: tuple[int, int] | None = None
    loaded: dict[Path, tuple[list[Path], list[Image.Image], list[tuple[int, int, int, int]]]] = {}
    inspected: list[tuple[Path, tuple[int, int], tuple[int, int, int, int]]] = []
    shared_boxes: list[tuple[int, int, int, int]] = []
    for source_dir in bounds_sources:
        paths = sorted(source_dir.glob(args.pattern))
        if not paths:
            raise RuntimeError(f'No shared-bounds frames matched {args.pattern} in {source_dir}')
        frames: list[Image.Image] = []
        boxes: list[tuple[int, int, int, int]] = []
        for path in paths:
            image, bbox = load_foreground(path, threshold_table)
            size = image.size
            if expected_size is None:
                expected_size = size
            elif size != expected_size:
                raise ValueError(
                    f'All shared-bounds frames must use the same source dimensions; '
                    f'expected {expected_size}, got {size} in {path}'
                )
            frames.append(image)
            boxes.append(bbox)
            shared_boxes.append(bbox)
            inspected.append((path, size, bbox))
        loaded[source_dir.resolve()] = (paths, frames, boxes)

    if args.report_bounds:
        for path, size, bbox in inspected:
            occupied = (bbox[2] - bbox[0], bbox[3] - bbox[1])
            print(f'Bounds {path}: source={size[0]}x{size[1]} alpha={bbox} occupied={occupied[0]}x{occupied[1]}')

    left = min(box[0] for box in shared_boxes)
    top = min(box[1] for box in shared_boxes)
    right = max(box[2] for box in shared_boxes)
    bottom = max(box[3] for box in shared_boxes)
    union = (left, top, right, bottom)
    width = right - left
    height = bottom - top
    scale = min(content_size / width, content_size / height)
    new_size = (max(1, round(width * scale)), max(1, round(height * scale)))

    for source_dir, target_dir, prefix in states:
        _, frames, _ = loaded[source_dir.resolve()]
        target_dir.mkdir(parents=True, exist_ok=True)
        for index, image in enumerate(frames):
            cropped = image.crop(union).resize(new_size, Image.Resampling.LANCZOS)
            canvas = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
            x = (canvas_size - cropped.width) // 2
            y = canvas_size - cropped.height - 4
            canvas.alpha_composite(cropped, (x, y))
            output = target_dir / f'{prefix}_{index:02d}.webp'
            canvas.save(output, 'WEBP', lossless=True, method=6)

    output_count = sum(len(loaded[source.resolve()][0]) for source, _, _ in states)
    print(
        f'Processed {output_count} frames across {len(states)} states '
        f'using shared union crop {union} from {len(inspected)} inspected frames'
    )


def main() -> None:
    process(parse_args())


if __name__ == '__main__':
    main()
