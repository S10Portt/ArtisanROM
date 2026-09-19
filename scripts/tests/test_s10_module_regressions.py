"""Exercise the shipped shell fragments in isolated work directories."""
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


class ModuleTest(unittest.TestCase):
    def test_floating_feature_prefix_and_operations(self):
        source = (ROOT/'scripts/utils/module_utils.sh').read_text()
        function = source.split('SET_FLOATING_FEATURE_CONFIG()\n', 1)[1].split('\n# SET_PROP_IF_DIFF', 1)[0]
        function = 'SET_FLOATING_FEATURE_CONFIG()\n'+function
        with tempfile.TemporaryDirectory() as d:
            xml = Path(d)/'system/system/etc/floating_feature.xml'
            xml.parent.mkdir(parents=True)
            xml.write_text('<SecFloatingFeatureSet>\n    <TEST_LONG>keep</TEST_LONG>\n</SecFloatingFeatureSet>\n')
            def run(commands):
                script = '''set -e
WORK_DIR="$1"
_CHECK_NON_EMPTY_PARAM() { test -n "$2"; }
LOG() { :; }
LOGE() { echo "$*" >&2; }
'''+function+'\n'+commands
                return subprocess.run(['bash', '-c', script, 'fixture', d], capture_output=True)
            result = run('SET_FLOATING_FEATURE_CONFIG TEST first\nSET_FLOATING_FEATURE_CONFIG TEST second')
            self.assertEqual(result.returncode, 0, result.stderr)
            tree = ET.parse(xml)
            self.assertEqual(tree.findtext('TEST'), 'second')
            self.assertEqual(tree.findtext('TEST_LONG'), 'keep')
            self.assertEqual(run('SET_FLOATING_FEATURE_CONFIG TEST --delete').returncode, 0)
            self.assertIsNone(ET.parse(xml).find('TEST'))
            xml.write_text('<SecFloatingFeatureSet>\n<TEST>one</TEST>\n<TEST>two</TEST>\n</SecFloatingFeatureSet>\n')
            before = xml.read_bytes()
            self.assertNotEqual(run('SET_FLOATING_FEATURE_CONFIG TEST bad').returncode, 0)
            self.assertEqual(xml.read_bytes(), before)

    def test_cpuset_idempotence_and_partial_rejection(self):
        source = (ROOT/'platform/exynos9820/patches/stock_blobs/customize.sh').read_text()
        block = source[source.index('    _CPUSET_RC='):source.index('    unset _CPUSET_RC')]
        with tempfile.TemporaryDirectory() as d:
            rc = Path(d)/'vendor/etc/init/init.exynos9820.rc'
            rc.parent.mkdir(parents=True)
            rc.write_text('on init\n    # stock commands\n')
            def run():
                script = 'set -e\nWORK_DIR="$1"\nLOGE() { echo "$*" >&2; }\napply() {\n'+block+'\n}\napply'
                return subprocess.run(['bash', '-c', script, 'fixture', d], capture_output=True)
            self.assertEqual(run().returncode, 0)
            complete = rc.read_bytes()
            self.assertIn(b'mkdir /dev/cpuset/foreground-boost', complete)
            self.assertEqual(run().returncode, 0)
            self.assertEqual(rc.read_bytes(), complete)
            for partial in ('on init\n    mkdir /dev/cpuset/sf\n',
                            'on init\n    mkdir /dev/cpuset/foreground-boost\n'):
                rc.write_text(partial)
                self.assertNotEqual(run().returncode, 0)
                self.assertEqual(rc.read_text(), partial)


if __name__ == '__main__':
    unittest.main()
