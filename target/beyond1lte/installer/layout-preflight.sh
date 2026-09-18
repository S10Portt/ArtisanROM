#!/sbin/sh
# Pre-write partition layout guard for beyond1lte.
#
# This build assumes the user-measured repartition profile
# "user-repartition-20260913" (target/beyond1lte/layouts/user-repartition-20260913.json,
# expected byte sizes sourced from target/beyond1lte/layouts/measurement/layout.json,
# sha256 5b331c34ceef922602b0ff3d771dc4bf19ac2f32ed5b0d89c3d62a8eb711e4db).
# It is NOT a stock/universal G973F or G973N layout. Before any
# block_image_update() call writes to a partition, confirm the device
# actually attached at install time has the exact same byte size this
# build expects -- fail closed (nonzero exit -> assert() aborts the
# install) rather than let block_image_update discover a mismatch
# mid-write.
#
# Scope: only the 6 partitions this installer actually writes
# (system/vendor/product/boot/dtb/dtbo). odm/prism/optics/up_param are
# preserve-only (never written by this installer, see
# target/beyond1lte/README.md) and are guarded at
# build time by scripts/utils/s10_installer_guard.py instead -- this
# script does not touch them.

# LAYOUT_PREFLIGHT_BLOCK_ROOTS / LAYOUT_PREFLIGHT_SYS_CLASS_BLOCK: only ever
# set by this script's own test harness (see the fixture test invoked from
# scripts/), never in a real recovery environment -- lets the exact same
# resolution logic run against a fake root instead of the real /dev, /sys.
BLOCK_ROOTS="${LAYOUT_PREFLIGHT_BLOCK_ROOTS:-/dev/block/platform/13d60000.ufs/by-name /dev/block/bootdevice/by-name /dev/block/by-name}"
SYS_CLASS_BLOCK="${LAYOUT_PREFLIGHT_SYS_CLASS_BLOCK:-/sys/class/block}"

fail() {
    echo "layout-preflight: FAIL: $1" 1>&2
    exit 1
}

resolve_link() {
    # Prints the resolved by-name path for $1, or nothing if not found.
    local name="$1"
    local root
    for root in $BLOCK_ROOTS; do
        if [ -e "$root/$name" ]; then
            echo "$root/$name"
            return 0
        fi
    done
    return 1
}

sysfs_size_path() {
    # Prints a readable <SYS_CLASS_BLOCK>/*/size path for device node $1,
    # searching both the flat and nested (holder/parent) layouts different
    # kernels expose, or nothing if not found.
    local devnode="$1"
    if [ -r "$SYS_CLASS_BLOCK/$devnode/size" ]; then
        echo "$SYS_CLASS_BLOCK/$devnode/size"
        return 0
    fi
    local candidate
    for candidate in "$SYS_CLASS_BLOCK"/*/"$devnode"/size; do
        if [ -r "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

check_partition() {
    local name="$1"
    local expected_bytes="$2"

    local link
    link="$(resolve_link "$name")" || fail "partition '$name' not found under any known by-name path"

    local real
    real="$(readlink -f "$link" 2>/dev/null)"
    [ -n "$real" ] || real="$link"
    local devnode
    devnode="$(basename "$real")"

    local sizepath
    sizepath="$(sysfs_size_path "$devnode")" || fail "cannot resolve /sys/class/block size for '$name' (device $devnode)"

    local sectors
    sectors="$(cat "$sizepath" 2>/dev/null)"
    case "$sectors" in
        ''|*[!0-9]*) fail "non-numeric block size reported for '$name': '$sectors'" ;;
    esac

    local actual_bytes=$((sectors * 512))
    if [ "$actual_bytes" != "$expected_bytes" ]; then
        fail "'$name' size mismatch: this build expects ${expected_bytes} bytes (user-repartition-20260913), device reports ${actual_bytes} bytes (${link} -> ${real}). This is very likely NOT the measured device; refusing to write."
    fi
    echo "layout-preflight: OK: $name = ${actual_bytes} bytes (${link})"
}

check_partition "system"  7340032000
check_partition "vendor"  1572864000
check_partition "product" 1572864000
check_partition "boot"    57671680
check_partition "dtb"     8388608
check_partition "dtbo"    8388608

echo "layout-preflight: PASSED"
exit 0
