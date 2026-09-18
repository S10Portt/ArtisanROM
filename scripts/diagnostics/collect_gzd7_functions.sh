#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# User-run, read-only collection; no build/configuration/framework setup.
set -euo pipefail
IMAGE="${1:?usage: collect_gzd7_functions.sh SYSTEM_IMAGE OUTPUT_PARENT}"
PARENT="${2:?output parent required}"
[[ -f "$IMAGE" && ! -L "$IMAGE" && -d "$PARENT" ]] || exit 1
OUT=$(mktemp -d "$PARENT/gzd7-functions.XXXXXX")
MOUNT_POINT="$OUT/mount"
mkdir "$MOUNT_POINT"
MOUNTED=false
cleanup() {
    if "$MOUNTED"; then
        sudo umount "$MOUNT_POINT" || { echo "Unmount failed: $MOUNT_POINT" >&2; return 1; }
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sha256sum -- "$IMAGE" > "$OUT/image.before.sha256"
sudo -v
sudo mount -t f2fs -o loop,ro,norecovery "$IMAGE" "$MOUNT_POINT"
MOUNTED=true
FILES=(
    system/build.prop
    system/framework/framework.jar
    system/framework/services.jar
    system/framework/telephony-common.jar
    system/framework/semwifi-service.jar
    system/system_ext/priv-app/SystemUI/SystemUI.apk
    system/priv-app/SecSettings/SecSettings.apk
    system/apex/com.android.bt.apex
    system/lib64/libstagefright.so
)
for FILE in "${FILES[@]}"; do
    sudo test -f "$MOUNT_POINT/$FILE" || exit 1
    if sudo test -L "$MOUNT_POINT/$FILE"; then
        echo "Unexpected symlink: $FILE" >&2
        exit 1
    fi
    sudo sha256sum "$MOUNT_POINT/$FILE" >> "$OUT/files.sha256"
done
sudo tar -C "$MOUNT_POINT" -cf - -- "${FILES[@]}" > "$OUT/functions.tar" 2> "$OUT/tar.errors.txt"
[[ ! -s "$OUT/tar.errors.txt" ]] || exit 1
sudo umount "$MOUNT_POINT"
MOUNTED=false
sha256sum -- "$IMAGE" > "$OUT/image.after.sha256"
cmp "$OUT/image.before.sha256" "$OUT/image.after.sha256"
sha256sum "$OUT/functions.tar" > "$OUT/archive.sha256"
printf '%s\n' 'Collection complete; firmware compatibility is not certified.' > "$OUT/complete.txt"
printf 'Analysis inputs: %s\n' "$OUT"
