# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only preflight for the experimental S10 port. No tool setup or downloads.

# Exactly one definition is required; matching one of several values is not enough.
CHECK_S10_PROPERTY()
{
    local FILE="$1" KEY="$2" EXPECTED="$3"
    if [[ ! -f "$FILE" || ! -r "$FILE" || -L "$FILE" ]]; then
        echo "Invalid S10 property file: $FILE" >&2
        return 1
    fi
    if ! awk -v key="$KEY" -v expected="$EXPECTED" '
        /^[[:space:]]*#/ { next }
        {
            separator = index($0, "=")
            if (!separator) next
            name = substr($0, 1, separator - 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
            if (name == key) {
                count++
                value = substr($0, separator + 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                if (value != expected) invalid = 1
            }
        }
        END { exit (count != 1 || invalid) }
    ' "$FILE"; then
        echo "S10 property must have one definition: $KEY=$EXPECTED in $FILE" >&2
        return 1
    fi
}

# Validate the work/final kernel set independently of the source provenance manifest.
CHECK_S10_KERNEL_SET()
{
    local ROOT="$1" FILE NAME MODE="${2:-kernel}"
    [[ "$MODE" == kernel || "$MODE" == package ]] || return 1
    [[ -d "$ROOT" && -r "$ROOT" && -x "$ROOT" && ! -L "$ROOT" ]] || return 1
    for NAME in boot.img dtb.img dtbo.img; do
        FILE="$ROOT/$NAME"
        if [[ ! -f "$FILE" || ! -r "$FILE" || ! -s "$FILE" || -L "$FILE" ]]; then
            echo "Missing or invalid S10 kernel image: $FILE" >&2
            return 1
        fi
    done
    for FILE in "$ROOT"/*.img "$ROOT"/.*.img; do
        [[ -e "$FILE" || -L "$FILE" ]] || continue
        case "${FILE##*/}" in boot.img|dtb.img|dtbo.img) ;;
            odm.img|prism.img|optics.img) [[ "$MODE" == package ]] || return 1 ;; *)
            echo "Unexpected S10 kernel image: $FILE" >&2
            return 1 ;;
        esac
    done
}

CHECK_S10_LAYOUT()
{
    [[ "$TARGET_SUPER_PARTITION_SIZE" == "0" ]] || return 1
    python3 "$SRC_DIR/scripts/utils/s10_layout.py" "$SRC_DIR" "$TARGET_LAYOUT_PROFILE" --check \
        "TARGET_SYSTEM_PARTITION_SIZE=$TARGET_SYSTEM_PARTITION_SIZE" \
        "TARGET_VENDOR_PARTITION_SIZE=$TARGET_VENDOR_PARTITION_SIZE" \
        "TARGET_PRODUCT_PARTITION_SIZE=$TARGET_PRODUCT_PARTITION_SIZE" \
        "TARGET_BOOT_PARTITION_SIZE=$TARGET_BOOT_PARTITION_SIZE" \
        "TARGET_DTB_PARTITION_SIZE=$TARGET_DTB_PARTITION_SIZE" \
        "TARGET_DTBO_PARTITION_SIZE=$TARGET_DTBO_PARTITION_SIZE"
}

