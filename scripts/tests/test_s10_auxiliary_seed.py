from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/utils'))
from s10_auxiliary_images import ranges

class AuxiliaryRangesTest(unittest.TestCase):
    def test_full_new_ranges(self):
        self.assertEqual(ranges(b'4\n2\n0\n0\nnew 2,0,1\nnew 2,1,2\n',8192),8192)
    def test_invalid_ranges(self):
        for line in ('new 2,1,2','new 2,0,3','erase 2,0,1','new 4,0,1,0,1'):
            with self.subTest(line=line),self.assertRaises(ValueError):
                ranges(('4\n2\n0\n0\n'+line+'\n').encode(),8192)


class KernelPackageScopeTest(unittest.TestCase):
    def test_auxiliaries_only_in_package_scope(self):
        import subprocess
        import tempfile
        source=(ROOT/'scripts/utils/s10_inputs.sh').read_text()
        function=source[source.index('CHECK_S10_KERNEL_SET()'):source.index('CHECK_S10_LAYOUT()')]
        with tempfile.TemporaryDirectory() as d:
            for name in ('boot','dtb','dtbo','odm','prism','optics'):
                (Path(d)/(name+'.img')).write_bytes(b'fixture')
            def run(mode):
                return subprocess.run(['bash','-c',function+'\nCHECK_S10_KERNEL_SET "$1" "$2"','fixture',d,mode],capture_output=True).returncode
            self.assertEqual(run('package'),0)
            self.assertNotEqual(run('kernel'),0)
            (Path(d)/'up_param.img').write_bytes(b'bad')
            self.assertNotEqual(run('package'),0)


class AuxiliaryPreparationTest(unittest.TestCase):
    def test_wrong_source_leaves_no_output(self):
        import tempfile
        from s10_auxiliary_images import prepare
        with tempfile.TemporaryDirectory() as d:
            source=Path(d)/'source.zip';source.write_bytes(b'not approved')
            output=Path(d)/'output'
            with self.assertRaises(ValueError):prepare(source,output)
            self.assertFalse(output.exists())

    def test_work_tree_rejects_auxiliary(self):
        import tempfile
        from s10_auxiliary_contract import check
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            check(root,'work')
            (root/'odm').mkdir()
            with self.assertRaises(ValueError):check(root,'work')
