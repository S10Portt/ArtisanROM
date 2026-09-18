# Copyright (c) 2025 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# [
source "$SRC_DIR/scripts/utils/log_utils.sh"

_CHECK_NON_EMPTY_PARAM()
{
    if [ ! "$2" ]; then
        echo -n -e '\033[0;31m' >&2

        local STACK_SIZE="${#FUNCNAME[@]}"
        if [[ "$STACK_SIZE" -gt "1" ]]; then
            echo -n "(" >&2
            if [[ "$STACK_SIZE" -gt "2" ]]; then
                echo -n "${BASH_SOURCE[2]//$SRC_DIR\//}:${BASH_LINENO[1]}:" >&2
            fi
            echo -n "${FUNCNAME[1]}) " >&2
        fi

        echo -n "$1 is not set!" >&2
        echo -e '\033[0m' >&2

        return 1
    fi

    return 0
}

_GET_PROP_FILES_PATH()
{
    local PARTITION="$1"
    local FILES=()

    if IS_VALID_PARTITION_NAME "$PARTITION"; then
        case "$PARTITION" in
            "system")
                FILES+=("$WORK_DIR/system/system/build.prop")
                ;;
            "vendor")
                FILES+=(
                    "$WORK_DIR/vendor/default.prop"
                    "$WORK_DIR/vendor/build.prop"
                )
                ;;
            "product")
                FILES+=("$WORK_DIR/product/etc/build.prop")
                ;;
            "system_ext")
                FILES+=(
                    "$WORK_DIR/system_ext/etc/build.prop"
                    "$WORK_DIR/system/system/system_ext/etc/build.prop"
                )
                ;;
            "odm")
                FILES+=("$WORK_DIR/odm/etc/build.prop")
                ;;
            "vendor_dlkm")
                FILES+=(
                    "$WORK_DIR/vendor_dlkm/etc/build.prop"
                    "$WORK_DIR/vendor/vendor_dlkm/etc/build.prop"
                )
                ;;
            "odm_dlkm")
                FILES+=("$WORK_DIR/vendor/odm_dlkm/etc/build.prop")
                ;;
            "system_dlkm")
                FILES+=(
                    "$WORK_DIR/system_dlkm/etc/build.prop"
                    "$WORK_DIR/system/system/system_dlkm/etc/build.prop"
                )
                ;;
        esac
    else
        # https://android.googlesource.com/platform/system/core/+/refs/tags/android-15.0.0_r1/init/property_service.cpp#1214
        FILES+=(
            "$WORK_DIR/system/system/build.prop"
            "$WORK_DIR/system_ext/etc/build.prop"
            "$WORK_DIR/system/system/system_ext/etc/build.prop"
            "$WORK_DIR/system_dlkm/etc/build.prop"
            "$WORK_DIR/system/system/system_dlkm/etc/build.prop"
            "$WORK_DIR/vendor/default.prop"
            "$WORK_DIR/vendor/build.prop"
            "$WORK_DIR/vendor_dlkm/etc/build.prop"
            "$WORK_DIR/vendor/vendor_dlkm/etc/build.prop"
            "$WORK_DIR/vendor/odm_dlkm/etc/build.prop"
            "$WORK_DIR/odm/etc/build.prop"
            "$WORK_DIR/product/etc/build.prop"
        )
    fi

    printf '%s\n' "${FILES[@]}"
}

_GET_PROP_LOCATION()
{
    local FILES
    FILES="$(_GET_PROP_FILES_PATH "$1")"

    if IS_VALID_PARTITION_NAME "$1"; then
        shift
    fi

    _CHECK_NON_EMPTY_PARAM "PROP" "$1" || return 1

    local PROP="$1"
    local MATCHES=()
    while IFS= read -r f; do
        if grep -q "^$PROP=" "$f" 2> /dev/null; then
            MATCHES+=("$f")
        fi
    done <<< "$FILES"

    printf '%s\n' "${MATCHES[@]}"
}

_GET_SELINUX_LABEL()
{
    _CHECK_NON_EMPTY_PARAM "PARTITION" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "FILE" "$2" || return 1

    local PARTITION="$1"
    local FILE="$2"
    local FC_FILE

    case "$PARTITION" in
        "product")
            FC_FILE="$WORK_DIR/product/etc/selinux/product_file_contexts"
            ;;
        "vendor")
            FC_FILE="$WORK_DIR/vendor/etc/selinux/vendor_file_contexts"
            ;;
        "system_ext")
            if $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION; then
                FC_FILE="$WORK_DIR/system_ext/etc/selinux/system_ext_file_contexts"
            else
                FC_FILE="$WORK_DIR/system/system/system_ext/etc/selinux/system_ext_file_contexts"
            fi
            ;;
        *)
            FC_FILE="$WORK_DIR/system/system/etc/selinux/plat_file_contexts"
            ;;
    esac

    if [ ! -f "$FC_FILE" ]; then
        LOGE "File not found: ${FC_FILE//$WORK_DIR/}"
        return 1
    fi

    if [[ "${FILE:0:1}" != "/" ]]; then
        FILE="/$FILE"
    fi

    local LABEL
    LABEL=$(perl -ne '
        next if /^\s*#/ || /^\s*$/;
        s/\s+/ /g;
        my ($pattern, $label) = split(" ", $_, 3);
        if ($ARGV[0] =~ /^$pattern$/) {
            print "$label\n";
            exit;
        }
    ' - "$FILE" <<< "$(tac "$FC_FILE")")
    echo "$LABEL"
}