CHECK_S10_INPUTS()
{
    [[ "$TARGET_CODENAME" == "beyond1lte" ]] || return 0
    CHECK_S10_LAYOUT || return 1
    python3 -B "$SRC_DIR/scripts/utils/s10_auxiliary_images.py" verify "$OUT_DIR/inputs/s10-auxiliary" || return 1
    if [[ "$TARGET_OS_FILE_SYSTEM_TYPE" != "erofs" ]]; then
        echo "S10 requires the selected EROFS OS policy; regenerate stale configuration" >&2
        return 1
    fi

    if [[ "$TARGET_FIRMWARE_OFFLINE" != "true" || "$TARGET_FIRMWARE" != "SM-G973F/AUT" ]]; then
        echo "beyond1lte requires the prepared offline SM-G973F/AUT firmware cache" >&2
        return 1
    fi

    if [[ -n "$TARGET_EXTRA_FIRMWARES" ]]; then
        echo "S10 offline target extras have no defined input contract; refusing to ignore them" >&2
        return 1
    fi
    local ROOT="$FW_DIR/SM-G973F_AUT"
    local PARTITION FILE
    python3 "$SRC_DIR/scripts/utils/s10_registered_input.py" "$ROOT" || return 1
    # HWC1 product is an identity-only input. OS product comes from GZD7;
    # ADD_TO_WORK_DIR rejects copying the HWC1 product under this contract.
    for PARTITION in system vendor odm odm_dlkm system_dlkm vendor_dlkm; do
        case "$PARTITION" in
            system|vendor) ;;
            *) [ -d "$ROOT/$PARTITION" ] || continue ;;
        esac
        for FILE in "$ROOT/$PARTITION" "$ROOT/fs_config-$PARTITION" "$ROOT/file_context-$PARTITION"; do
            if [ ! -e "$FILE" ]; then
                echo "Missing S10 input: $FILE (see target/beyond1lte/README.md)" >&2
                return 1
            fi
        done
        if [ ! -d "$ROOT/$PARTITION" ] || [ ! -s "$ROOT/fs_config-$PARTITION" ] ||
                [ ! -s "$ROOT/file_context-$PARTITION" ]; then
            echo "Incomplete S10 partition or metadata: $PARTITION" >&2
            return 1
        fi
    done
    python3 "$SRC_DIR/scripts/utils/s10_validate_inputs.py" raw-links \
        "$FW_DIR" "$SOURCE_FIRMWARE" "$TARGET_FIRMWARE" "$WORK_DIR" || return 1
    CHECK_S10_PROPERTY "$ROOT/vendor/build.prop" ro.product.vendor.model SM-G973F || return 1
    CHECK_S10_PROPERTY "$ROOT/vendor/build.prop" ro.vendor.build.version.incremental G973FXXSGHWC1 || return 1
    CHECK_S10_PROPERTY "$ROOT/vendor/build.prop" ro.product.vendor.name beyond1ltexx || return 1
    CHECK_S10_PROPERTY "$ROOT/system/system/build.prop" ro.build.version.incremental G973FXXSGHWC1 || return 1
    if [ ! -f "$ROOT/product/build.prop" ] && [ ! -f "$ROOT/product/etc/build.prop" ]; then
        echo "Missing S10 product build.prop" >&2
        return 1
    fi
    CHECK_S10_STOCK_DATA "$ROOT" || return 1
    # Existing unica/mods/prophide reads the original target vbmeta.
    if [ ! -s "$ROOT/avb/vbmeta.img" ]; then
        echo "Missing original S10 avb/vbmeta.img (do not substitute a patched image)" >&2
        return 1
    fi
    CHECK_S10_KERNEL
}

CHECK_S10_KERNEL()
{
    local ROOT="$SRC_DIR/target/beyond1lte/kernel"
    local EXPECTED_COMMIT="bf6931b605aacb7f434d6ff440344a0c3e1f92e1"
    CHECK_S10_KERNEL_SET "$ROOT" || return 1
    case "$TARGET_KERNEL_INPUT_KIND" in
        source)
            if [[ ! -f "$ROOT/source.commit" || -L "$ROOT/source.commit" ]] ||
                    [ "$(cat "$ROOT/source.commit" 2>/dev/null)" != "$EXPECTED_COMMIT" ]; then
                echo "S10 source kernel source.commit must record $EXPECTED_COMMIT" >&2
                return 1
            fi
            local EXPECTED_PATCH_FILE="$SRC_DIR/target/beyond1lte/kernel/source.patch.sha256.expected"
            local EXPECTED_PATCH
            [[ -f "$EXPECTED_PATCH_FILE" && ! -L "$EXPECTED_PATCH_FILE" ]] || return 1
            EXPECTED_PATCH=$(cat "$EXPECTED_PATCH_FILE") || return 1
            if [[ ! "$EXPECTED_PATCH" =~ ^[0-9a-f]{64}$ ||
                  ! -f "$ROOT/source.patch.sha256" || -L "$ROOT/source.patch.sha256" ]] ||
                    [[ "$(cat "$ROOT/source.patch.sha256" 2>/dev/null)" != "$EXPECTED_PATCH" ]]; then
                echo "S10 source kernel must record the selected local source patch in source.patch.sha256" >&2
                return 1
            fi ;;
        artisan311)
            # Do not label an observed prebuilt with an unrelated source commit.
            if [[ -e "$ROOT/source.commit" || -L "$ROOT/source.commit" || -e "$ROOT/source.patch.sha256" || -L "$ROOT/source.patch.sha256" ]]; then
                echo "artisan311 kernel input must not carry source-built provenance markers" >&2
                return 1
            fi
            python3 - "$ROOT" <<'PY_S10_KERNEL'
import hashlib
import json
from pathlib import Path
import sys
try:
    root = Path(sys.argv[1])
    manifest = root / "artisan311.json"
    if manifest.is_symlink() or not manifest.is_file():
        raise ValueError("invalid artisan311 kernel provenance file")
    expected = json.loads(manifest.read_text())["sha256"]
    if set(expected) != {"boot.img", "dtb.img", "dtbo.img"}:
        raise ValueError("incomplete artisan311 kernel provenance")
    for name, digest in expected.items():
        file = root / name
        if file.is_symlink() or not file.is_file() or not file.stat().st_size:
            raise ValueError(f"invalid prebuilt kernel input: {name}")
        if hashlib.sha256(file.read_bytes()).hexdigest() != digest:
            raise ValueError(f"prebuilt kernel differs from observed artisan311: {name}")
