#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Expand a verified collector archive to a NEW host-owned analysis directory.

Android ownership and xattrs remain in separate metadata, never inferred from
host ownership. No firmware cache registration, image build or mount is done.
"""
import argparse
import json
from pathlib import Path
import os
import shutil
import tarfile
import tempfile
from verify_image_tree import archive_path, check_tree, digest, regular


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('conversion', type=Path)
    p.add_argument('verification', type=Path)
    p.add_argument('--output-parent', required=True, type=Path)
    a = p.parse_args()
    proof = json.loads(regular(a.verification).read_text())
    convfile = regular(a.conversion / 'conversion.json')
    if proof.get('archive_metadata_match') is not True or proof['conversion_sha256'] != digest(convfile):
        raise ValueError('archive proof does not match conversion')
    conv = json.loads(convfile.read_text())
    for name, sha in conv['output_sha256'].items():
        if Path(name).name != name or digest(regular(a.conversion / name)) != sha:
            raise ValueError('conversion output changed: ' + name)
    archive = regular(Path(conv['source_evidence']) / 'tree.tar')
    if digest(archive) != proof['archive_sha256']:
        raise ValueError('archive changed since verification')
    entries = json.loads((a.conversion / 'paths.json').read_text())
    out = Path(tempfile.mkdtemp(prefix='expanded-' + conv['partition'] + '.', dir=a.output_parent))
    tree = out / 'tree'
    tree.mkdir()
    # Check all parent types before creating anything from the archive.
    for key, info in entries.items():
        if archive_path(key) != key:
            raise ValueError('noncanonical metadata path')
        if key:
            parent = str(Path(key).parent)
            while parent != '.':
                if entries.get(parent, {}).get('type') != 'd':
                    raise ValueError('non-directory archive parent: ' + parent)
                parent = str(Path(parent).parent)
    with tarfile.open(archive, 'r:') as tar:
        members = {}
        for item in tar:
            key = archive_path(item.name)
            if key in members:
                raise ValueError('duplicate member')
            members[key] = item
        if set(members) != set(entries):
            raise ValueError('archive path coverage changed')
        for key in sorted(entries, key=lambda x: (x.count('/'), x)):
            if key and entries[key]['type'] == 'd':
                (tree / key).mkdir(mode=0o755)
        for key, info in entries.items():
            if info['type'] != 'f':
                continue
            item = members[key]
            visited = set()
            while item.islnk():
                target = archive_path(item.linkname)
                if target in visited or target not in members:
                    raise ValueError('invalid archive hard link')
                visited.add(target)
                item = members[target]
            if not item.isreg():
                raise ValueError('nonregular archive content')
            with tar.extractfile(item) as src, (tree / key).open('xb') as dst:
                shutil.copyfileobj(src, dst, 1024 * 1024)
            (tree / key).chmod(0o644 | (int(info['mode'], 8) & 0o111))
        # Symlinks last: never traverse an Android absolute link while writing.
        for key, info in entries.items():
            if info['type'] == 'l':
                os.symlink(info['link'], tree / key)
    if digest(archive) != proof['archive_sha256']:
        raise ValueError('archive changed during expansion')
    check_tree(tree, entries, proof['file_sha256'])
    (out / 'expansion.json').write_text(json.dumps({
        'tree': str(tree), 'conversion': str(a.conversion),
        'verification_sha256': digest(a.verification), 'archive_sha256': proof['archive_sha256'],
        'paths': len(entries), 'expanded_tree_match': True,
        'scope': 'content/kind/link match; Android metadata retained separately; no builder approval',
    }, indent=2))
    print(out)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        raise SystemExit('Expansion failed (partial output is not approved): ' + str(error))
