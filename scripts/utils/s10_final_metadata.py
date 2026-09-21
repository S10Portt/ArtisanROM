#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate complete S10 output metadata before caching or packaging."""
import argparse
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from s10_metadata_plan import rows, context_key, item_kind


def raise_walk_error(error):
    raise error


def metadata(root):
    """Check complete final-tree metadata, after APK/RRO output creation."""
    for part in ('system', 'vendor', 'product'):
        if (root/part).is_symlink() or not (root/part).is_dir():
            raise ValueError('missing or linked work partition: ' + part)
        fs = rows(root/'configs'/('fs_config-'+part), 'fs')
        fc = rows(root/'configs'/('file_context-'+part), 'context')
        paths = set()
        for parent, dirs, files in os.walk(root/part, followlinks=False, onerror=raise_walk_error):
            for name in dirs + files:
                path = Path(parent)/name
                item_kind(path)  # Refuse unsupported special inodes.
                relative = path.relative_to(root/part).as_posix()
                paths.add(relative if part == 'system' else part+'/'+relative)
        expected_contexts = {context_key(path) for path in paths}
        problems = {
            'missing ownership': paths - fs.keys(),
            'missing labels': expected_contexts - fc.keys(),
            'stale ownership': fs.keys() - paths - {'', part},
            'stale labels': fc.keys() - expected_contexts - {'/', '/'+part},
            'duplicate ownership': {key for key, values in fs.items() if len(values) != 1},
            'duplicate labels': {key for key, values in fc.items() if len(values) != 1},
        }
        for reason, keys in problems.items():
            if keys:
                raise ValueError(part + ': ' + reason + ': ' + ', '.join(sorted(keys)[:10]))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    try:
        metadata(args.root)
    except (OSError, ValueError) as error:
        raise SystemExit('S10 final metadata: ' + str(error))
