from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Extract a trimmed video segment into ordered PNG animation frames.')
    parser.add_argument('source', type=Path)
    parser.add_argument('target_dir', type=Path)
    parser.add_argument('--fps', type=float, default=12.0)
    parser.add_argument('--start', type=float, default=0.0)
    parser.add_argument('--duration', type=float)
    parser.add_argument('--prefix', default='frame')
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    source: Path = args.source
    target_dir: Path = args.target_dir
    fps: float = args.fps
    start: float = args.start
    duration: float | None = args.duration
    prefix: str = args.prefix

    if not source.is_file():
        raise FileNotFoundError(f'Video source not found: {source}')
    if fps <= 0.0:
        raise ValueError('FPS must be positive')
    if start < 0.0:
        raise ValueError('Start time cannot be negative')
    if duration is not None and duration <= 0.0:
        raise ValueError('Duration must be positive')
    if not prefix or '/' in prefix or '\\' in prefix:
        raise ValueError('Prefix must be a non-empty filename prefix')

    ffmpeg = shutil.which('ffmpeg')
    if ffmpeg is None:
        raise RuntimeError('ffmpeg is required to extract animation frames')

    target_dir.mkdir(parents=True, exist_ok=True)
    for existing in target_dir.glob(f'{prefix}_*.png'):
        existing.unlink()

    command: list[str] = [ffmpeg, '-hide_banner', '-loglevel', 'error', '-y']
    if start > 0.0:
        command.extend(['-ss', f'{start:g}'])
    command.extend(['-i', str(source)])
    if duration is not None:
        command.extend(['-t', f'{duration:g}'])
    command.extend(
        [
            '-vf',
            f'fps={fps:g}',
            '-start_number',
            '0',
            str(target_dir / f'{prefix}_%04d.png'),
        ]
    )
    subprocess.run(command, check=True)

    frames = sorted(target_dir.glob(f'{prefix}_*.png'))
    if not frames:
        raise RuntimeError('No frames were extracted from the selected video segment')
    print(f'Extracted {len(frames)} frames from {source} into {target_dir}')


if __name__ == '__main__':
    main()
