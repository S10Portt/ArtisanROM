#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Enforce the current no-auxiliary-write staging boundary, not boot approval."""
from pathlib import Path
import os
import sys


def check(root, stage):
    if root.is_symlink() or not root.is_dir():
        raise ValueError('invalid S10 staging directory')
    if stage == 'work':
        names = ('odm','prism','optics','up_param.bin')
    elif stage == 'package':
        names = tuple(p+suffix for p in ('odm','prism','optics','up_param')
                      for suffix in ('.img','.bin','.new.dat','.new.dat.br','.patch.dat','.transfer.list'))
    else:
        raise ValueError('unsupported auxiliary contract stage')
    present = [name for name in names if os.path.lexists(root/name)]
    if present:
        raise ValueError('unapproved auxiliary payloads (no automatic removal): '+', '.join(present))


if __name__ == '__main__':
    try:
        if len(sys.argv) != 3: raise ValueError('usage: s10_auxiliary_contract.py work|package ROOT')
        check(Path(sys.argv[2]),sys.argv[1])
    except (OSError,ValueError) as exc:
        print(f'S10 auxiliary contract: {exc}',file=sys.stderr)
        sys.exit(1)
