#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate work OTA identity fields without running the ROM builder."""
from datetime import date
from pathlib import Path
import re
import sys
from s10_copy_properties import read, property_value


def fields(path):
    data = read(path)
    values = {name: property_value(data, key) for name, key in (
        ('INCREMENTAL', 'ro.build.version.incremental'),
        ('SDK', 'ro.build.version.sdk'),
        ('SECURITY_PATCH_LEVEL', 'ro.build.version.security_patch'),
        ('TIMESTAMP', 'ro.build.date.utc'),
    )}
    if values['SDK'] != '36':
        raise ValueError('S10 GZD7 work must retain SDK 36')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', values['INCREMENTAL']):
        raise ValueError('unsupported incremental serialization')
    if not re.fullmatch(r'[1-9][0-9]*', values['TIMESTAMP']) or int(values['TIMESTAMP']) >= 2**63:
        raise ValueError('OTA timestamp must fit a positive int64')
    patch = values['SECURITY_PATCH_LEVEL']
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', patch) or date.fromisoformat(patch).isoformat() != patch:
        raise ValueError('invalid OTA security patch date')
    return values


if __name__ == '__main__':
    try:
        if len(sys.argv) not in (2, 5):
            raise ValueError('usage: s10_ota_properties.py WORK_SYSTEM_BUILD_PROP')
        values = fields(Path(sys.argv[1]))
        if len(sys.argv) == 5:
            if sys.argv[2] != '--build-info' or not re.fullmatch(r'[A-Za-z0-9_.-]+', sys.argv[3]):
                raise ValueError('invalid build_info version/arguments')
            timestamp = sys.argv[4]
            if not re.fullmatch(r'[1-9][0-9]*', timestamp) or int(timestamp) >= 2**63:
                raise ValueError('invalid ROM build timestamp')
            print('device=beyond1lte')
            print('version='+sys.argv[3])
            print('timestamp='+timestamp)
            print('security_patch_version='+values['SECURITY_PATCH_LEVEL'])
            print('incremental='+values['INCREMENTAL'])
        else:
            for key, value in values.items():
                print(f'{key}\t{value}')
    except (OSError, ValueError) as exc:
        print(f'S10 OTA properties: {exc}', file=sys.stderr)
        sys.exit(1)
