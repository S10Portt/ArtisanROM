#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Preserve a verified expansion and its proofs in a new directory; no build registration."""
import argparse
import json
from pathlib import Path
import shutil
import tempfile

from verify_image_tree import check_tree, digest, regular


def preserve(expansion, verification, output_parent):
    expansion = regular(expansion)
    verification = regular(verification)
    expansion_hash, verification_hash = digest(expansion), digest(verification)
    exp = json.loads(expansion.read_text())
    proof = json.loads(verification.read_text())
    convdir = Path(exp['conversion'])
    convfile = regular(convdir / 'conversion.json')
    conversion_hash = digest(convfile)
    conv = json.loads(convfile.read_text())
    partition = conv['partition']
    if partition not in {'system', 'vendor', 'product', 'odm'}:
        raise ValueError('unsupported partition')
    if (exp.get('expanded_tree_match') is not True
            or exp['verification_sha256'] != verification_hash
            or proof.get('archive_metadata_match') is not True
            or proof['conversion_sha256'] != conversion_hash
            or exp['archive_sha256'] != proof['archive_sha256']
            or conv.get('metadata_conversion') != 'complete'):
        raise ValueError('proof chain mismatch')
    required = {'paths.json', 'fs_config-' + partition, 'file_context-' + partition}
    if set(conv['output_sha256']) != required:
        raise ValueError('unexpected conversion output set')
    for name, sha in conv['output_sha256'].items():
        if digest(regular(convdir / name)) != sha:
            raise ValueError('conversion output changed: ' + name)
    entries = json.loads((convdir / 'paths.json').read_text())
    tree = Path(exp['tree'])
    check_tree(tree, entries, proof['file_sha256'])
    out = Path(tempfile.mkdtemp(prefix=partition + '.', dir=output_parent))
    # Separate inodes: later changes cannot modify the analysis source through hard links.
    shutil.copytree(tree, out / 'tree', symlinks=True)
    metadata = out / 'metadata'
    metadata.mkdir()
    for name in required:
        shutil.copyfile(convdir / name, metadata / name)
        if digest(metadata / name) != conv['output_sha256'][name]:
            raise ValueError('metadata changed during copy: ' + name)
    for name, source, sha in (
            ('conversion.json', convfile, conversion_hash),
            ('verification.json', verification, verification_hash),
            ('expansion.json', expansion, expansion_hash)):
        shutil.copyfile(source, out / name)
        if digest(out / name) != sha or digest(source) != sha:
            raise ValueError('proof changed during copy: ' + name)
    check_tree(out / 'tree', entries, proof['file_sha256'])
    record = {
        'partition': partition, 'paths': len(entries),
        'image_fingerprint_record': conv['image_fingerprint_record'],
        'archive_sha256': proof['archive_sha256'],
        'proof_sha256': {name: digest(out / name) for name in
                         ('conversion.json', 'verification.json', 'expansion.json')},
        'metadata_sha256': conv['output_sha256'],
        'preserver_sha256': digest(Path(__file__)),
        'tree': 'tree', 'metadata': 'metadata',
        'content_kind_links_verified': True,
        'scope': 'Preserved verified tree and Android metadata sidecars; archive binding inherited from prior proof. No fresh image read, builder registration, final SELinux interpretation or build approval.',
    }
    # No completion record exists on any earlier failure; keep partial output for diagnosis.
    (out / 'preservation.json').write_text(json.dumps(record, indent=2) + '\n')
    return out


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('expansion', type=Path)
    parser.add_argument('verification', type=Path)
    parser.add_argument('--output-parent', type=Path, required=True)
    args = parser.parse_args()
    try:
        print(preserve(args.expansion, args.verification, args.output_parent), flush=True)
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit('Preservation failed; partial output is not complete: ' + str(error))
