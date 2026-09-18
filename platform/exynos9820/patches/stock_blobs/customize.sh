# Selected from the reference stock_blobs module; see target/beyond1lte/README.md
# Hotword and 32-bit WFD replacements still need base-specific validation.
LOG_STEP_IN "- Replacing GameDriver"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/priv-app/GameDriver-EX9820/GameDriver-EX9820.apk" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/priv-app/DevGPUDriver-EX9820/DevGPUDriver-EX9820.apk" 0 0 644 "u:object_r:system_file:s0"
LOG_STEP_OUT

if [[ "$TARGET_CODENAME" == "beyond1lte" ]]; then
    # 2026-09-18: real-device tombstones (18/18 for this crash) confirmed
    # audioserver segfaulting in GZD7-sourced (system partition)
    # lib_SoundBooster_ver1100.so's Third_Harm_SetPar, fed HWC1-sourced
    # (vendor partition) SoundBoosterParam.bin/.txt -- a smaller/older-format
    # file (8568 bytes / 157 records vs GZD7's own 16240 bytes / 193 records
    # for the same file). GZD7's newer library does not understand HWC1's
    # older param layout. Fix: take HWC1's own matched SoundBooster libs
    # instead, so the library and the param file it parses come from the same
    # donor -- mirrors the r9s/exynos2100 and a71 precedent in UN1CA
    # (github.com/salvogiangri/UN1CA), which replaces ver1100 with the
    # target device's own version for the same reason. Scoped to beyond1lte:
    # not verified for any other device sharing this platform module.
    LOG_STEP_IN "- Replacing stock SoundBooster libs with the HWC1 (SM-G973F) donor's own matched version"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib/lib_SoundBooster_ver1000.so" 0 0 644 "u:object_r:system_lib_file:s0"
    DELETE_FROM_WORK_DIR "system" "system/lib/lib_SoundBooster_ver1100.so"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib/libsamsungSoundbooster_plus_legacy.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/lib_SoundBooster_ver1000.so" 0 0 644 "u:object_r:system_lib_file:s0"
    DELETE_FROM_WORK_DIR "system" "system/lib64/lib_SoundBooster_ver1100.so"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libsamsungSoundbooster_plus_legacy.so" 0 0 644 "u:object_r:system_lib_file:s0"
    LOG_STEP_OUT

    # 2026-09-19: real-device logcat shows the stock Camera app (sourced from
    # GZD7/S908B) crashing every time HIFI_LLS post-processing runs:
    #   V1/MpiHifiLlsWrapper: fail to load library(libMultiFrameProcessing10.camera.samsung.so),
    #   dlopen failed: library "libMultiFrameProcessing10.camera.samsung.so" not found
    #   -> FATAL EXCEPTION in PostProcessThread, InvalidOperationException: load
    #      nativeNode(id: 1700100) fail, process com.sec.android.app.camera killed
    # A second, independent crash 12s earlier in the same session (nativeNode
    # id: 1110100, NODE_MPI_V1_LLHDR) was confirmed via ARM64 disassembly of
    # SamsungCamera.apk's bundled lib/arm64-v8a/libnode-jni.so (capstone,
    # MpiLlHdrWrapper's constructor at file offset 0xb0d04) to be the exact
    # same failure mode one library generation up: it unconditionally
    # dlopen()s "libMultiFrameProcessing20.camera.samsung.so". The sibling
    # NODE_MPI_V1_MFHDR node (MpiMfHdrWrapper, constructor at 0xc22b8) was
    # confirmed the same way to target "libMultiFrameProcessing20Day.camera.samsung.so"
    # - not yet observed crashing on-device, but SEC_FLOATING_FEATURE_CAMERA_CONFIG_VENDOR_LIB_INFO
    # (target/beyond1lte/sff.sh) explicitly declares "mfhdr.mpi.v1" alongside
    # "llhdr.mpi.v1"/"hifills.mpi.v1", so this node is reachable and would
    # fail identically the first time a plain (non-low-light) HDR merge runs.
    # GZD7 (S908B, a newer flagship) never ships the 10/20/20Day generations
    # at all (confirmed: absent from its whole firmware tree, and also absent
    # from its system/etc/public.libraries-camera.samsung.txt) - it only
    # ships the newest 30 generation. But the app's compiled core2 framework
    # still contains these legacy fallback nodes, and at runtime (driven by
    # this device's real camera HW/HAL capabilities, which come from HWC1's
    # vendor blobs) it selects them. HWC1 (the real S10/G973F firmware) ships
    # all three (10/20/20Day) in both system/lib and system/lib64, and lists
    # all three in its own public.libraries-camera.samsung.txt, since the
    # real S10 camera generation needs them. ELF NEEDED closure and the
    # exported "construct" symbol were checked for every file added below
    # (readelf -d / -Ws) - all NEEDED entries resolve either from GZD7's own
    # system libs (libc/libc++/libutils/... - present in both donors) or from
    # HWC1's vendor partition (libhidlbase/libhidltransport/vendor.samsung_slsi.hardware.iva@1.0.so/
    # vendor.samsung_slsi.hardware.MultiFrameProcessing20@1.0.so - present in
    # HWC1 vendor/lib(64), which this ROM's vendor partition is sourced from
    # wholesale, along with the corresponding HIDL service binaries + init.rc
    # already present there unmodified). Same donor-mismatch shape as the
    # SoundBooster fix above. Precedent for this exact "add target's own
    # missing native camera lib" pattern: UN1CA r8q
    # target/r8q/patches/camera/customize.sh (adds
    # libSwIsp_core.camera.samsung.so the same way). Scoped to beyond1lte:
    # not verified for any other device sharing this platform module.
    LOG_STEP_IN "- Adding HWC1 (SM-G973F) donor's own libMultiFrameProcessing{10,20,20Day}.camera.samsung.so (missing from GZD7, crashes stock Camera app's HIFI_LLS/LLHDR/MFHDR nodes)"
    for _MFP_VER in 10 20 20Day; do
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib/libMultiFrameProcessing${_MFP_VER}.camera.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libMultiFrameProcessing${_MFP_VER}.camera.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
        if ! grep -qF "libMultiFrameProcessing${_MFP_VER}.camera.samsung.so" "$WORK_DIR/system/system/etc/public.libraries-camera.samsung.txt"; then
            EVAL "echo \"libMultiFrameProcessing${_MFP_VER}.camera.samsung.so\" >> \"$WORK_DIR/system/system/etc/public.libraries-camera.samsung.txt\""
        fi
    done
    unset _MFP_VER
    LOG_STEP_OUT
