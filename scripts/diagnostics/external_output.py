#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Resolve diagnostic output outside the source checkout, including symlink aliases."""
import os
from pathlib import Path
import sys

SOURCE_ROOT = Path(__file__).resolve().parents[2]


def external_output_parent(path=None):
    if path is None:
        path = os.environ.get('ARTISANROM_RECORDS_DIR') or SOURCE_ROOT.parent/'ArtisanROM_records'
    resolved = Path(path).expanduser().resolve()
    if resolved == SOURCE_ROOT or SOURCE_ROOT in resolved.parents:
        raise ValueError('diagnostic output must be outside the ROM source checkout')
    return resolved


if __name__ == '__main__':
    try:
        if len(sys.argv) > 2:
            raise ValueError('usage: external_output.py [OUTPUT_PARENT]')
        output = external_output_parent(sys.argv[1] if len(sys.argv) == 2 else None)
        output.mkdir(parents=True, exist_ok=True)
        print(output)
    except (OSError, ValueError) as exc:
        sys.exit(str(exc))