_HANDLE_SPECIAL_CHARS()
{
    local STRING="${1:?}"

    STRING="${STRING//\./\\.}"
    STRING="${STRING//\+/\\+}"
    STRING="${STRING//\[/\\[}"
    STRING="${STRING//\]/\\]}"
    STRING="${STRING//\*/\\*}"

    echo "$STRING"
}
# ]

# Exact literal key lookup for converted S10 firmware metadata.
# STRICT_RAW_METADATA is local to ADD_TO_WORK_DIR (Bash dynamic scope).
_MATCH_METADATA_LINE()
{
    if [[ "${STRICT_RAW_METADATA:-false}" == "true" ]]; then
        awk 'BEGIN { key=ARGV[1]; ARGV[1]="" }
            $1 == key { print; found++ }
            END { if (found != 1) exit 1 }' "$2" "$1"
    else
        grep -F "$2 " "$1"
    fi
}

# Remove a serialized key (and optionally descendants), without evaluating regex.
# Preserve comments, whitespace and unrelated type-qualified context rules.
_REMOVE_METADATA_KEY()
{
    local META="$1" KEY="$2" RECURSIVE="${3:-false}" COPY IS_CONTEXT=false
    [[ "$META" == */file_context-* ]] && IS_CONTEXT=true
    [[ -f "$META" && -r "$META" && ! -L "$META" ]] || return 1
    COPY=$(mktemp "${META}.edit.XXXXXX") || return 1
    cp -p -- "$META" "$COPY" || return 1
    awk 'function literal(value, i,c) {
            for (i=1;i<=length(value);i++) {
                c=substr(value,i,1)
                if (c=="\\") {
                    i++; if (i>length(value) || index(".+[]*",substr(value,i,1))==0) return 0
                } else if (index(".+[]*^$?{}()|",c)>0) return 0
            }
            return 1
        }
        BEGIN { key=ARGV[1]; recursive=ARGV[2]; context=ARGV[3]; ARGV[1]=""; ARGV[2]=""; ARGV[3]="" }
        /^[[:space:]]*#/ || NF==0 { print; next }
        context=="true" && !literal($1) { print; next }
        $1==key { next }
        recursive=="true" && index($1,key "/")==1 { next }
        { print }' "$KEY" "$RECURSIVE" "$IS_CONTEXT" "$META" > "$COPY" || return 1
    mv -f -- "$COPY" "$META" || return 1
}

