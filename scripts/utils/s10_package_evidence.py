#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Preserve packaging inputs before ZIP temporary-directory cleanup.

No image building, extraction or AVB verification. A report binds the final ZIP
and observed kernel hashes to metadata/scripts; it is not installation approval.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile

TEXT_INPUTS = tuple(
    f'image-metadata/{kind}-{partition}'
    for partition in ('system', 'vendor', 'product')
    for kind in ('fs_config', 'file_context')
) + ('META-INF/com/google/android/updater-script', 'META-INF/com/google/android/update-binary', 'build_info.txt',
     'META-INF/com/android/metadata')
KERNELS = ('boot.img', 'dtb.img', 'dtbo.img')


def no_links(path):
    for item in (path, *path.parents):
        if item.is_symlink():
            raise ValueError(f'symlink evidence path: {item}')


def snapshot(path, retain=False):
    no_links(path)
    before = path.stat()
    if not stat.S_ISREG(before.st_mode) or before.st_size == 0:
        raise ValueError(f'missing/empty/unsupported package input: {path}')
    signature = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    digest = hashlib.sha256()
    content = bytearray()
    with path.open('rb') as stream:
        if signature(os.fstat(stream.fileno())) != signature(before):
            raise ValueError(f'input changed while opening: {path}')
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
            if retain:
                content.extend(chunk)
        if signature(os.fstat(stream.fileno())) != signature(before):
            raise ValueError(f'input changed while reading: {path}')
    if signature(path.stat()) != signature(before):
        raise ValueError(f'input replaced while reading: {path}')
    return {'bytes': before.st_size, 'sha256': digest.hexdigest()}, bytes(content)


def preserve(stage, archive, output, work):
    if any('..' in p.parts for p in (stage, archive, output, work)):
        raise ValueError('noncanonical evidence argument')
    stage, archive, output, work = (p.absolute() for p in (stage, archive, output, work))
    for path in (stage, archive, output, work):
        no_links(path)
    # Evidence must survive temporary cleanup and must not change work's hash.
    for forbidden in (stage, work):
        if output == forbidden or forbidden in output.parents or output in forbidden.parents:
            raise ValueError('evidence output overlaps work or temporary package directory')
    names = list(TEXT_INPUTS)
    optional = stage/'META-INF/com/android/metadata.pb'
    if os.path.lexists(optional):
        names.append('META-INF/com/android/metadata.pb')
    records, contents = {}, {}
    for name in names:
        records[name], contents[name] = snapshot(stage/name, retain=True)
    kernels = {name: snapshot(stage/name)[0] for name in KERNELS}
    archive_record = snapshot(archive)[0]
    # Recheck small inputs before writing; there is no global filesystem lock.
    for name, expected in records.items():
        if snapshot(stage/name)[0] != expected:
            raise ValueError(f'packaging evidence changed: {name}')
    # Import lazily so snapshot-only consumers need no output directory.
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'diagnostics'))
    from external_output import external_output_parent
    output = external_output_parent(output)
    output.mkdir(parents=True, exist_ok=True)
    destination = Path(tempfile.mkdtemp(prefix='s10-package-', dir=output))
    for name, content in contents.items():
        dest = destination/name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(content)
        if snapshot(dest)[0] != records[name]:
            raise ValueError(f'evidence copy mismatch: {name}')
    report = {
        'schema': 1,
        'scope': 'Packaging evidence only; no final image, AVB, installer or runtime approval.',
        'installation_approved': False,
        'archive': {'name': archive.name, **archive_record},
        'kernel_hashes_after_processing': kernels,
        'preserved_files': records,
        'limitations': ['Sequential snapshots without concurrent-writer exclusion.',
                       'No claim that archive members were independently extracted and compared.',
                       'Android ownership/xattrs are represented by metadata, not host copy stat.'],
    }
    # A failed copy leaves an incomplete evidence directory without this record.
    temp = destination/'report.json.tmp'
    temp.write_text(json.dumps(report, indent=2) + '\n')
    temp.replace(destination/'report.json')
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('archive', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('work', type=Path)
    args = parser.parse_args()
    try:
        print(preserve(args.stage, args.archive, args.output, args.work))
    except (OSError, ValueError) as exc:
        print(f'S10 package evidence: {exc}', file=sys.stderr)
        sys.exit(1)
