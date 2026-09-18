LOG_STEP_IN "- Updating Vendor HALs"
BLOBS_LIST="
bin/hw/vendor.samsung.hardware.vibrator@2.2-service
bin/hw/vendor.samsung.hardware.sysinput@1.2-service
bin/hw/vendor.samsung.hardware.snap@1.2-service
etc/audio_policy_configuration_sec.xml
etc/init/vendor.samsung.hardware.sysinput@1.2-service.rc
etc/init/vendor.samsung.hardware.vibrator@2.2-service.rc
lib/hw/android.hardware.graphics.mapper@2.0-impl.so
lib/hw/vendor.samsung.hardware.snap@1.2-impl.so
lib/vendor.samsung.hardware.snap@1.0.so
lib/vendor.samsung.hardware.snap@1.1.so
lib/vendor.samsung.hardware.snap@1.2.so
lib64/vendor.samsung.hardware.snap@1.0.so
lib64/vendor.samsung.hardware.snap@1.1.so
lib64/vendor.samsung.hardware.snap@1.2.so
lib64/vendor.samsung.hardware.vibrator@2.0.so
lib64/vendor.samsung.hardware.vibrator@2.1.so
lib64/vendor.samsung.hardware.vibrator@2.2.so
lib64/hw/android.hardware.graphics.mapper@2.0-impl.so
lib64/hw/vendor.samsung.hardware.snap@1.2-impl.so
"
for blob in $BLOBS_LIST
do
    DELETE_FROM_WORK_DIR "vendor" "$blob"
done
LOG_STEP_OUT

LOG_STEP_IN "- Removing RenderScript"
BLOBS_LIST="
bin/bcc_mali
lib/libmalicore.bc
lib/libclcore.bc
lib/libclcore_neon.bc
lib/libRSDriverArm.so
lib64/libLLVM_android_mali.so
lib64/libbcc_mali.so
lib64/libbccArm.so
lib64/libclcore.bc
lib64/libmalicore.bc
lib64/libRSDriverArm.so
"
for blob in $BLOBS_LIST
do
    DELETE_FROM_WORK_DIR "vendor" "$blob"
done
LOG_STEP_OUT

LOG "- Fixing SNAP AIDL SELinux rule"
SNAP_POLICY="$WORK_DIR/vendor/etc/selinux/vendor_sepolicy.cil"
SNAP_OLD="(allow snap_hidl hal_snap_service (service_manager (find)))"
SNAP_NEW="(allow snap_hidl hal_snap_service (service_manager (add find)))"
if ! grep -q -F "$SNAP_NEW" "$SNAP_POLICY"; then
    if ! grep -q -F "$SNAP_OLD" "$SNAP_POLICY"; then
        ABORT "SNAP policy does not match the Exynos 9820 reference"
        return 1
    fi
    sed -i "s/$SNAP_OLD/$SNAP_NEW/g" "$SNAP_POLICY"
fi
unset SNAP_POLICY SNAP_OLD SNAP_NEW

LOG "- Fixing JSQZ node permission"
if ! grep -q -E '^/dev/jsqz[[:space:]]+0660[[:space:]]+mediacodec[[:space:]]+camera$' "$WORK_DIR/vendor/ueventd.rc"; then
    if grep -q -E '^/dev/jsqz[[:space:]]' "$WORK_DIR/vendor/ueventd.rc"; then
        ABORT "Unexpected existing /dev/jsqz permissions"
        return 1
    fi
    echo "/dev/jsqz                 0660   mediacodec     camera" >> "$WORK_DIR/vendor/ueventd.rc"
fi