# ADD_TO_WORK_DIR <source> <partition> <file/dir> <user> <group> <mode> <label> [S10 metadata policy]
# Adds the supplied file/directory in work dir along with its entries in fs_config/file_context.
#
# `source` argument can be:
# - a full path
# - a string in the following format: "MODEL/CSC" (the folder MUST exist under `out/fw`)
# - a string with the product name of the desidered device's prebuilt blobs (the folder MUST exist under `prebuilts/samsung`)
#
# `user`/`group`/`mode`/`label`/ arguments can be omitted as long as the respective entry is present in `source`/fs_config and `source`/file_context.
ADD_TO_WORK_DIR()
{
    _CHECK_NON_EMPTY_PARAM "SOURCE" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "PARTITION" "$2" || return 1
    _CHECK_NON_EMPTY_PARAM "FILE" "$3" || return 1

    local SOURCE="$1"
    local PARTITION="$2"
    local FILE="$3"
    local METADATA_POLICY="${8:-}"
    local USER="$4"
    local GROUP="$5"
    local MODE="$6"
    local LABEL="$7"

    if [ ! -d "$SOURCE" ]; then
        if [ "$(cut -d "/" -f 2 -s <<< "$SOURCE")" ]; then
            SOURCE="$FW_DIR/$(cut -d "/" -f 1 <<< "$SOURCE")_$(cut -d "/" -f 2 <<< "$SOURCE")"
        else
            SOURCE="$SRC_DIR/prebuilts/samsung/$SOURCE"
        fi
    fi

    if [ ! -d "$SOURCE" ]; then
        LOGE "Folder not found: ${SOURCE//$SRC_DIR\//}"
        return 1
    fi

    if [[ "$TARGET_CODENAME" == "beyond1lte" && "$PARTITION" == "product" ]] &&
            { [[ "$SOURCE" == "$FW_DIR/SM-G973F_AUT" ]] ||
              [[ "$SOURCE/product" -ef "$FW_DIR/SM-G973F_AUT/product" ]]; }; then
        LOGE "HWC1 product is identity-only; copying it requires a separate metadata policy"
        return 1
    fi

    if ! IS_VALID_PARTITION_NAME "$PARTITION"; then
        LOGE "\"$PARTITION\" is not a valid partition name"
        return 1
    fi

    while [[ "${FILE:0:1}" == "/" ]]; do
        FILE="${FILE:1}"
    done

    local SOURCE_FILE="$SOURCE"
    local TARGET_FILE="$WORK_DIR"
    if [[ "$PARTITION" == "system_ext" ]]; then
        if [ -d "$SOURCE/system_ext" ]; then
            SOURCE_FILE+="/system_ext/$FILE"
        elif [ -d "$SOURCE/system/system/system_ext" ]; then
            SOURCE_FILE+="/system/system/system_ext/$FILE"
        else
            SOURCE_FILE+="/system/system_ext/$FILE"
        fi

        if $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION; then
            TARGET_FILE+="/system_ext/$FILE"
        else
            PARTITION="system"
            FILE="system/system_ext/$FILE"
            TARGET_FILE+="/system/$FILE"
        fi
    elif [[ "$PARTITION" == "system" ]]; then
        if [ -d "$SOURCE/system/system" ]; then
            SOURCE_FILE+="/system/$FILE"
            TARGET_FILE+="/system/$FILE"
        else
            SOURCE_FILE+="/system/${FILE//system\//}"
            TARGET_FILE+="/system/system/${FILE//system\//}"
        fi
    else
        SOURCE_FILE+="/$PARTITION/$FILE"
        TARGET_FILE+="/$PARTITION/$FILE"
    fi

    if [[ -n "$METADATA_POLICY" && ( "$TARGET_CODENAME" != "beyond1lte" || "$SOURCE" != "$FW_DIR/"* ) ]]; then
        LOGE "S10 metadata policy requires a firmware input in the strict path"
        return 1
    fi
    # Firmware-derived S10 data must have unique, readable source/work metadata.
    # Explicit prebuilt assets retain the original interface.
    local STRICT_RAW_METADATA=false META_FILE S10_PLAN_FILE
    local SOURCE_IS_DIR=false
    [[ -d "$SOURCE_FILE" && ! -L "$SOURCE_FILE" ]] && SOURCE_IS_DIR=true
    if [[ "$TARGET_CODENAME" == "beyond1lte" && "$SOURCE" == "$FW_DIR/"* ]]; then
        STRICT_RAW_METADATA=true
        S10_PLAN_FILE=$(mktemp "$WORK_DIR/configs/.s10-plan.XXXXXX") || return 1
        python3 "$SRC_DIR/scripts/utils/s10_metadata_plan.py" --policy "$METADATA_POLICY" \
            "$SOURCE" "$WORK_DIR" "$SOURCE_FILE" "$TARGET_FILE" "$PARTITION" \
            "$USER" "$GROUP" "$MODE" "$LABEL" > "$S10_PLAN_FILE" || return 1
        for META_FILE in "$SOURCE/fs_config-$PARTITION" "$SOURCE/file_context-$PARTITION" \
            "$WORK_DIR/configs/fs_config-$PARTITION" "$WORK_DIR/configs/file_context-$PARTITION"; do
            [[ -f "$META_FILE" && -r "$META_FILE" && ! -L "$META_FILE" ]] || {
                LOGE "Missing readable S10 metadata: $META_FILE"
                return 1
            }
            local META_KIND="context" META_SCOPE="work"
            [[ "$META_FILE" == */fs_config-* ]] && META_KIND="fs"
            [[ "$META_FILE" == "$SOURCE/"* ]] && META_SCOPE="source"
            awk 'BEGIN { kind=ARGV[1]; scope=ARGV[2]; ARGV[1]=""; ARGV[2]="" }
                /^[[:space:]]*#/ || NF==0 { next }
                {
                    key=$1
                    if (kind=="fs") {
                        offset=0
                        if (NF==4 && $0~/^[[:space:]]/) { key=""; offset=-1 }
                        else if (NF!=5) exit 1
                        uid=$(2+offset); gid=$(3+offset); mode=$(4+offset); cap=$(5+offset)
                        if (uid!~/^[0-9]+$/ || gid!~/^[0-9]+$/ || uid>4294967295 || gid>4294967295 ||
                            mode!~/^[0-7]+$/ || length(mode)>4 || cap!~/^capabilities=0x[0-9a-fA-F]+$/ || length(cap)>31) exit 1
                    } else {
                        if (NF==2) context=$2
                        else if (scope=="work" && NF==3 && $2~/^-[bcdpls-]$/) {
                            key=key " " $2; context=$3
                        } else exit 1
                        if (context!~/^[^[:space:]:]+:[^[:space:]:]+:[^[:space:]:]+:[^[:space:]]+$/ && context!="<<none>>") exit 1
                    }
                    if (seen[key]++) exit 1
                }' "$META_KIND" "$META_SCOPE" "$META_FILE" || {
                LOGE "Invalid or duplicate S10 metadata: $META_FILE"
                return 1
            }
        done
    fi

    if [ ! -e "$SOURCE_FILE" ] && [ ! -L "$SOURCE_FILE" ]; then
        if [ -e "$SOURCE_FILE.00" ]; then
            LOG "- Adding $(sed -e "s|$WORK_DIR||" -e "s|/\.||" <<< "$TARGET_FILE") from ${SOURCE//$SRC_DIR\//}"
            mkdir -p "$(dirname "$TARGET_FILE")"
            EVAL "cat \"$SOURCE_FILE.\"[0-9][0-9] > \"$TARGET_FILE\"" || exit 1
        else
            LOGE "File not found: ${SOURCE_FILE//$SRC_DIR\//}"
            return 1
        fi
    else
        LOG "- Adding $(sed -e "s|$WORK_DIR||" -e "s|/\.||" <<< "$TARGET_FILE") from ${SOURCE//$SRC_DIR\//}"
        if "$SOURCE_IS_DIR"; then
            mkdir -p "$TARGET_FILE" || return 1
        else
            mkdir -p "$(dirname "$TARGET_FILE")" || return 1
        fi
        EVAL "cp -a -T \"$SOURCE_FILE\" \"$TARGET_FILE\"" || exit 1
    fi

    local ENTRY="${TARGET_FILE//$WORK_DIR\//}"
    [[ "$PARTITION" == "system" ]] && ENTRY="${ENTRY//system\/system\//system/}"
    ENTRY="${ENTRY%/.}"

    if ! _MATCH_METADATA_LINE "$WORK_DIR/configs/fs_config-$PARTITION" "$ENTRY" > /dev/null 2>&1; then
        if [ "$USER" ] && [ "$GROUP" ] && [ "$MODE" ]; then
            echo "$ENTRY $USER $GROUP $MODE capabilities=0x0" >> "$WORK_DIR/configs/fs_config-$PARTITION"
        elif _MATCH_METADATA_LINE "$SOURCE/fs_config-$PARTITION" "$ENTRY" > /dev/null 2>&1; then
            _MATCH_METADATA_LINE "$SOURCE/fs_config-$PARTITION" "$ENTRY" >> "$WORK_DIR/configs/fs_config-$PARTITION" || return 1
        else
            if "$STRICT_RAW_METADATA"; then
                LOGE "Required S10 metadata entry was not found; refusing defaults"
                return 1
            fi
            LOGW "No fs_config entry found for \"$ENTRY\" in \"${SOURCE//$SRC_DIR\//}\". Using default values"

            USER=0
            GROUP=0
            MODE=644
            if [ -d "$TARGET_FILE" ]; then
                [[ "$PARTITION" == "vendor" ]] && GROUP=2000
                MODE=755
            fi

            echo "$ENTRY $USER $GROUP $MODE capabilities=0x0" >> "$WORK_DIR/configs/fs_config-$PARTITION"
        fi
    fi

    if ! _MATCH_METADATA_LINE "$WORK_DIR/configs/file_context-$PARTITION" "/$(_HANDLE_SPECIAL_CHARS "$ENTRY")" > /dev/null 2>&1; then
        if [ "$LABEL" ]; then
            echo "/$(_HANDLE_SPECIAL_CHARS "$ENTRY") $LABEL" >> "$WORK_DIR/configs/file_context-$PARTITION"
        elif _MATCH_METADATA_LINE "$SOURCE/file_context-$PARTITION" "/$(_HANDLE_SPECIAL_CHARS "$ENTRY")" > /dev/null 2>&1; then
            _MATCH_METADATA_LINE "$SOURCE/file_context-$PARTITION" "/$(_HANDLE_SPECIAL_CHARS "$ENTRY")" >> "$WORK_DIR/configs/file_context-$PARTITION" || return 1
        else
            if "$STRICT_RAW_METADATA"; then
                LOGE "Required S10 metadata entry was not found; refusing defaults"
                return 1
            fi
            LOGW "No file_context entry found for \"$ENTRY\" in \"${SOURCE//$SRC_DIR\//}\". Using default value"

            LABEL="$(_GET_SELINUX_LABEL "$PARTITION" "/$ENTRY")"

            echo "/$(_HANDLE_SPECIAL_CHARS "$ENTRY") $LABEL" >> "$WORK_DIR/configs/file_context-$PARTITION"
        fi
    fi

    if "$STRICT_RAW_METADATA" || "$SOURCE_IS_DIR"; then
        local FILES
        if "$STRICT_RAW_METADATA"; then
            FILES=$(cat "$S10_PLAN_FILE") || return 1
        else
        FILES="$(find "${SOURCE_FILE%/.}")" || return 1
        FILES="${FILES//$SOURCE\//}"
        [[ "$PARTITION" == "system" ]] && FILES="${FILES//system\/system\//system/}"
        if ! $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION; then
            FILES=$(sed 's|^system_ext/|system/system_ext/|' <<< "$FILES") || return 1
        fi

        fi

        while IFS= read -r f; do
            IS_VALID_PARTITION_NAME "$f" && continue

            if ! _MATCH_METADATA_LINE "$WORK_DIR/configs/fs_config-$PARTITION" "$f" > /dev/null 2>&1; then
                if _MATCH_METADATA_LINE "$SOURCE/fs_config-$PARTITION" "$f" > /dev/null 2>&1; then
                    _MATCH_METADATA_LINE "$SOURCE/fs_config-$PARTITION" "$f" >> "$WORK_DIR/configs/fs_config-$PARTITION" || return 1
                else
                    if "$STRICT_RAW_METADATA"; then
                        LOGE "Required S10 metadata entry was not found; refusing defaults"
                        return 1
                    fi
                    LOGW "No fs_config entry found for \"$f\" in \"${SOURCE//$SRC_DIR\//}\". Using default values"

                    USER=0
                    GROUP=0
                    MODE=644
                    if [ -d "$SOURCE/$f" ] || [ -d "$SOURCE/system/$f" ] || [ -d "$SOURCE/${f//system\//}" ]; then
                        [[ "$PARTITION" == "vendor" ]] && GROUP=2000
                        MODE=755
                    fi

                    echo "$f $USER $GROUP $MODE capabilities=0x0" >> "$WORK_DIR/configs/fs_config-$PARTITION"
                fi
            fi

            if ! _MATCH_METADATA_LINE "$WORK_DIR/configs/file_context-$PARTITION" "/$(_HANDLE_SPECIAL_CHARS "$f")" > /dev/null 2>&1; then
                if _MATCH_METADATA_LINE "$SOURCE/file_context-$PARTITION" "/$(_HANDLE_SPECIAL_CHARS "$f")" > /dev/null 2>&1; then
                    _MATCH_METADATA_LINE "$SOURCE/file_context-$PARTITION" "/$(_HANDLE_SPECIAL_CHARS "$f")" >> "$WORK_DIR/configs/file_context-$PARTITION" || return 1
                else
                    if "$STRICT_RAW_METADATA"; then
                        LOGE "Required S10 metadata entry was not found; refusing defaults"
                        return 1
                    fi
                    LOGW "No file_context entry found for \"$f\" in \"${SOURCE//$SRC_DIR\//}\". Using default value"

                    LABEL="$(_GET_SELINUX_LABEL "$PARTITION" "/$f")"

                    echo "/$(_HANDLE_SPECIAL_CHARS "$f") $LABEL" >> "$WORK_DIR/configs/file_context-$PARTITION"
                fi
            fi
        done <<< "$FILES"
    else
        local TMP="${TARGET_FILE%/.}"
        TMP="$(dirname "${TMP//$WORK_DIR\//}")"
        [[ "$PARTITION" == "system" ]] && TMP="${TMP//system\/system\//system/}"

        while [[ "$TMP" != "." ]]; do
            IS_VALID_PARTITION_NAME "$TMP" && break

            if ! _MATCH_METADATA_LINE "$WORK_DIR/configs/fs_config-$PARTITION" "$TMP" > /dev/null 2>&1; then
                if _MATCH_METADATA_LINE "$SOURCE/fs_config-$PARTITION" "$TMP" > /dev/null 2>&1; then
                    _MATCH_METADATA_LINE "$SOURCE/fs_config-$PARTITION" "$TMP" >> "$WORK_DIR/configs/fs_config-$PARTITION" || return 1
                else
                    if "$STRICT_RAW_METADATA"; then
                        LOGE "Required S10 metadata entry was not found; refusing defaults"
                        return 1
                    fi
                    LOGW "No fs_config entry found for \"$TMP\" in \"${SOURCE//$SRC_DIR\//}\". Using default values"

                    USER=0
                    GROUP=0
                    MODE=755
                    [[ "$PARTITION" == "vendor" ]] && GROUP=2000

                    echo "$TMP $USER $GROUP $MODE capabilities=0x0" >> "$WORK_DIR/configs/fs_config-$PARTITION"
                fi
            fi

            if ! _MATCH_METADATA_LINE "$WORK_DIR/configs/file_context-$PARTITION" "/$(_HANDLE_SPECIAL_CHARS "$TMP")" > /dev/null 2>&1; then
                if _MATCH_METADATA_LINE "$SOURCE/file_context-$PARTITION" "/$(_HANDLE_SPECIAL_CHARS "$TMP")" > /dev/null 2>&1; then
                    _MATCH_METADATA_LINE "$SOURCE/file_context-$PARTITION" "/$(_HANDLE_SPECIAL_CHARS "$TMP")" >> "$WORK_DIR/configs/file_context-$PARTITION" || return 1
                else
                    if "$STRICT_RAW_METADATA"; then
                        LOGE "Required S10 metadata entry was not found; refusing defaults"
                        return 1
                    fi
                    LOGW "No file_context entry found for \"$TMP\" in \"${SOURCE//$SRC_DIR\//}\". Using default value"

                    LABEL="$(_GET_SELINUX_LABEL "$PARTITION" "/$TMP")"

                    echo "/$(_HANDLE_SPECIAL_CHARS "$TMP") $LABEL" >> "$WORK_DIR/configs/file_context-$PARTITION"
                fi
            fi

            TMP="$(dirname "$TMP")"
        done
    fi

    if "$STRICT_RAW_METADATA"; then
        python3 "$SRC_DIR/scripts/utils/s10_metadata_plan.py" --verify-result --policy "$METADATA_POLICY" \
            "$SOURCE" "$WORK_DIR" "$SOURCE_FILE" "$TARGET_FILE" "$PARTITION" \
            "$USER" "$GROUP" "$MODE" "$LABEL" > /dev/null || return 1
        rm -f -- "$S10_PLAN_FILE" || return 1
    fi
    return 0
}

