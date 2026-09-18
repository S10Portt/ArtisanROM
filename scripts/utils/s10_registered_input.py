# SPDX-License-Identifier: GPL-3.0-or-later
"""Check locally registered firmware contents, independently of kernel/build readiness."""
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'diagnostics'))
from verify_image_tree import check_tree, digest, regular

PARTITIONS = {'SM-S908B_EUX': {'system', 'vendor', 'product', 'odm'},
              'SM-G973F_AUT': {'system', 'vendor'}}


def verify(root):
    root = Path(root).absolute()
    if root.name not in PARTITIONS or root.is_symlink() or not root.is_dir():
        raise ValueError('unknown or linked registered firmware root')
    record = json.loads(regular(root / '.s10-input.json').read_text())
    if record.get('schema') != 1 or record.get('input_id') != root.name:
        raise ValueError('invalid registration identity/schema')
    if set(record['partitions']) != PARTITIONS[root.name]:
        raise ValueError('registered partition set differs')
    expected_files = {'.s10-input.json', '.s10-proofs'} | PARTITIONS[root.name]
    for part, hashes in record['partitions'].items():
        proofdir = root / '.s10-proofs' / part
        if proofdir.is_symlink() or (root / '.s10-proofs').is_symlink():
            raise ValueError('linked proof directory')
        if set(hashes) != {'paths.json', 'verification.json', 'conversion.json'}:
            raise ValueError('unexpected partition proof set')
        for name, sha in hashes.items():
            if digest(regular(proofdir / name)) != sha:
                raise ValueError('changed registration proof: ' + part + '/' + name)
        conv = json.loads((proofdir / 'conversion.json').read_text())
        proof = json.loads((proofdir / 'verification.json').read_text())
        if (conv['partition'] != part or conv.get('metadata_conversion') != 'complete'
                or proof.get('archive_metadata_match') is not True
                or proof['conversion_sha256'] != hashes['conversion.json']
                or conv['output_sha256']['paths.json'] != hashes['paths.json']):
            raise ValueError('partition proof chain mismatch')
        for name in ('fs_config-' + part, 'file_context-' + part):
            expected_files.add(name)
            if digest(regular(root / name)) != conv['output_sha256'][name]:
                raise ValueError('changed firmware metadata: ' + name)
        entries = json.loads((proofdir / 'paths.json').read_text())
        check_tree(root / part, entries, proof['file_sha256'])
    extras = record['identity_files']
    expected_extra = {'product/build.prop', 'avb/vbmeta.img'} if root.name == 'SM-G973F_AUT' else set()
    if set(extras) != expected_extra:
        raise ValueError('identity-only input scope differs')
    for name, sha in extras.items():
        path = root / name
        if path.parent.is_symlink() or digest(regular(path)) != sha:
            raise ValueError('changed identity/AVB input: ' + name)
        if {p.name for p in path.parent.iterdir()} != {path.name}:
            raise ValueError('identity-only directory has unexpected content')
        expected_files.add(path.parent.name)
    if {p.name for p in root.iterdir()} != expected_files:
        raise ValueError('unregistered firmware root entries')
    return record


if __name__ == '__main__':
    try:
        verify(Path(sys.argv[1]))
        print('Registered firmware content/metadata verified: ' + sys.argv[1])
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        raise SystemExit('S10 input registration failed: ' + str(error))
