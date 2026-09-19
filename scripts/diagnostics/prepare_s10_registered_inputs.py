#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare a NEW cache-shaped directory from preserved proofs; never run a build."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from external_output import external_output_parent

from verify_image_tree import check_tree, digest, regular
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'utils'))
from s10_registered_input import verify, PARTITIONS
from s10_validate_inputs import validate


def prepare(records_file, hwc1_manifest, output_parent):
    rows = json.loads(regular(records_file).read_text())
    mapping = {'gzd7': 'SM-S908B_EUX', 'hwc1': 'SM-G973F_AUT'}
    keys = [(r['firmware'], r['partition']) for r in rows]
    expected = {(fw, p) for fw, name in mapping.items() for p in PARTITIONS[name]}
    if len(keys) != len(set(keys)) or set(keys) != expected:
        raise ValueError('expected exactly six preserved partitions')
    output = Path(tempfile.mkdtemp(prefix='s10-fw.', dir=external_output_parent(output_parent)))
    registrations = {}
    for fw, name in mapping.items():
        (output / name).mkdir()
        registrations[name] = {'schema': 1, 'input_id': name, 'partitions': {},
                               'identity_files': {}, 'scope': 'Verified local firmware input, not final ROM/kernel/SELinux/AVB compatibility approval'}
    for row in rows:
        source = Path(row['directory'])
        saved = json.loads(regular(source / 'preservation.json').read_text())
        if saved != row['record'] or saved.get('content_kind_links_verified') is not True:
            raise ValueError('preservation record changed')
        part = row['partition']
        if saved['partition'] != part:
            raise ValueError('partition identity mismatch')
        for name, sha in saved['proof_sha256'].items():
            if name not in {'conversion.json', 'verification.json', 'expansion.json'} or digest(regular(source / name)) != sha:
                raise ValueError('preserved proof changed')
        conv = json.loads((source / 'conversion.json').read_text())
        proof = json.loads((source / 'verification.json').read_text())
        for name in ('paths.json', 'fs_config-' + part, 'file_context-' + part):
            if digest(regular(source / 'metadata' / name)) != conv['output_sha256'][name]:
                raise ValueError('preserved metadata changed')
        entries = json.loads((source / 'metadata/paths.json').read_text())
        check_tree(source / 'tree', entries, proof['file_sha256'])
        root = output / mapping[row['firmware']]
        print('Preparing', root.name, part, flush=True)
        shutil.copytree(source / 'tree', root / part, symlinks=True)
        for name in ('fs_config-' + part, 'file_context-' + part):
            shutil.copyfile(source / 'metadata' / name, root / name)
        proofdir = root / '.s10-proofs' / part
        proofdir.mkdir(parents=True)
        for name in ('conversion.json', 'verification.json'):
            shutil.copyfile(source / name, proofdir / name)
            if digest(proofdir / name) != saved['proof_sha256'][name]:
                raise ValueError('proof changed during preparation: ' + name)
        shutil.copyfile(source / 'metadata/paths.json', proofdir / 'paths.json')
        if digest(proofdir / 'paths.json') != conv['output_sha256']['paths.json']:
            raise ValueError('paths changed during preparation')
        registrations[root.name]['partitions'][part] = {p.name: digest(p) for p in proofdir.iterdir()}
    manifest = json.loads(regular(hwc1_manifest).read_text())
    if manifest.get('complete') is not True or manifest['zip_sha256'] != '84a96e2d7d372dfb7786e1d99470398d5a8172dceae78920738b32daad208c3b':
        raise ValueError('unexpected HWC1 extraction provenance')
    products = [r for r in manifest['images'] if r['partition'] == 'product']
    vbmetas = [r for r in manifest['images'] if r['partition'] == 'vbmeta']
    if len(products) != 1 or len(vbmetas) != 2:
        raise ValueError('unexpected product/vbmeta set')
    original = {}
    for row in products + vbmetas:
        rel = Path(row['raw_path'])
        if rel.is_absolute() or '..' in rel.parts:
            raise ValueError('invalid image record path')
        path = regular(hwc1_manifest.parent / rel)
        if digest(path) != row['raw_sha256']:
            raise ValueError('original image changed: ' + str(path))
        original[row['raw_path']] = row['raw_sha256']
    if {r['raw_sha256'] for r in vbmetas} != {'ba366de39ea4638312f76774249930af4983b9cdb1e1a96181c1e9acdffbdb37'}:
        raise ValueError('unexpected original vbmeta')
    product = hwc1_manifest.parent / products[0]['raw_path']
    if products[0]['raw_sha256'] != 'e3246e8e20535230d44255f95ae39bd36e05b1d5ca541b023e411aa395c87815':
        raise ValueError('unexpected original product')
    # debugfs is read-only without -w. Its exit status alone does not detect lookup failure.
    result = subprocess.run(['debugfs', '-R', 'cat /build.prop', str(product)], capture_output=True, check=True)
    expected_props = b'ro.omc.build.version=G973FOXMGHWA3\nro.omc.build.id=61057831\nro.omc.changetype=DATA_RESET_ON,TRUE\nro.simbased.changetype=NO_DFLT_CSC,OMC\nro.omc.disabler=FALSE\n'
    if result.stdout != expected_props or digest(product) != products[0]['raw_sha256']:
        raise ValueError('original product identity extraction differs')
    target = output / 'SM-G973F_AUT'
    (target / 'product').mkdir()
    (target / 'product/build.prop').write_bytes(result.stdout)
    (target / 'avb').mkdir()
    shutil.copyfile(hwc1_manifest.parent / vbmetas[0]['raw_path'], target / 'avb/vbmeta.img')
    registrations[target.name]['identity_files'] = {n: digest(target / n) for n in ('product/build.prop', 'avb/vbmeta.img')}
    registrations[target.name]['original_images'] = original
    registrations[target.name]['extraction_manifest_sha256'] = digest(hwc1_manifest)
    for name, record in registrations.items():
        (output / name / '.s10-input.json').write_text(json.dumps(record, indent=2) + '\n')
        verify(output / name)
    for stage in ('source', 'raw-links'):
        validate(stage, output, 'SM-S908B/EUX', 'SM-G973F/AUT', Path('/nonexistent-work'))
    (output / 'preparation.json').write_text(json.dumps({
        'firmware_root': str(output), 'registered_inputs': list(registrations),
        'source_and_raw_structure_checks': 'passed', 'script_sha256': digest(Path(__file__)),
        'scope': 'Input preparation only; no kernel readiness, modules or build executed',
    }, indent=2) + '\n')
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('records', type=Path)
    parser.add_argument('hwc1_manifest', type=Path)
    parser.add_argument('--output-parent', type=Path, required=True)
    args = parser.parse_args()
    try:
        print(prepare(args.records, args.hwc1_manifest, args.output_parent), flush=True)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        raise SystemExit('Preparation failed; partial directory is not complete: ' + str(error))