# DELETE_FROM_WORK_DIR "<partition>" "<file/dir>"
# Deletes the supplied file/directory from work dir along with its entries in fs_config/file_context.
DELETE_FROM_WORK_DIR()
{
    _CHECK_NON_EMPTY_PARAM "PARTITION" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "FILE" "$2" || return 1

    local PARTITION="$1"
    local FILE="$2"

    if ! IS_VALID_PARTITION_NAME "$PARTITION"; then
        LOGE "\"$PARTITION\" is not a valid partition name"
        return 1
    fi

    while [[ "${FILE:0:1}" == "/" ]]; do
        FILE="${FILE:1}"
    done

    if ! $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION && [[ "$PARTITION" == "system_ext" ]]; then
        PARTITION="system"
        FILE="system/system_ext/$FILE"
    fi

    local FILE_PATH="$WORK_DIR"
    case "$PARTITION" in
        "system_ext")
            if $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION; then
                FILE_PATH+="/system_ext"
            else
                FILE_PATH+="/system/system/system_ext"
            fi
            ;;
        *)
            FILE_PATH+="/$PARTITION"
            ;;
    esac
    FILE_PATH+="/$FILE"

    if [ ! -e "$FILE_PATH" ] && [ ! -L "$FILE_PATH" ]; then
        LOGW "File not found: ${FILE_PATH//$WORK_DIR/}"
        return 0
    fi

    local IS_DIR=false
    [ -d "$FILE_PATH" ] && [ ! -L "$FILE_PATH" ] && IS_DIR=true

    LOG "- Deleting ${FILE_PATH//$WORK_DIR/}"
    rm -rf "$FILE_PATH" || return 1

    local KEY="$FILE"
    [[ "$PARTITION" != "system" ]] && KEY="$PARTITION/$KEY"
    _REMOVE_METADATA_KEY "$WORK_DIR/configs/fs_config-$PARTITION" "$KEY" "$IS_DIR" || return 1
    _REMOVE_METADATA_KEY "$WORK_DIR/configs/file_context-$PARTITION" \
        "/$(_HANDLE_SPECIAL_CHARS "$KEY")" "$IS_DIR" || return 1

    if [[ "$FILE" == *".so" ]]; then
        local LIB_LIST
        for LIB_LIST in "$WORK_DIR/system/system/etc/public.libraries"*.txt; do
            [[ -e "$LIB_LIST" || -L "$LIB_LIST" ]] || continue
            _REMOVE_METADATA_KEY "$LIB_LIST" "${FILE##*/}" || return 1
        done
    fi

    return 0
}

