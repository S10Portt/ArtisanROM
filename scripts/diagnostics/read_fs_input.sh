#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# User-run evidence collector, not a ROM builder or firmware-cache importer.
# Requires Linux ext4/F2FS, sudo, mount/umount, file, find, getfattr, sha256sum.
# Supersedes the F2FS-only collector for new inputs; preserves its raw evidence format.
# Do not run as part of source-only review.
set -eu
set -o pipefail

if [[ $# -lt 1 || $# -gt 2 || ! -f "$1" || -L "$1" ]]; then
    echo "Usage: bash read_fs_input.sh /absolute/path/to/raw-filesystem.img [--export-tree]" >&2
    exit 1
fi
EXPORT_TREE=false
if [[ $# -eq 2 ]]; then
    [[ "$2" == "--export-tree" ]] || { echo "Unknown option: $2" >&2; exit 1; }
    EXPORT_TREE=true
    command -v tar >/dev/null || { echo "Missing tar" >&2; exit 1; }
fi
for tool in sudo mount umount file find getfattr sha256sum realpath mktemp cmp python3; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
IMAGE=$(realpath -- "$1") || exit 1
TYPE=$(file -b -- "$IMAGE") || exit 1
FS_TYPE=$(python3 - "$IMAGE" <<'PY'
from pathlib import Path
import struct
import sys

path = Path(sys.argv[1])
with path.open("rb") as stream:
    header = stream.read(2048)
if header[:4] == b"\x3a\xff\x26\xed":
    raise SystemExit("Sparse image: supply the manifest raw_path instead")
if len(header) < 2048:
    raise SystemExit("Truncated filesystem header")
sb = header[1024:2048]
if sb[:4] == b"\x10\x20\xf5\xf2":
    print("f2fs")
elif sb[56:58] == b"\x53\xef":
    incompat = struct.unpack_from("<I", sb, 96)[0]
    log_block_size = struct.unpack_from("<I", sb, 24)[0]
    blocks = struct.unpack_from("<I", sb, 4)[0]
    if incompat & 0x80:
        blocks |= struct.unpack_from("<I", sb, 336)[0] << 32
    # EXTENTS marks the observed ext4 layout; do not trust file's PSX/ext2 label.
    if not incompat & 0x40 or log_block_size > 6 or blocks == 0:
        raise SystemExit("Unsupported ext superblock; no mount attempted")
    if blocks * (1024 << log_block_size) > path.stat().st_size:
        raise SystemExit("Filesystem block count exceeds image size")
    print("ext4")
else:
    raise SystemExit("Unsupported filesystem magic; no mount attempted")
PY
) || exit 1
case "$FS_TYPE" in
    f2fs) FS_OPTIONS=loop,ro,norecovery ;;
    ext4) FS_OPTIONS=loop,ro,noload ;;
    *) echo "Unsupported filesystem: $FS_TYPE" >&2; exit 1 ;;
esac
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RECORDS_PARENT="$(python3 "$SCRIPT_DIR/external_output.py")" || exit 1
OUT=$(mktemp -d "$RECORDS_PARENT/fs-evidence.XXXXXX") || exit 1
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
# ro prevents writes; norecovery/noload prevent recovery or journal replay. No repair fallback.
printf '%s %s\n' "$FS_TYPE" "$FS_OPTIONS" > "$OUT/mount-options.txt"
sudo mount -t "$FS_TYPE" -o "$FS_OPTIONS" "$IMAGE" "$MNT" > "$OUT/mount.log" 2>&1 || {
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
if "$EXPORT_TREE"; then
    # Preserve the actual image root and symlink text; never use --dereference.
    # Stream to the caller-owned archive instead of chowning Android files.
    sudo tar --one-file-system --xattrs --xattrs-include='*' --acls --numeric-owner \
        -cpf - -C "$MNT" . > "$OUT/tree.tar" 2> "$OUT/tree.errors.txt" || exit 1
    if [[ -s "$OUT/tree.errors.txt" ]]; then
        echo "Tree export reported diagnostics; review tree.errors.txt before accepting output" >&2
        exit 1
    fi
    sha256sum "$OUT/tree.tar" > "$OUT/tree.sha256" || exit 1
fi
sudo umount "$MNT" || exit 1
MOUNTED=false
sha256sum -- "$IMAGE" > "$OUT/image.after.sha256" || exit 1
cmp "$OUT/image.before.sha256" "$OUT/image.after.sha256" || exit 1
printf '{"metadata_collected":true,"tree_export_requested":%s,"tree_export_completed":%s,"image_hash_unchanged":true}\n' \
    "$EXPORT_TREE" "$EXPORT_TREE" > "$OUT/collection.json" || exit 1
printf '%s\n' "Collection finished; not a builder-ready metadata validation." > "$OUT/collection-complete.txt" || exit 1
