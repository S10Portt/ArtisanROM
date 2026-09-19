"""Keep diagnostic artifacts out of the source tree, including through aliases."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'scripts/diagnostics'))
from external_output import external_output_parent


class ExternalOutputTest(unittest.TestCase):
    def test_source_and_descendants_rejected(self):
        for path in (ROOT, ROOT/'docs/new-record', ROOT/'out/report'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                external_output_parent(path)

    def test_alias_into_source_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            alias = Path(d)/'alias'
            alias.symlink_to(ROOT, target_is_directory=True)
            with self.assertRaises(ValueError):
                external_output_parent(alias/'new-record')

    def test_external_and_default(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(external_output_parent(d), Path(d).resolve())
            with patch.dict('os.environ', {'ARTISANROM_RECORDS_DIR': d}):
                self.assertEqual(external_output_parent(), Path(d).resolve())
        with patch.dict('os.environ', {'ARTISANROM_RECORDS_DIR': ''}):
            self.assertEqual(external_output_parent(), ROOT.parent/'ArtisanROM_records')


if __name__ == '__main__':
    unittest.main()