# DOWNLOAD_FILE "<url>" "<output path>"
# Downloads the file from the provided URL and stores it in the desidered output path.
DOWNLOAD_FILE()
{
    _CHECK_NON_EMPTY_PARAM "URL" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "OUTPUT" "$2" || return 1

    local URL="$1"
    local OUTPUT="$2"

    mkdir -p "$(dirname "$OUTPUT")"
    curl -L -# -o "$OUTPUT" "$URL"
    return $?
}

# EVAL <cmd>
# Executes the provided command and prints its output if it returns a non-zero exit code.
EVAL()
{
    _CHECK_NON_EMPTY_PARAM "CMD" "$1" || return 1

    local CMD="$1"

    local OUT
    OUT="$(eval "$CMD" 2>&1)"
    # shellcheck disable=SC2181,SC2291
    if [ $? -ne 0 ]; then
        LOGE "Command returned a non-zero exit code\n"
        echo -e    '\033[0;31m'"$CMD"'\033[0m\n' >&2
        echo -n -e '\033[0;33m' >&2
        echo -n    "$OUT" >&2
        echo -e    '\033[0m' >&2
        return 1
    fi

    return 0
}

# GET_PROP "<partition>/<file>" "<prop>"
# Returns the supplied prop value, partition/file can be omitted.
GET_PROP()
{
    local FILES
    if [[ "$1" == *".prop" ]]; then
        FILES="$1"
        shift
    else
        FILES="$(_GET_PROP_FILES_PATH "$1")"
        if IS_VALID_PARTITION_NAME "$1"; then
            shift
        fi
    fi

    _CHECK_NON_EMPTY_PARAM "PROP" "$1" || return 1

    local PROP="$1"
    # shellcheck disable=SC2086
    cat $FILES 2> /dev/null | sed -n "s/^$PROP=//p" | head -n 1
}