except (OSError, ValueError, KeyError, TypeError) as error:
    print(f"S10 prebuilt kernel validation failed: {error}", file=sys.stderr)
    sys.exit(1)
PY_S10_KERNEL
            [[ "$?" -eq 0 ]] || return 1 ;;
        *) echo "Unsupported S10 kernel input kind: $TARGET_KERNEL_INPUT_KIND" >&2; return 1 ;;
    esac
    if [ ! -s "$ROOT/SHA256SUMS" ]; then
        echo "Missing S10 kernel SHA256SUMS" >&2
        return 1
    fi

    local DIGEST NAME EXTRA ACTUAL
    local SEEN=" "
    local COUNT=0
    while read -r DIGEST NAME EXTRA || [[ -n "$DIGEST$NAME$EXTRA" ]]; do
        if [[ ! "$DIGEST" =~ ^[0-9a-f]{64}$ || -n "$EXTRA" ]]; then
            echo "Malformed S10 kernel checksum entry" >&2
            return 1
        fi
        case "$NAME" in boot.img|dtb.img|dtbo.img) ;; *)
            echo "Unexpected S10 kernel checksum filename: $NAME" >&2
            return 1 ;;
        esac
        if [[ "$SEEN" == *" $NAME "* ]] || [ ! -s "$ROOT/$NAME" ] || [ -L "$ROOT/$NAME" ]; then
            echo "Missing, duplicate or symlinked S10 kernel input: $NAME" >&2
            return 1
        fi
        ACTUAL="$(sha256sum "$ROOT/$NAME")" || return 1
        if [[ "${ACTUAL%% *}" != "$DIGEST" ]]; then
            echo "S10 kernel checksum mismatch: $NAME" >&2
            return 1
        fi
        SEEN+="$NAME "
        COUNT=$((COUNT + 1))
    done < "$ROOT/SHA256SUMS"
    if [ "$COUNT" -ne 3 ]; then
        echo "S10 kernel manifest must contain boot.img, dtb.img and dtbo.img" >&2
        return 1
    fi
}

# Input parsing only; do not execute this helper during source-only review.
CHECK_S10_STOCK_DATA()
{
    python3 - "$1" "$SRC_DIR/target/beyond1lte" <<'PY_S10_STOCK'
import json
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

root, target = map(Path, sys.argv[1:])

def require_file(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"missing, empty or unsupported stock input: {path}")
    return path

try:
    listing = require_file(target / "stock-system-files.txt")
    paths = [line.strip() for line in listing.read_text().splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    if not paths or len(paths) != len(set(paths)):
        raise ValueError("empty or duplicate stock file list")
    for name in paths:
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts or not name.startswith("system/"):
            raise ValueError(f"invalid stock relative path: {name}")
        file = require_file(root / "system" / relative)
        if file.suffix == ".xml":
            ET.parse(file)
        else:
            with file.open("rb") as stream:
                stream.read(1)
    portrait = require_file(root / "system/system/cameradata/portrait_data/single_bokeh_feature.json")
    json.loads(portrait.read_text())
    for name in ("singletake/service-feature.xml", "aremoji-feature.xml", "camera-feature.xml"):
        override = target / "camera" / name
        # A malformed override must not silently fall back to stock.
        if override.exists() or override.is_symlink() or name == "camera-feature.xml":
            file = require_file(override)
        else:
            file = require_file(root / "system/system/cameradata" / name)
        ET.parse(file)
except (OSError, UnicodeError, ValueError, ET.ParseError) as error:
    print(f"S10 stock/camera input validation failed: {error}", file=sys.stderr)
    sys.exit(1)
PY_S10_STOCK
}

CHECK_S10_SOURCE_INPUTS()
{
    python3 "$SRC_DIR/scripts/utils/s10_registered_input.py" \
        "$FW_DIR/SM-S908B_EUX" || return 1
    python3 "$SRC_DIR/scripts/utils/s10_validate_inputs.py" source \
        "$FW_DIR" "$SOURCE_FIRMWARE" "$TARGET_FIRMWARE" "$WORK_DIR"
}

CHECK_S10_ZIP_INPUTS()
{
    CHECK_S10_LAYOUT || return 1
    python3 -B "$SRC_DIR/scripts/utils/s10_auxiliary_images.py" verify "$OUT_DIR/inputs/s10-auxiliary" || return 1
    python3 "$SRC_DIR/scripts/utils/s10_auxiliary_contract.py" work "$WORK_DIR" || return 1
    python3 "$SRC_DIR/scripts/utils/s10_validate_inputs.py" zip \
        "$FW_DIR" "$SOURCE_FIRMWARE" "$TARGET_FIRMWARE" "$WORK_DIR" || return 1
    CHECK_S10_KERNEL_SET "$WORK_DIR/kernel"
}
