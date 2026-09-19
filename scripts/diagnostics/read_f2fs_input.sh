#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# User-run evidence collector, not a ROM builder or firmware-cache importer.
# Requires Linux F2FS, sudo, mount/umount, file, find, getfattr, sha256sum.
# Do not run as part of source-only review.
set -eu
set -o pipefail

if [[ $# -ne 1 || ! -f "$1" || -L "$1" ]]; then
    echo "Usage: bash read_f2fs_input.sh /absolute/path/to/raw-f2fs.img" >&2
    exit 1
fi
for tool in sudo mount umount file find getfattr sha256sum realpath mktemp cmp; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
IMAGE=$(realpath -- "$1") || exit 1
TYPE=$(file -b -- "$IMAGE") || exit 1
case "$TYPE" in
    "F2FS filesystem"*) ;;
    *) echo "Expected a raw F2FS image; detected: $TYPE" >&2; exit 1 ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RECORDS_PARENT="$(python3 "$SCRIPT_DIR/external_output.py")" || exit 1
OUT=$(mktemp -d "$RECORDS_PARENT/f2fs-evidence.XXXXXX") || exit 1
MNT="$OUT/mount"
mkdir "$MNT" || exit 1
MOUNTED=false
cleanup()
{
    local rc=$?
    trap - EXIT
    if "$MOUNTED"; then
        if ! sudo umount "$MNT"; then
            echo "Unmount failed; mount point retained: $MNT" >&2
            rc=1
        fi
    fi
    echo "Evidence directory: $OUT"
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s\n%s\n' "$IMAGE" "$TYPE" > "$OUT/input.txt"
sha256sum -- "$IMAGE" > "$OUT/image.before.sha256" || exit 1
sudo -v || exit 1
# ro prevents writes; norecovery forbids roll-forward recovery. No repair fallback.
sudo mount -t f2fs -o loop,ro,norecovery "$IMAGE" "$MNT" > "$OUT/mount.log" 2>&1 || {
    cat "$OUT/mount.log" >&2
    echo "Mount failed. Do not retry read-write or run filesystem repair." >&2
    exit 1
}
MOUNTED=true
# Six NUL-separated fields per entry: relative path, type, UID, GID, mode, link target.
sudo find "$MNT" -xdev -printf '%P\0%y\0%U\0%G\0%m\0%l\0' \
    > "$OUT/inodes.nul" 2> "$OUT/inodes.errors.txt" || exit 1
# Raw xattrs, not fabricated capabilities=0; preserve errors and path base.
sudo getfattr -R -P -h -d -m '^security\.(selinux|capability)$' \
    --encoding=hex --absolute-names "$MNT" \
    > "$OUT/security-xattrs.txt" 2> "$OUT/xattrs.errors.txt" || exit 1
sudo find "$MNT" -xdev -type f -name build.prop -exec sh -c '
    for input do
        printf "\nFILE %s\n" "$input" || exit 1
        cat "$input" || exit 1
    done
' sh {} + > "$OUT/build-props.txt" 2> "$OUT/build-props.errors.txt" || exit 1
sudo umount "$MNT" || exit 1
MOUNTED=false
sha256sum -- "$IMAGE" > "$OUT/image.after.sha256" || exit 1
cmp "$OUT/image.before.sha256" "$OUT/image.after.sha256" || exit 1
printf '%s\n' "Collection finished; not a builder-ready metadata validation." > "$OUT/collection-complete.txt"