fi

LOG_STEP_IN "- Adding stock NFC Case features"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/permissions/com.sec.feature.cover.sview.xml" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/permissions/com.sec.feature.cover.xml" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/permissions/com.sec.feature.nfc_authentication_cover.xml" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/permissions/com.sec.feature.cover.clearcover.xml" 0 0 644 "u:object_r:system_file:s0"

if [[ "$TARGET_CODENAME" != "beyondx" ]]; then
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/permissions/com.sec.feature.cover.flip.xml" 0 0 644 "u:object_r:system_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/permissions/com.sec.feature.cover.ledbackcover.xml" 0 0 644 "u:object_r:system_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/permissions/com.sec.feature.cover.nfcledcover.xml" 0 0 644 "u:object_r:system_file:s0"
fi

ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/priv-app/LedBackCoverAppBeyond/LedBackCoverAppBeyond.apk" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/permissions/privapp-permissions-com.samsung.android.app.ledbackcover.xml" 0 0 644 "u:object_r:system_file:s0"
LOG_STEP_OUT

LOG_STEP_IN "- Adding stock cutout assets"
DECODE_APK "system_ext" "priv-app/SystemUI/SystemUI.apk"
cp -a "$MODPATH/assets/"* "$APKTOOL_DIR/system_ext/priv-app/SystemUI/SystemUI.apk/assets/"
LOG_STEP_OUT
