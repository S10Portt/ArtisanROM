# S10 legacy VNDK is independent of the (unobserved) board API property.
# Keep the existing path below unchanged for other targets.
if [[ "$TARGET_CODENAME" == "beyond1lte" ]]; then
    if [[ "$TARGET_LEGACY_VNDK_VERSION" != "31" ]]; then
        LOGE "Unsupported S10 legacy VNDK requirement"
        return 1
    fi
    source "$SRC_DIR/scripts/utils/s10_inputs.sh" || return 1
    CHECK_S10_PROPERTY "$WORK_DIR/vendor/build.prop" ro.vndk.version 31 || return 1
    if $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION; then
        SYS_EXT_DIR="$WORK_DIR/system_ext"
    else
        SYS_EXT_DIR="$WORK_DIR/system/system/system_ext"
    fi
    if [[ ! -f "$SYS_EXT_DIR/etc/vintf/manifest.xml" ||
            ! -r "$SYS_EXT_DIR/etc/vintf/manifest.xml" || -L "$SYS_EXT_DIR/etc/vintf/manifest.xml" ]]; then
        LOGE "Invalid S10 framework manifest file"
        return 1
    fi
    # Do not rewrite unrelated HAL versions or assume a patched donor manifest.
    if ! python3 - "$SYS_EXT_DIR/etc/vintf/manifest.xml" <<'PY_VNDK'
import sys
import xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
    if root.tag != "manifest" or root.get("type") != "framework":
        raise ValueError("expected a framework manifest root")
    declarations = root.findall("vendor-ndk")
    if len(declarations) != 1:
        raise ValueError("unsupported input: expected exactly one vendor-ndk declaration")
    versions = declarations[0].findall("version")
    if len(versions) != 1 or (versions[0].text or "").strip() != "31":
        raise ValueError("unsupported input: expected exactly one version 31")
except (OSError, ET.ParseError, ValueError) as error:
    print(f"S10 VNDK manifest validation failed: {error}", file=sys.stderr)
    sys.exit(1)
PY_VNDK
    then
        unset SYS_EXT_DIR
        return 1
    fi
    VNDK_APEX="$SYS_EXT_DIR/apex/com.android.vndk.v31.apex"
    if [[ -e "$VNDK_APEX" || -L "$VNDK_APEX" ]]; then
        if [[ ! -f "$VNDK_APEX" || ! -r "$VNDK_APEX" || ! -s "$VNDK_APEX" || -L "$VNDK_APEX" ]]; then
            LOGE "Existing S10 VNDK APEX is invalid; refusing to replace damaged input"
            return 1
        fi
    else
        ADD_TO_WORK_DIR "b0qxxx" "system_ext" "apex/com.android.vndk.v31.apex" \
            0 0 644 "u:object_r:system_file:s0" || return 1
    fi
    if [[ ! -f "$VNDK_APEX" || ! -r "$VNDK_APEX" || ! -s "$VNDK_APEX" || -L "$VNDK_APEX" ]]; then
        LOGE "Missing S10 VNDK v31 APEX after copy"
        unset SYS_EXT_DIR
        return 1
    fi
    # Observed GZD7 v31 APEX is byte-identical to the existing b0qxxx prebuilt.
    # This verifies the selected file, not its signature or runtime namespace.
    VNDK_EXPECTED_SHA256="f428c431923efde9cfdaabb387ef5bcd3efe1adf1f9515bcf4c6c66bba931bca"
    VNDK_ACTUAL_SHA256="$(sha256sum "$VNDK_APEX")" || return 1
    if [[ "${VNDK_ACTUAL_SHA256%% *}" != "$VNDK_EXPECTED_SHA256" ]]; then
        LOGE "S10 VNDK v31 APEX differs from the observed GZD7/prebuilt file"
        return 1
    fi
    unset SYS_EXT_DIR VNDK_APEX VNDK_EXPECTED_SHA256 VNDK_ACTUAL_SHA256
    return 0
fi

if [[ "$SOURCE_BOARD_API_LEVEL" == "$TARGET_BOARD_API_LEVEL" ]]; then
    LOG "\033[0;33m! Nothing to do\033[0m"
    return 0
fi

# [
ADD_TARGET_VNDK_APEX() {
    case "$TARGET_BOARD_API_LEVEL" in
        "30")
            ADD_TO_WORK_DIR "a73xqxx" "system_ext" "apex/com.android.vndk.v30.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        "31")
            ADD_TO_WORK_DIR "b0qxxx" "system_ext" "apex/com.android.vndk.v31.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        "32")
            ADD_TO_WORK_DIR "b4qxxx" "system_ext" "apex/com.android.vndk.v32.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        "33")
            ADD_TO_WORK_DIR "dm1qxxx" "system_ext" "apex/com.android.vndk.v33.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        *)
            ABORT "No APEX blob available for VNDK $TARGET_BOARD_API_LEVEL"
            ;;
    esac
}
# ]

if $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION; then
    SYS_EXT_DIR="$WORK_DIR/system_ext"
else
    SYS_EXT_DIR="$WORK_DIR/system/system/system_ext"
fi

if [ "$SOURCE_BOARD_API_LEVEL" -gt "34" ] && [ "$TARGET_BOARD_API_LEVEL" -gt "34" ]; then
    :
elif [ "$SOURCE_BOARD_API_LEVEL" -gt "34" ] && [ "$TARGET_BOARD_API_LEVEL" -le "34" ]; then
    ADD_TARGET_VNDK_APEX
    LOG "- Patching ${SYS_EXT_DIR//$WORK_DIR/}/etc/vintf/manifest.xml"
    EVAL "sed -i \"\\\$d\" \"$SYS_EXT_DIR/etc/vintf/manifest.xml\""
    {
        echo "    <vendor-ndk>"
        echo "        <version>$TARGET_BOARD_API_LEVEL</version>"
        echo "    </vendor-ndk>"
        echo "</manifest>"
    } >> "$SYS_EXT_DIR/etc/vintf/manifest.xml"
elif [ "$SOURCE_BOARD_API_LEVEL" -le "34" ] && [ "$TARGET_BOARD_API_LEVEL" -gt "34" ]; then
    DELETE_FROM_WORK_DIR "system_ext" "apex/com.android.vndk.v$SOURCE_BOARD_API_LEVEL.apex"
    LOG "- Patching ${SYS_EXT_DIR//$WORK_DIR/}/etc/vintf/manifest.xml"
    EVAL "sed -i -e \"/vendor-ndk/d\" -e \"/version>/d\" \"$SYS_EXT_DIR/etc/vintf/manifest.xml\""
elif [ ! -f "$SYS_EXT_DIR/apex/com.android.vndk.v$TARGET_BOARD_API_LEVEL.apex" ]; then
    DELETE_FROM_WORK_DIR "system_ext" "apex/com.android.vndk.v$SOURCE_BOARD_API_LEVEL.apex"
    ADD_TARGET_VNDK_APEX
    LOG "- Patching ${SYS_EXT_DIR//$WORK_DIR/}/etc/vintf/manifest.xml"
    EVAL "sed -i \"s/version>$SOURCE_BOARD_API_LEVEL/version>$TARGET_BOARD_API_LEVEL/g\" \"$SYS_EXT_DIR/etc/vintf/manifest.xml\""
fi

unset SYS_EXT_DIR
unset -f ADD_TARGET_VNDK_APEX
