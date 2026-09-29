from __future__ import annotations

import argparse
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import process_animation_frames as pipeline
from PIL import Image


class ProcessAnimationFramesTest(unittest.TestCase):
    def make_frame(self, path: Path, size: tuple[int, int], foreground: tuple[int, int, int, int]) -> None:
        image = Image.new('RGBA', size, (0, 255, 0, 255))
        pixels = image.load()
        if pixels is None:
            raise RuntimeError('Image pixel access is unavailable')
        left, top, right, bottom = foreground
        for y in range(top, bottom):
            for x in range(left, right):
                pixels[x, y] = (220, 30, 30, 255)
        image.save(path)

    def args(self, states: list[list[str]], *, canvas: int = 40, content: int = 32) -> argparse.Namespace:
        return argparse.Namespace(
            source_dir=None,
            target_dir=None,
            pattern='frame_*.png',
            prefix='frame',
            canvas=canvas,
            content=content,
            state=states,
            shared_bounds_source=[],
            report_bounds=False,
        )

    def test_batch_scans_each_source_frame_once_and_processes_every_state(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            idle_source = root / 'idle-source'
            run_source = root / 'run-source'
            idle_target = root / 'idle-target'
            run_target = root / 'run-target'
            idle_source.mkdir()
            run_source.mkdir()
            self.make_frame(idle_source / 'frame_00.png', (48, 48), (18, 8, 30, 42))
            self.make_frame(idle_source / 'frame_01.png', (48, 48), (17, 9, 31, 42))
            self.make_frame(run_source / 'frame_00.png', (48, 48), (10, 12, 38, 42))
            self.make_frame(run_source / 'frame_01.png', (48, 48), (8, 13, 40, 42))

            states = [
                [str(idle_source), str(idle_target), 'idle'],
                [str(run_source), str(run_target), 'run'],
            ]
            with mock.patch.object(pipeline, 'build_mask', wraps=pipeline.build_mask) as build_mask:
                pipeline.process(self.args(states))

            self.assertEqual(build_mask.call_count, 4)
            self.assertEqual(
                [path.name for path in sorted(idle_target.glob('*.webp'))], ['idle_00.webp', 'idle_01.webp']
            )
            self.assertEqual([path.name for path in sorted(run_target.glob('*.webp'))], ['run_00.webp', 'run_01.webp'])
            for output in [*idle_target.glob('*.webp'), *run_target.glob('*.webp')]:
                with Image.open(output) as image:
                    self.assertEqual(image.size, (40, 40))
                    self.assertEqual(image.getchannel('A').getbbox()[3], 36)

    def test_batch_rejects_mixed_source_dimensions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            idle_source = root / 'idle-source'
            run_source = root / 'run-source'
            idle_source.mkdir()
            run_source.mkdir()
            self.make_frame(idle_source / 'frame_00.png', (48, 48), (18, 8, 30, 42))
            self.make_frame(run_source / 'frame_00.png', (64, 48), (20, 8, 44, 42))
            states = [
                [str(idle_source), str(root / 'idle-target'), 'idle'],
                [str(run_source), str(root / 'run-target'), 'run'],
            ]

            with self.assertRaisesRegex(ValueError, 'same source dimensions'):
                pipeline.process(self.args(states))


if __name__ == '__main__':
    unittest.main()
