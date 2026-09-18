#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-only comparison of a collected tree archive and converted inode metadata.

Does not extract archives, register firmware inputs or run any build. The image
association relies on the collector records; it is not a fresh image read.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import tarfile
import tempfile


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def regular(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('expected regular input: ' + str(path))
    return path


def archive_path(name):
    if name.startswith('./'):
        name = name[2:]
    name = name.rstrip('/')
    if name == '.':
        name = ''
    if name and (name.startswith('/') or str(PurePosixPath(name)) != name or '..' in name.split('/')):
        raise ValueError('noncanonical archive path: ' + repr(name))
    return name


def check_archive(archive, entries):
    hashes = {}
    with tarfile.open(archive, 'r:') as tar:
        members = {}
        for item in tar:
            key = archive_path(item.name)
            if key in members:
                raise ValueError('duplicate archive member: ' + key)
            members[key] = item
        if set(members) != set(entries):
            raise ValueError(f'archive path coverage differs: extra={sorted(set(members)-set(entries))[:5]}, missing={sorted(set(entries)-set(members))[:5]}')
        for key, item in members.items():
            expected = entries[key]
            kind = 'd' if item.isdir() else 'l' if item.issym() else 'f' if item.isreg() or item.islnk() else 'unsupported'
            if kind != expected['type'] or (item.uid, item.gid, item.mode & 0o7777) != (expected['uid'], expected['gid'], int(expected['mode'], 8)):
                raise ValueError('archive inode mismatch: ' + key)
            if kind == 'l' and item.linkname != expected['link']:
                raise ValueError('archive symlink differs: ' + key)
            # Resolve only archive hard links; never follow Android symlinks on the host.
            content = item
            visited = set()
            while content.islnk():
                target = archive_path(content.linkname)
                if target in visited or target not in members:
                    raise ValueError('cyclic or missing archive hard-link target: ' + key)
                visited.add(target)
                content = members[target]
            if kind == 'f':
                if not content.isreg():
                    raise ValueError('hard link does not name a regular archive file: ' + key)
                with tar.extractfile(content) as stream:
                    hashes[key] = hashlib.file_digest(stream, 'sha256').hexdigest()
            # GNU tar may store shared hard-link xattrs only on the data member.
            attrs = content.pax_headers if item.islnk() else item.pax_headers
            label = attrs.get('SCHILY.xattr.security.selinux')
            if label is None or label.rstrip('\0') != expected['selinux']:
                raise ValueError('archive SELinux xattr missing/different: ' + key)
            cap = attrs.get('SCHILY.xattr.security.capability')
            if (cap is not None) != expected['capability_xattr_present']:
                raise ValueError('archive capability presence differs: ' + key)
            if cap is not None and cap.encode('utf-8', 'surrogateescape').hex() != expected['capability_xattr_hex']:
                raise ValueError('archive capability bytes differ: ' + key)
    return hashes


def check_tree(root, entries, hashes):
    root = Path(os.path.abspath(root))
    for part in [*reversed(root.parents), root]:
        if part.is_symlink() or not part.is_dir():
            raise ValueError('expanded root/ancestor is not a directory: ' + str(part))
    observed = {'': root}
    def fail(error):
        raise error
    for parent, dirs, files in os.walk(root, followlinks=False, onerror=fail):
        for name in dirs + files:
            path = Path(parent) / name
            observed[path.relative_to(root).as_posix()] = path
    if set(observed) != set(entries):
        raise ValueError('expanded tree path coverage differs')
    for key, path in observed.items():
        mode = path.lstat().st_mode
        kind = 'd' if stat.S_ISDIR(mode) else 'l' if stat.S_ISLNK(mode) else 'f' if stat.S_ISREG(mode) else 'unsupported'
        if kind != entries[key]['type']:
            raise ValueError('expanded tree kind differs: ' + key)
        if kind == 'l' and os.readlink(path) != entries[key]['link']:
            raise ValueError('expanded tree link differs: ' + key)
        if kind == 'f' and digest(path) != hashes[key]:
            raise ValueError('expanded tree content differs: ' + key)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('conversion', type=Path)
    parser.add_argument('--expanded-tree', type=Path)
    parser.add_argument('--output-parent', required=True, type=Path)
    args = parser.parse_args()
    conversion = json.loads(regular(args.conversion / 'conversion.json').read_text())
    if conversion.get('metadata_conversion') != 'complete':
        raise ValueError('metadata conversion incomplete')
    for name, sha in conversion['output_sha256'].items():
        if Path(name).name != name or digest(regular(args.conversion / name)) != sha:
            raise ValueError('converted output digest mismatch: ' + name)
    evidence = Path(conversion['source_evidence'])
    regular(evidence / 'collection-complete.txt')
    state = json.loads(regular(evidence / 'collection.json').read_text())
    if not all(state.get(k) is True for k in ('metadata_collected', 'tree_export_requested', 'tree_export_completed', 'image_hash_unchanged')):
        raise ValueError('collection does not claim completed tree export')
    if regular(evidence / 'tree.errors.txt').read_bytes():
        raise ValueError('tree export has diagnostics')
    for name in ('image.before.sha256', 'image.after.sha256'):
        if regular(evidence / name).read_text() != conversion['image_fingerprint_record']:
            raise ValueError('image association differs from metadata conversion')
    for name, sha in conversion['input_sha256'].items():
        if Path(name).name != name or digest(regular(evidence / name)) != sha:
            raise ValueError('collection metadata digest differs: ' + name)
    archive = regular(evidence / 'tree.tar')
    sha = digest(archive)
    if regular(evidence / 'tree.sha256').read_text().split()[0] != sha:
        raise ValueError('archive digest differs')
    entries = json.loads(regular(args.conversion / 'paths.json').read_text())
    hashes = check_archive(archive, entries)
    if args.expanded_tree:
        check_tree(args.expanded_tree, entries, hashes)
    if digest(archive) != sha:
        raise ValueError("archive changed during verification")
    out = Path(tempfile.mkdtemp(prefix='tree-check.', dir=args.output_parent))
    report = {'scope': 'archive matches collected inode/security metadata; image binding relies on collector records',
              'conversion_sha256': digest(args.conversion / 'conversion.json'), 'archive_sha256': sha,
              'paths': len(entries), 'file_sha256': hashes, 'archive_metadata_match': True,
              'expanded_tree_match': True if args.expanded_tree else None,
              'limitations': ['no image mount/build or SELinux policy resolution', 'no ACL or hard-link topology certification', 'host ownership is not Android metadata']}
    (out / 'verification.json').write_text(json.dumps(report, indent=2))
    print(out)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        raise SystemExit('Tree verification failed: ' + str(error))
