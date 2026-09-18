# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-only verification of the selected S10 ESSI QHD replacements."""
import hashlib
import json
from pathlib import Path
import sys
from s10_metadata_plan import rows, context_key, item_kind, check_parents


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(stage, prebuilts, work, ssi):
    if stage not in ('pre', 'post') or ssi != 'essi':
        raise ValueError('unregistered S10 QHD stage/SSI')
    policy = json.loads(Path(__file__).with_suffix('.json').read_text())
    fs = rows(work/'configs/fs_config-system', 'fs')
    fc = rows(work/'configs/file_context-system', 'context')
    for e in policy['entries']:
        key = e['key']; source = prebuilts/e['donor']/key; dest = work/'system'/key
        check_parents(source); check_parents(dest)
        if item_kind(source) != 'file' or digest(source) != e['sha256']:
            raise ValueError('unregistered QHD source content: ' + key)
        # These transfers do not create parent directories or change their policy.
        parent = dest.parent
        while parent != work/'system':
            if item_kind(parent) != 'directory': raise ValueError('invalid QHD parent')
            parent_key = parent.relative_to(work/'system').as_posix()
            if len(fs.get(parent_key, [])) != 1 or len(fc.get(context_key(parent_key), [])) != 1:
                raise ValueError('missing/ambiguous QHD parent metadata: ' + parent_key)
            parent = parent.parent
        kind = item_kind(dest, missing=True)
        if kind is None:
            if stage != 'pre' or e['original_sha256'] is not None or key in fs or context_key(key) in fc:
                raise ValueError('unexpected missing QHD file: ' + key)
        else:
            if kind != 'file' or fs.get(key) != [tuple(e['fs'])] or fc.get(context_key(key)) != [(e['label'],)]:
                raise ValueError('QHD destination policy differs: ' + key)
            allowed = {e['sha256']}
            if stage == 'pre' and e['original_sha256']: allowed.add(e['original_sha256'])
            if digest(dest) not in allowed: raise ValueError('unregistered QHD destination content: ' + key)


if __name__ == '__main__':
    try:
        verify(sys.argv[1], Path(sys.argv[2]).absolute(), Path(sys.argv[3]).absolute(), sys.argv[4])
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        raise SystemExit('S10 QHD policy failed: ' + str(error))
