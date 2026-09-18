# SPDX-License-Identifier: GPL-3.0-or-later
"""Require the current unconditional S10 abort (or an explicitly, narrowly
authorized abort-removed state) and the original installer executable."""
import re
from pathlib import Path
import sys
from s10_copy_properties import read

ABORT = 'abort("beyond1lte source port is incomplete; see target/beyond1lte/README.md Do not flash.");'

# assertions.edify has exactly two accepted states:
#   1. safe/default: its only executable line is exactly ABORT.
#   2. deliberate test state: it contains at least one nonblank line and every
#      nonblank line is a comment (there is no executable Edify content).
#
# An empty/whitespace-only file is NOT accepted. A different abort, partially
# edited statement, or any other executable content still fails the build.
# This keeps abort removal explicit in the repository while preserving all
# unrelated installer guards below.

# ArtisanROM 3.1.1's own installer (target/beyond1lte/README.md)
# does write odm/prism/optics (block_image_update) and up_param (package_extract_file
# of up_param.bin) as part of a normal install -- they are not factory-locked or
# out of OTA scope. This build simply has no GZD7-compatible, verified replacement
# data for any of the four yet (see target/beyond1lte/README.md,
# corrected 2026-09-18), so it must not write them until that data exists. Reject
# any updater-script that references their block devices or ships a matching
# transfer.list/new.dat/img/bin asset, by name or by a bare "by-name/<partition>"
# path, so a future accidental (or copy-pasted-from-3.1.1) write is caught here
# instead of at install time.
RESERVED_PARTITIONS = ('odm', 'prism', 'optics', 'up_param')
RESERVED_PATTERN = re.compile(
    r'(?:^|[^A-Za-z0-9_])(?:' + '|'.join(RESERVED_PARTITIONS) + r')(?:[^A-Za-z0-9_]|$)')


def code(data):
    return [line.strip() for line in data.decode('utf-8').splitlines()
            if line.strip() and not line.lstrip().startswith('#')]


def _nonblank_lines(data):
    return [line.strip() for line in data.decode('utf-8').splitlines()
            if line.strip()]


def _assertions_abort_present(data):
    """Return True for the safe ABORT state, False for a documented comment-only state."""
    lines = _nonblank_lines(data)
    executable = code(data)

    if executable == [ABORT]:
        return True

    # Abort removal is allowed only when the file is non-empty and consists
    # entirely of comments. Empty/whitespace-only files are rejected.
    if not executable and lines and all(line.lstrip().startswith('#') for line in lines):
        return False

    raise ValueError(
        'S10 assertions must contain exactly the required abort, or be a '
        'non-empty comment-only file documenting deliberate abort removal'
    )


def check(repo, stage=None):
    assertions_data = read(repo/'target/beyond1lte/installer/assertions.edify')
    abort_present = _assertions_abort_present(assertions_data)

    binary = repo/'prebuilts/bootable/deprecated-ota/updater'
    # Binary read is separate: property reader rejects NUL bytes.
    from s10_package_evidence import snapshot
    expected = snapshot(binary)[0]

    if stage is not None:
        script = code(read(stage/'META-INF/com/google/android/updater-script'))
        if not script:
            raise ValueError('built updater-script contains no executable content')

        if abort_present:
            if script[0] != ABORT or script.count(ABORT) != 1:
                raise ValueError('required abort must be the first executable installer line')
        elif ABORT in script:
            raise ValueError(
                'assertions.edify has no abort but the built updater-script '
                'still contains one (stale/mismatched build?)'
            )

        if snapshot(stage/'META-INF/com/google/android/update-binary')[0] != expected:
            raise ValueError('update-binary differs from required installer input')

        # These protections are independent of the temporary test-build abort state.
        for line in script:
            match = RESERVED_PATTERN.search(line)
            if match:
                raise ValueError(
                    f'installer must not reference reserved partition '
                    f'"{match.group(0).strip()}"'
                )

        for path in stage.rglob('*'):
            if path.is_file() and any(
                    path.name == name or path.name.startswith(name + '.')
                    for name in RESERVED_PARTITIONS):
                raise ValueError(
                    f'installer package must not ship a reserved-partition asset: {path.name}'
                )


if __name__ == '__main__':
    try:
        if len(sys.argv) not in (2,3): raise ValueError('usage: s10_installer_guard.py REPO [STAGE]')
        check(Path(sys.argv[1]), Path(sys.argv[2]) if len(sys.argv)==3 else None)
    except (ValueError,OSError) as exc:
        print(f'S10 installer: {exc}',file=sys.stderr)
        sys.exit(1)