# IS_SPARSE_IMAGE <file>
# Returns whether or not the supplied file is a valid sparse image.
IS_SPARSE_IMAGE()
{
    _CHECK_NON_EMPTY_PARAM "FILE" "$1" || exit 1

    local FILE="$1"

    if [ ! -f "$FILE" ]; then
        LOGE "File not found: ${FILE//$SRC_DIR\//}"
        return 1
    fi

    # https://android.googlesource.com/platform/system/core/+/refs/tags/android-15.0.0_r1/libsparse/sparse_format.h#39
    [[ "$(READ_BYTES_AT "$FILE" "0" "4")" == "ed26ff3a" ]]
}

# IS_VALID_PARTITION_NAME <partition>
# Returns whether or not the supplied partition name is valid.
IS_VALID_PARTITION_NAME()
{
    local PARTITION="$1"
    # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/common.py#131
    [[ "$PARTITION" == "system" ]] || [[ "$PARTITION" == "vendor" ]] || [[ "$PARTITION" == "product" ]] || \
        [[ "$PARTITION" == "system_ext" ]] || [[ "$PARTITION" == "odm" ]] || [[ "$PARTITION" == "vendor_dlkm" ]] || \
        [[ "$PARTITION" == "odm_dlkm" ]] || [[ "$PARTITION" == "system_dlkm" ]]
}

