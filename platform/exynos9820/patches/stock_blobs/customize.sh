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
    # (readelf -d / -Ws).
    #
    # 2026-09-19 correction (real-device retest after the fix above):
    # libMultiFrameProcessing10.camera.samsung.so still failed to dlopen,
    # now with a more specific error:
    #   dlopen failed: library "vendor.samsung_slsi.hardware.iva@1.0.so" not
    #   found: needed by /system/lib64/libMultiFrameProcessing10.camera.samsung.so
    #   in namespace clns-shared-12
    # `dumpsys package` confirmed the MFP libs themselves DO resolve as
    # usesLibraryFiles now, so the file-presence/public.libraries fix above
    # was necessary but not sufficient - the ORIGINAL note here ("resolves
    # from HWC1's vendor partition, sourced wholesale") was wrong: HWC1's
    # vendor/etc/public.libraries.txt does NOT list
    # vendor.samsung_slsi.hardware.iva@1.0.so or
    # vendor.samsung_slsi.hardware.MultiFrameProcessing20@1.0.so (checked
    # directly - it only exposes 5 unrelated camera libs to the sphal
    # namespace), so an app process's linker namespace can never see the
    # vendor/lib(64) copies no matter how the vendor partition is sourced.
    # HWC1 avoids this entirely on real hardware by *also* shipping both
    # HIDL client stub libraries directly on system/lib(64) (confirmed via
    # out/fw/SM-G973F_AUT/fs_config-system and irremovable_list.txt) -
    # system-partition libraries are visible to app processes without the
    # vendor/sphal namespace bridge at all. GZD7 has neither file on its own
    # system partition (this Samsung-SLSI chip HAL is S10/exynos9820-era
    # only). Fix: add HWC1's own system-side copies of both HIDL client
    # stubs the same way as the MFP libs themselves, mirroring exactly how
    # real stock S10 firmware makes them available to its own Camera app.
    # Precedent for this exact "add target's own missing native camera lib"
    # pattern: UN1CA r8q target/r8q/patches/camera/customize.sh (adds
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
    for _MFP_DEP in "vendor.samsung_slsi.hardware.iva@1.0.so" "vendor.samsung_slsi.hardware.MultiFrameProcessing20@1.0.so"; do
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib/${_MFP_DEP}" 0 0 644 "u:object_r:system_lib_file:s0"
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/${_MFP_DEP}" 0 0 644 "u:object_r:system_lib_file:s0"
    done
    unset _MFP_DEP
    LOG_STEP_OUT

    # 2026-09-19: real-device logcat is full of repeated
    #   libprocessgroup: Failed to write 'N-7' to /dev/cpuset/cpus: Permission denied
    # Confirmed NOT a DAC/SELinux problem: /dev/cpuset/cpus is 0664
    # root:system with zero matching avc denials, and the root ("top")
    # cpuset's own cpus file is kernel-enforced read-only regardless of
    # mode bits (see Documentation/admin-guide/cgroup-v1/cpusets.rst).
    # GZD7-sourced system/etc/surfaceflinger.rc applies task_profiles
    # "GpisSfCpusetJoin" (system/etc/task_profiles.json: JoinCgroup cpuset
    # "sf"), and system_server's "SystemServiceCapacityHigh" profile does
    # JoinCgroup cpuset "foreground-boost". Both target directories are
    # created by GZD7's own SoC-specific vendor init
    # (vendor/etc/init/init.s5e9925.rc, "on init", "CPUSET(s5e9925)"
    # section) - a file that is never part of this ROM's build since vendor
    # = HWC1. HWC1's own vendor/etc/init/init.exynos9820.rc "CPUSET(9820)"
    # section was checked directly and confirms real stock S10 never had
    # this concept at all (only chown/chmod on the standard
    # top-app/foreground/background/system-background/restricted groups,
    # no "sf" or "foreground-boost" anywhere). Confirmed empirically
    # on-device (adb shell): /dev/cpuset/sf and /dev/cpuset/foreground-boost
    # do not exist; SurfaceFlinger and all 33 of its threads sit in the root
    # cgroup "/" because its JoinCgroup "sf" silently fails at boot; the
    # "GpisSfCpuset" Attribute (task_profiles.json) has no "Path", so
    # SetAttribute resolves the target file relative to the *calling task's
    # actual* cgroup - for a root-cgroup task that is exactly
    # /dev/cpuset/cpus, matching the observed failure precisely. This is
    # P2/non-blocking (screen recording, app switching, SystemUI all
    # confirmed normal with this warning present) but leaves GZD7's intended
    # GPIS SurfaceFlinger CPU-placement boost silently inert. Fix: recreate
    # both compatibility cpuset groups in HWC1's own init.exynos9820.rc,
    # mirroring GZD7's init.s5e9925.rc mkdir/copy/chown/chmod sequence
    # exactly, but with HWC1's own CPU masks instead of GZD7's
    # s5e9925-specific ones (which have no proven meaning on this SoC): "sf"
    # gets HWC1's own "foreground" mask (0-2,4-7 - the mask real S10
    # firmware engineers already chose for foreground-priority work on this
    # exact SoC), "foreground-boost" gets 0-7 (matches both GZD7's own
    # foreground-boost and HWC1's own top-app, uncontested on both sides).
    # Reviewed and approved by ChatGPT(웹), including this exact mask choice.
    # Scoped to beyond1lte: not verified for any other device sharing this
    # platform module.
    LOG_STEP_IN "- Restoring GZD7-expected 'sf'/'foreground-boost' cpuset groups in HWC1 (SM-G973F) vendor init (missing from stock S10, referenced by GZD7's task_profiles.json/surfaceflinger.rc)"
    _CPUSET_RC="$WORK_DIR/vendor/etc/init/init.exynos9820.rc"
    if [ ! -f "$_CPUSET_RC" ]; then
        LOGE "File not found: ${_CPUSET_RC//$WORK_DIR/}"
        return 1
    fi
    _CPUSET_BLOCK="$(
        {
            echo ""
            echo "# GZD7 compatibility cpusets (sf / foreground-boost) -- see target/beyond1lte/README.md"
            echo "on init"
            echo "    mkdir /dev/cpuset/sf"
            echo "    copy /dev/cpuset/cpus /dev/cpuset/sf/cpus"
            echo "    copy /dev/cpuset/mems /dev/cpuset/sf/mems"
            echo "    chown system system /dev/cpuset/sf/tasks"
            echo "    chown system system /dev/cpuset/sf/cgroup.procs"
            echo "    chown system system /dev/cpuset/sf/cpus"
            echo "    chmod 0664 /dev/cpuset/sf/cpus"
            echo "    write /dev/cpuset/sf/cpus 0-2,4-7"
            echo ""
            echo "    mkdir /dev/cpuset/foreground-boost"
            echo "    copy /dev/cpuset/cpus /dev/cpuset/foreground-boost/cpus"
            echo "    copy /dev/cpuset/mems /dev/cpuset/foreground-boost/mems"
            echo "    chown system system /dev/cpuset/foreground-boost"
            echo "    chown system system /dev/cpuset/foreground-boost/tasks"
            echo "    chown system system /dev/cpuset/foreground-boost/cgroup.procs"
            echo "    chown system system /dev/cpuset/foreground-boost/cpus"
            echo "    chmod 0664 /dev/cpuset/foreground-boost/tasks"
            echo "    chmod 0664 /dev/cpuset/foreground-boost/cgroup.procs"
            echo "    chmod 0664 /dev/cpuset/foreground-boost/cpus"
            echo "    write /dev/cpuset/foreground-boost/cpus 0-7"
        }
    )"
    if grep -qE '^[[:space:]]*mkdir /dev/cpuset/(sf|foreground-boost)([[:space:]]|$)' "$_CPUSET_RC"; then
        # A previous/partial patch must not silently suppress either group.
        while IFS= read -r _CPUSET_LINE; do
            [[ "$_CPUSET_LINE" == "    "* ]] || continue
            if ! grep -qxF "$_CPUSET_LINE" "$_CPUSET_RC"; then
                LOGE "Incomplete compatibility cpuset configuration: $_CPUSET_LINE"
                return 1
            fi
        done <<< "$_CPUSET_BLOCK"
    else
        printf '%s\n' "$_CPUSET_BLOCK" >> "$_CPUSET_RC"
    fi
    unset _CPUSET_RC _CPUSET_BLOCK _CPUSET_LINE
    LOG_STEP_OUT

    # 2026-09-19: real-device logcat showed Bluetooth A2DP media audio
    # (music/video) completely silent while connected to a normal A2DP
    # earphone (EDIFIER X1, SBC codec) - connect/disconnect tones worked,
    # actual media playback did not, and stayed silent until BT was
    # disconnected. Root-caused with ChatGPT(웹) via a live A/B test on this
    # exact device (Developer Options > "Disable A2DP hardware offload" ON,
    # no rebuild needed to test): with hardware offload forced off, the same
    # earphone/track played normally, and the failure signature below
    # disappeared entirely.
    #
    # Full chain: com.android.bluetooth (GZD7-sourced, Android 16 Bluetooth
    # stack) negotiates SBC with the earphone and the Bluetooth Audio HAL
    # correctly starts the *software* A2DP datapath for it
    # (A2DP_SOFTWARE_ENCODING_DATAPATH, StartSession SUCCESS) - but
    # A2dpServiceHelper still calls setOffloadModeNative(1) right after,
    # forcing Samsung's Exynos hardware-offload path on top of a codec its
    # own logging admits doesn't support offload ("IsCodecOffloadingEnabled:
    # software codec={SBC...}" immediately followed by "support offload =
    # false, offload running = true"). AudioPolicy then reconfigures the A2DP
    # device and routes deep_buffer output through HWC1's
    # audio_hw_proxy_9820 HAL for the (now-mismatched) hardware-offload
    # path, where PCM prepare fails every single time:
    #   audio_hw_proxy_9820: deep_out-proxy_write_playback_buffer: failed to
    #   write to PCM Device with cannot prepare channel: Invalid argument
    # (9200+ consecutive failures observed over ~3 minutes of attempted
    # playback) - the media app's MediaSession stays in PLAYING state the
    # whole time since nothing above the HAL ever sees an error, it is a
    # pure silent HAL-level failure. This is a generation mismatch between
    # GZD7's newer Bluetooth stack's offload decision logic and HWC1's older
    # Exynos9820 hardware-offload HAL implementation, not a missing blob or
    # codec negotiation failure (SBC negotiates correctly; the vendor A2DP
    # offload HIDL service itself starts fine when actually asked to).
    #
    # Existing /data settings can override this default. A data-preserving
    # update needed the developer-option toggle to be enabled again (§32.8).
    # Fresh-install automatic application has not been independently tested.
    # Fix: default persist.bluetooth.a2dp_offload.disabled=true so this
    # device defaults to the software A2DP path (SBC tested with EDIFIER X1;
    # AAC/LDAC are not validated by that test), instead of Samsung's hardware-offload
    # path that HWC1's HAL can't actually complete for this donor
    # combination. This is the safer of the two options ChatGPT(웹)
    # presented (vs. a targeted A2dpServiceHelper patch to skip
    # setOffloadModeNative() when the negotiated codec doesn't support
    # offload) - it trades potential power-efficiency loss from software
    # encoding for guaranteed-working A2DP audio. Scoped to beyond1lte: not
    # verified for any other device sharing this platform module.
    SET_PROP "system" "persist.bluetooth.a2dp_offload.disabled" "true"
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
