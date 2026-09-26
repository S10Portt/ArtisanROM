#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Optional unsigned diagnostic package; normal ROMs already supply auxiliaries."""
import argparse
import hashlib
from pathlib import Path
import sys
import tempfile
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'utils'))
from s10_auxiliary_images import NAMES, REPO, prepare, digest


def build(source,output):
    if output.resolve().is_relative_to(REPO) or output.exists(): raise ValueError('new external output required')
    with tempfile.TemporaryDirectory(prefix='s10-seed-') as tmp:
        images=Path(tmp)/'images'; prepare(source,images)
        updater=(REPO/'prebuilts/bootable/deprecated-ota/updater').read_bytes()
        if hashlib.sha256(updater).hexdigest()!='28378c9dcae8a0e6035e5f90e66c2a128eab3cce2982e43aa33424542507664a': raise ValueError('unexpected updater')
        script='assert(getprop("ro.boot.em.model") == "SM-G973F");\n'
        script+='assert(package_extract_file("layout-preflight.sh", "/tmp/layout-preflight.sh"));\n'
        script+='set_metadata("/tmp/layout-preflight.sh", "uid", 0, "gid", 0, "mode", 0755);\n'
        script+='assert(run_program("/tmp/layout-preflight.sh") == "0");\n'
        for p in NAMES: script+=f'assert(package_extract_file("{p}.img", "/dev/block/by-name/{p}"));\n'
        with output.open('xb') as raw,zipfile.ZipFile(raw,'w',compression=zipfile.ZIP_DEFLATED) as z:
            z.writestr('META-INF/com/google/android/update-binary',updater)
            z.writestr('META-INF/com/google/android/updater-script',script)
            z.writestr('layout-preflight.sh',(REPO/'target/beyond1lte/installer/layout-preflight.sh').read_bytes())
            for p in NAMES:z.write(images/(p+'.img'),p+'.img')
    with output.open('rb') as stream: print(digest(stream))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('source_zip',type=Path);p.add_argument('output_zip',type=Path)
    a=p.parse_args();build(a.source_zip,a.output_zip)