# READ_BYTES_AT <file> <offset> <bytes>
# Reads the desidered amount of bytes from the supplied file.
READ_BYTES_AT()
{
    _CHECK_NON_EMPTY_PARAM "FILE" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "OFFSET" "$2" || return 1
    _CHECK_NON_EMPTY_PARAM "BYTES" "$3" || return 1

    local FILE="$1"
    local OFFSET="$2"
    local BYTES="$3"

    if [ ! -f "$FILE" ]; then
        LOGE "File not found: ${FILE//$SRC_DIR\//}"
        return 1
    fi

    local FILE_SIZE
    FILE_SIZE="$(wc -c "$FILE" | cut -d " " -f 1)"
    if ! [[ "$OFFSET" =~ ^[+-]?[0-9]+$ ]] || [[ "$OFFSET" -gt "$FILE_SIZE" ]]; then
        LOGE "Offset value not valid: $OFFSET"
        return 1
    fi
    if ! [[ "$BYTES" =~ ^[+-]?[0-9]+$ ]] || [[ "$BYTES" -gt "$((FILE_SIZE - OFFSET))" ]]; then
        LOGE "Bytes value not valid: $BYTES"
        return 1
    fi

    local READ
    local LENGTH
    READ="$(xxd -p -l "$BYTES" --skip "$OFFSET" "$FILE")"
    LENGTH="${#READ}"

    while [[ "$LENGTH" -gt 0 ]]; do
        echo -n "${READ:$LENGTH-2:2}"
        LENGTH="$((LENGTH - 2))"
    done
    echo ""
}

