# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the real build loop with exclusive metadata completion fixtures."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ApkSchedulingTests(unittest.TestCase):
    def run_loop(self, fail=False):
        source = (ROOT/'scripts/make_rom.sh').read_text()
        start = source.index('    if [ -d "$APKTOOL_DIR" ]; then', source.index('Applying ROM mods'))
        end = source.index('    if [[ "$TARGET_CODENAME" == "beyond1lte" ]]; then', source.index('        LOG_STEP_OUT', start))
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'scripts').mkdir()
            cache = root/'apktool'
            for name in ('first.jar', 'second.jar'):
                (cache/'system/framework'/name).mkdir(parents=True)
            mock = root/'scripts/apktool.sh'
            mock.write_text('''#!/bin/bash
set -e
mkdir "$COMPLETION_LOCK"
trap 'rmdir "$COMPLETION_LOCK"' EXIT
sleep 0.1
printf '%s\\n' "$*" >> "$CALLS"
[[ "$FAIL_BUILD" == false ]]
''')
            mock.chmod(0o755)
            shell = 'set -e\nLOG_STEP_IN() { :; }\nLOG_STEP_OUT() { :; }\nLOGE() { echo "$*" >&2; }\n' + source[start:end]
            env = dict(os.environ, SRC_DIR=str(root), OUT_DIR=str(root), APKTOOL_DIR=str(cache),
                       TARGET_CODENAME='beyond1lte', COMPLETION_LOCK=str(root/'lock'),
                       CALLS=str(root/'calls'), FAIL_BUILD=str(fail).lower())
            result = subprocess.run(['bash', '-c', shell], env=env, capture_output=True, text=True)
            calls = (root/'calls').read_text().splitlines()
            return result, calls

    def test_completion_does_not_overlap(self):
        result, calls = self.run_loop()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 2)

    def test_failed_apk_stops_build(self):
        result, calls = self.run_loop(fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)