LOG "- Adding missing plat_pub_versioned.cil compat attributes for GZD7 system_ext"
# GZD7's system_ext/etc/selinux/mapping/31.0.cil (real init input, confirmed via
# external/android-tools/vendor/core/init/selinux.cpp's OpenSplitPolicy) declares
# perf_prop_31_0/qb_id_prop_31_0 memberships (typeattributeset ... (perf_prop))
# for two system_ext-owned properties (ro.system.qb.id and a perf-related prop)
# that did not exist yet when this G973F plat_pub_versioned.cil snapshot was
# built, so it never declared the corresponding (typeattribute X_31_0)/
# (roletype object_r X_31_0) pair -- these two are the actual missing pieces
# (secilc fails to resolve the real init CIL input set without them: "Failed
# to resolve expandtypeattribute statement ... mapping/31.0.cil"). The base
# `(type perf_prop)`/`(type qb_id_prop)` declarations are NOT added here --
# both already exist in system_ext_sepolicy.cil (and mapping/31.0.cil already
# declares `(type perf_prop)` itself), so re-declaring them here would be a
# redundant duplicate rather than a required fix.
#
# grep of vendor_sepolicy.cil found no targeted `allow`/similar rule naming
# either _31_0 attribute specifically (only generic domain/file_type bulk-list
# membership references perf_prop/qb_id_prop by their base, non-_31_0 names).
# That is evidence the gap is compile-time-only for this build, not proof: it
# does not rule out effects mediated indirectly through that bulk membership,
# and has not been checked against real property_contexts/init behavior on
# real hardware.
PLAT_PUB="$WORK_DIR/vendor/etc/selinux/plat_pub_versioned.cil"
if ! grep -q -F "(typeattribute perf_prop_31_0)" "$PLAT_PUB"; then
    if grep -q -F "perf_prop_31_0" "$PLAT_PUB" || grep -q -F "qb_id_prop_31_0" "$PLAT_PUB"; then
        ABORT "plat_pub_versioned.cil already has unexpected perf_prop_31_0/qb_id_prop_31_0 content"
        return 1
    fi
    cat >> "$PLAT_PUB" << 'CIL_EOF'
(typeattribute perf_prop_31_0)
(roletype object_r perf_prop_31_0)
(typeattribute qb_id_prop_31_0)
(roletype object_r qb_id_prop_31_0)
CIL_EOF
fi
unset PLAT_PUB

LOG_STEP_IN "- Adding S21 (p3sxxx) Light HAL"
if [[ "$TARGET_CODENAME" == "beyond1lte" ]]; then
    python3 "$SRC_DIR/scripts/utils/s10_light_policy.py" pre \
        "$SRC_DIR/prebuilts/samsung/p3sxxx" "$WORK_DIR" || return 1
    # Explicit destination policy; capability=0 for new ADD entries. Existing
    # entries must already match the complete policy, including capability.
    ADD_TO_WORK_DIR "p3sxxx" "vendor" "bin/hw/vendor.samsung.hardware.light-service" \
        0 2000 755 "u:object_r:hal_light_default_exec:s0" || return 1
    ADD_TO_WORK_DIR "p3sxxx" "vendor" "lib64/android.hardware.light-V1-ndk_platform.so" \
        0 0 644 "u:object_r:vendor_file:s0" || return 1
    ADD_TO_WORK_DIR "p3sxxx" "vendor" "lib64/vendor.samsung.hardware.light-V1-ndk_platform.so" \
        0 0 644 "u:object_r:vendor_file:s0" || return 1
    python3 "$SRC_DIR/scripts/utils/s10_light_policy.py" post \
        "$SRC_DIR/prebuilts/samsung/p3sxxx" "$WORK_DIR" || return 1
else
    ADD_TO_WORK_DIR "p3sxxx" "vendor" "bin/hw/vendor.samsung.hardware.light-service"
    ADD_TO_WORK_DIR "p3sxxx" "vendor" "lib64/android.hardware.light-V1-ndk_platform.so"
    ADD_TO_WORK_DIR "p3sxxx" "vendor" "lib64/vendor.samsung.hardware.light-V1-ndk_platform.so"
fi
LOG_STEP_OUT
