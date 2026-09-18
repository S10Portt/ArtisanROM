#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Audit platform asset coverage; no defaults, metadata edits or module execution."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'utils'))
from s10_metadata_plan import rows, context_key, item_kind


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(module, raw):
    result = {'module': str(module), 'scope': 'literal exact coverage and observed donor comparison; not policy approval', 'entries': [], 'missing': [], 'conflicts': [], 'unused_fs_keys': {}}
    for partition in ('system', 'vendor', 'product', 'odm', 'system_ext'):
        tree = module / partition
        if not tree.exists():
            continue
        fs = rows(module / ('fs_config-' + partition), 'fs')
        fc = rows(module / ('file_context-' + partition), 'context')
        rfs = rows(raw / ('fs_config-' + partition), 'fs') if (raw / ('fs_config-' + partition)).is_file() else {}
        rfc = rows(raw / ('file_context-' + partition), 'context') if (raw / ('file_context-' + partition)).is_file() else {}
        seen = set()
        for path in sorted(tree.rglob('*')):
            key = path.relative_to(module).as_posix(); seen.add(key)
            kind = item_kind(path)
            frows, crows = fs.get(key, []), fc.get(context_key(key), [])
            original = raw / key
            entry = {'key': key, 'kind': kind, 'asset_sha256': sha(path) if kind == 'file' else None,
                     'asset_fs': frows, 'asset_context': crows,
                     'donor_fs': rfs.get(key, []), 'donor_context': rfc.get(context_key(key), [])}
            if kind == 'file' and original.is_file() and not original.is_symlink():
                entry['donor_sha256'] = sha(original)
                entry['same_donor_content'] = entry['asset_sha256'] == entry['donor_sha256']
            if len(frows) != 1 or len(crows) != 1 or len(crows[0]) != 1:
                result['missing'].append(key)
            if frows and rfs.get(key) and frows != rfs[key] or crows and rfc.get(context_key(key)) and crows != rfc[context_key(key)]:
                result['conflicts'].append(key)
            result['entries'].append(entry)
        result['unused_fs_keys'][partition] = sorted(set(fs) - seen - {'', '/', partition})
    result['complete_literal_coverage'] = not result['missing']
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('module', type=Path)
    p.add_argument('--raw', type=Path, required=True)
    p.add_argument('--require-coverage', action='store_true')
    a = p.parse_args()
    try:
        report = audit(a.module, a.raw)
        print(json.dumps(report, indent=2))
        if a.require_coverage and not report['complete_literal_coverage']:
            raise SystemExit(1)
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit('Asset metadata audit failed: ' + str(error))
