from pathlib import Path
import importlib.util
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[1] / 'install_cjk_font.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

class CommonFontTest(unittest.TestCase):
    def test_rejects_subset_before_replacing_working_font(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / installer.FONT_PATH
            target.parent.mkdir(parents=True)
            target.write_bytes(b'working font')
            subset = root / 'subset.otf'
            subset.write_bytes(b'text subset')
            with self.assertRaisesRegex(ValueError, 'pinned common'):
                installer.install_font(root, subset)
            self.assertEqual(target.read_bytes(), b'working font')

    def test_check_rejects_damaged_or_subset_runtime(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / installer.FONT_PATH
            target.parent.mkdir(parents=True)
            target.write_bytes(b'subset')
            with self.assertRaisesRegex(ValueError, 'pinned common'):
                installer.install_font(root, check=True)

if __name__ == '__main__':
    unittest.main()
