# SPDX-License-Identifier: GPL-3.0-or-later
"""Strict operations for specific S10 property consumers, not global prop policy."""
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
from s10_copy_properties import read, property_value


def perform(mode, work):
    path = work/'system/system/build.prop'
    data = read(path)
    if mode == 'oneui':
        value = property_value(data,'ro.build.version.oneui')
        if not re.fullmatch(r'[0-9]{1,7}',value): raise ValueError('invalid One UI integer')
        value = int(value)
        major, minor, patch = value//10000, value//100%100, value%100
        return f'{major}.{minor}'+(f'.{patch}' if patch else '')
    if mode == 'objectcapture':
        system = property_value(data,'ro.product.device')
        vendor = property_value(read(work/'vendor/build.prop'),'ro.product.vendor.device')
        if any(not re.fullmatch(r'[A-Za-z0-9_.-]+',s) for s in (system,vendor)):
            raise ValueError('invalid objectcapture identities')
        return system+'\t'+vendor
    if mode != 'delete-camerax': raise ValueError('unsupported consumer')
    key = 'ro.camerax.extensions.enabled'
    value = property_value(data,key,optional=True,nonempty=False)
    if value is None: return ''  # Explicitly absent is a valid idempotent deletion.
    after = b''.join(line for line in data.splitlines(keepends=True)
                    if not (b'=' in line and line.split(b'=',1)[0].strip()==key.encode()))
    fd,name = tempfile.mkstemp(prefix='.s10-camerax-',dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as stream:
            stream.write(after); stream.flush(); os.fsync(stream.fileno())
        shutil.copystat(path,name)
        if read(path)!=data: raise ValueError('property changed before replacement')
        os.replace(name,path)
    finally:
        if os.path.lexists(name): os.unlink(name)
    return ''


if __name__=='__main__':
    try:
        if len(sys.argv)!=3: raise ValueError('usage: s10_property_consumers.py MODE WORK')
        result=perform(sys.argv[1],Path(sys.argv[2]))
        if result: print(result)
    except (OSError,ValueError) as exc:
        print(f'S10 property consumer: {exc}',file=sys.stderr);sys.exit(1)