# SET_METADATA <partition> <file/dir> <user> <group> <mode> <label>
# Adds the supplied file/directory entry attrs in fs_config/file_context.
# Optional seventh argument: explicit capabilities mask. S10 refuses implicit
# removal of an existing nonzero capability; callers must choose a replacement.
SET_METADATA()
{
    _CHECK_NON_EMPTY_PARAM "PARTITION" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "ENTRY" "$2" || return 1
    _CHECK_NON_EMPTY_PARAM "USER" "$3" || return 1
    _CHECK_NON_EMPTY_PARAM "GROUP" "$4" || return 1
    _CHECK_NON_EMPTY_PARAM "MODE" "$5" || return 1
    _CHECK_NON_EMPTY_PARAM "LABEL" "$6" || return 1

    local PARTITION="$1"
    local ENTRY="$2"
    local USER="$3"
    local GROUP="$4"
    local MODE="$5"
    local LABEL="$6"
    local CAPABILITIES="${7:-0x0}"
    if [[ ! "$CAPABILITIES" =~ ^0x[0-9a-fA-F]{1,16}$ ]]; then
        LOGE "Invalid explicit capability mask: $CAPABILITIES"
        return 1
    fi

    if [[ ! "$USER" =~ ^[0-9]{1,10}$ || ! "$GROUP" =~ ^[0-9]{1,10}$ ||
          ! "$MODE" =~ ^[0-7]{1,4}$ ||
          ! "$LABEL" =~ ^[A-Za-z0-9_]+:[A-Za-z0-9_]+:[A-Za-z0-9_]+:[A-Za-z0-9_:,.-]+$ ]]; then
        LOGE "Invalid explicit metadata fields"
        return 1
    fi
    if (( 10#$USER > 4294967295 || 10#$GROUP > 4294967295 )); then
        LOGE "Metadata uid/gid outside 32-bit range"
        return 1
    fi

    if ! IS_VALID_PARTITION_NAME "$PARTITION"; then
        LOGE "\"$PARTITION\" is not a valid partition name"
        return 1
    fi

    while [[ "${ENTRY:0:1}" == "/" ]]; do
        ENTRY="${ENTRY:1}"
    done

    [ "$PARTITION" != "system" ] && [[ "$ENTRY" != "$PARTITION/"* ]] && ENTRY="$PARTITION/$ENTRY"

    if [[ "$TARGET_CODENAME" == "beyond1lte" ]]; then
        local OLD_CAP
        OLD_CAP=$(awk 'BEGIN { key=ARGV[1]; ARGV[1]="" }
            $1 == key {
                count++
                if (NF != 5 || $5 !~ /^capabilities=0x[0-9a-fA-F]+$/) invalid=1
                value=$5; sub(/^capabilities=/,"",value)
            }
            END { if (count>1 || invalid) exit 1; if (count==1) print value }' \
            "$ENTRY" "$WORK_DIR/configs/fs_config-$PARTITION") || return 1
        if [[ -z "${7:-}" && -n "$OLD_CAP" && ! "$OLD_CAP" =~ ^0x0+$ ]]; then
            LOGE "SET_METADATA requires an explicit capability mask for /$ENTRY (existing $OLD_CAP)"
            return 1
        fi
    fi

    LOG "- Adding metadata for /$ENTRY (uid:$USER gid:$GROUP mode:$MODE selabel:$LABEL)"

    local CONTEXT_KEY
    CONTEXT_KEY="/$(_HANDLE_SPECIAL_CHARS "$ENTRY")"
    # A typed rule is not equivalent to a universal replacement label.
    awk 'BEGIN { key=ARGV[1]; ARGV[1]="" }
        $1==key { count++; if (NF!=2) invalid=1 }
        END { if (invalid || count>1) exit 1 }' "$CONTEXT_KEY" \
        "$WORK_DIR/configs/file_context-$PARTITION" || return 1
    _REMOVE_METADATA_KEY "$WORK_DIR/configs/fs_config-$PARTITION" "$ENTRY" || return 1
    _REMOVE_METADATA_KEY "$WORK_DIR/configs/file_context-$PARTITION" "$CONTEXT_KEY" || return 1
    echo "$ENTRY $USER $GROUP $MODE capabilities=$CAPABILITIES" >> "$WORK_DIR/configs/fs_config-$PARTITION" || return 1
    echo "$CONTEXT_KEY $LABEL" >> "$WORK_DIR/configs/file_context-$PARTITION" || return 1

    return 0
}

# SET_PROP "<partition>" "<prop>" "<value>"
# Sets the supplied prop to the desidered value, partition name CANNOT be omitted.
# "-d" or "--delete" can be passed as value to delete the prop.
SET_PROP()
{
    _CHECK_NON_EMPTY_PARAM "PARTITION" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "PROP" "$2" || return 1

    local PARTITION="$1"
    local PROP="$2"
    local VALUE="$3"

    if ! IS_VALID_PARTITION_NAME "$PARTITION"; then
        LOGE "\"$PARTITION\" is not a valid partition name"
        return 1
    fi

    if [ "$(GET_PROP "$PARTITION" "$PROP")" ]; then
        local FILES
        FILES="$(_GET_PROP_LOCATION "$PARTITION" "$PROP")"

        while IFS= read -r f; do
            if [[ "$VALUE" == "-d" ]] || [[ "$VALUE" == "--delete" ]]; then
                LOG "- Deleting \"$PROP\" prop in ${f//$WORK_DIR/}"
                sed -i "/^$PROP/d" "$f"
            else
                LOG "- Replacing \"$PROP\" prop with \"$VALUE\" in ${f//$WORK_DIR/}"

                local LINES
                LINES="$(sed -n "/^${PROP}\b/=" "$f")"
                for l in $LINES; do
                    sed -i "$l c${PROP}=${VALUE}" "$f"
                done
            fi
        done <<< "$FILES"
    elif [[ "$VALUE" != "-d" ]] && [[ "$VALUE" != "--delete" ]]; then
        local FILE

        case "$PARTITION" in
            "system")
                FILE="$WORK_DIR/system/system/build.prop"
                ;;
            "system_ext")
                if $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION; then
                    FILE="$WORK_DIR/system_ext/etc/build.prop"
                else
                    FILE="$WORK_DIR/system/system/system_ext/etc/build.prop"
                fi
                ;;
            "system_dlkm")
                FILE="$WORK_DIR/system_dlkm/etc/build.prop"
                ;;
            "vendor")
                FILE="$WORK_DIR/vendor/build.prop"
                ;;
            "vendor_dlkm")
                FILE="$WORK_DIR/vendor_dlkm/etc/build.prop"
                ;;
            "odm_dlkm")
                FILE="$WORK_DIR/vendor/odm_dlkm/etc/build.prop"
                ;;
            "odm")
                FILE="$WORK_DIR/odm/etc/build.prop"
                ;;
            "product")
                FILE="$WORK_DIR/product/etc/build.prop"
                ;;
        esac

        if [ ! -f "$FILE" ]; then
            LOGW "File not found: ${FILE//$WORK_DIR/}"
            return 0
        fi

        LOG "- Adding \"$PROP\" prop with \"$VALUE\" in ${FILE//$WORK_DIR/}"
        if ! grep -q "Added by scripts" "$FILE"; then
            echo "# Added by scripts/utils/module_utils.sh" >> "$FILE"
        fi
        echo "$PROP=$VALUE" >> "$FILE"
    fi

    return 0
}
