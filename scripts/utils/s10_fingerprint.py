# SPDX-License-Identifier: GPL-3.0-or-later
"""Change only the device component of known source/donor fingerprints."""
from pathlib import Path
import re
import sys
from s10_copy_properties import read, property_value


def normalize(fingerprint, build_product, vendor_device):
    # brand/product/device:release/id/incremental:type/tags
    match = re.fullmatch(r'([^/:]+)/([^/:]+)/([^/:]+):([^/:]+)/([^/:]+)/([^/:]+):([^/:]+)/([^/:]+)', fingerprint)
    if not match or any(not re.fullmatch(r'[A-Za-z0-9_.-]+', s) for s in match.groups()):
        raise ValueError('unsupported fingerprint structure')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', vendor_device):
        raise ValueError('invalid vendor device')
    brand, product, device, release, build_id, incremental, kind, tags = match.groups()
    if device not in (build_product, vendor_device):
        raise ValueError('fingerprint device differs from both observed device identities')
    return f'{brand}/{product}/{vendor_device}:{release}/{build_id}/{incremental}:{kind}/{tags}'


def collect(fw):
    result = {}
    for name, folder in (('SOURCE_FINGERPRINT','SM-S908B_EUX'), ('TARGET_FINGERPRINT','SM-G973F_AUT')):
        system = read(fw/folder/'system/system/build.prop')
        vendor = read(fw/folder/'vendor/build.prop')
        result[name] = normalize(property_value(system,'ro.system.build.fingerprint'),
                                 property_value(system,'ro.build.product'),
                                 property_value(vendor,'ro.product.vendor.device'))
    return result


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2: raise ValueError('usage: s10_fingerprint.py FW_DIR')
        for key, value in collect(Path(sys.argv[1])).items(): print(key+'\t'+value)
    except (ValueError, OSError) as exc:
        print(f'S10 fingerprint: {exc}', file=sys.stderr)
        sys.exit(1)
