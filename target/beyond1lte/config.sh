#
# Copyright (C) 2024 BlackMesa123
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Device configuration file for Galaxy S10 (Exynos) (beyond1lte)
TARGET_NAME="Galaxy S10 (Exynos)"
TARGET_CODENAME="beyond1lte"
TARGET_ASSERT_MODEL=("SM-G973F" "SM-G973N")
TARGET_PLATFORM="exynos9820"
# Offline cache key, not a FUS download string; never invent an IMEI/SN.
TARGET_FIRMWARE="SM-G973F/AUT"
TARGET_FIRMWARE_OFFLINE=true
TARGET_EXTRA_FIRMWARES=()
# source: user-built fixed commit; artisan311: exact observed prebuilt image set.
TARGET_KERNEL_INPUT_KIND="source"
TARGET_PLATFORM_SDK_VERSION=31
TARGET_PRODUCT_SHIPPING_API_LEVEL=28
# Reference TARGET_VNDK_VERSION=31; not an observed ro.board.api_level.
TARGET_LEGACY_VNDK_VERSION=31
TARGET_OS_SINGLE_SYSTEM_IMAGE="essi"
# OS partitions use the observed S10 EROFS format; /data remains F2FS.
TARGET_OS_FILE_SYSTEM_TYPE="erofs"
TARGET_SUPER_PARTITION_SIZE=0
# Explicitly selected for this user's measured, repartitioned device only.
# Size generation does not approve auxiliary preservation or installation.
TARGET_LAYOUT_PROFILE="user-repartition-20260913"
TARGET_SUPER_GROUP_NAME="none"
TARGET_NONE_SIZE=0
TARGET_OS_BUILD_SYSTEM_EXT_PARTITION=false

# SEC Product Feature
TARGET_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS="4"
TARGET_DVFSAPP_CONFIG_DVFS_POLICY_FILENAME="dvfs_policy_makalu_xx"
TARGET_FINGERPRINT_CONFIG_SENSOR="google_touch_display_ultrasonic"
TARGET_CAMERA_SUPPORT_MASS_APP_FLAVOR=false
# Observed effective SystemUI resource on the user's running S10 3.1.1 (user 0).
# Retain this target behavior; new GZD7 base/RRO resource result remains untested.
# See target/beyond1lte/README.md
TARGET_CAMERA_SUPPORT_CUTOUT_PROTECTION=false
TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL=true
TARGET_LCD_CONFIG_HFR_MODE="0"
TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE="60"
TARGET_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE="60"
TARGET_LCD_CONFIG_SEAMLESS_BRT="none"
TARGET_LCD_CONFIG_SEAMLESS_LUX="none"
TARGET_COMMON_SUPPORT_EMBEDDED_SIM=false
TARGET_LCD_SUPPORT_MDNIE_HW=true
TARGET_COMMON_CONFIG_MDNIE_MODE="65303"
TARGET_LCD_CONFIG_COLOR_WEAKNESS_SOLUTION="3"
TARGET_WLAN_SUPPORT_MOBILEAP_DUALAP=false
TARGET_WLAN_SUPPORT_MOBILEAP_6G=false
TARGET_WLAN_SUPPORT_MOBILEAP_OWE=false
TARGET_AUDIO_SUPPORT_ACH_RINGTONE=false
# Also confirmed in the user-tested ArtisanROM 3.1.1 floating_feature.xml.
TARGET_AUDIO_SUPPORT_DUAL_SPEAKER=true
TARGET_AUDIO_SUPPORT_VIRTUAL_VIBRATION_SOUND=false

# Reference gen_config_file.sh defaults to this path; current builder defaults differ.
TARGET_OS_BOOT_DEVICE_PATH="/dev/block/by-name"
# From target/beyond1lte/sff.sh (not another device's policy).
TARGET_DVFSAPP_CONFIG_SSRM_POLICY_FILENAME="siop_beyond1_exynos9820"
# Reference platform debloat removes CameraX and SCameraSDKService.
TARGET_CAMERA_SUPPORT_CAMERAX_EXTENSION=false
TARGET_CAMERA_SUPPORT_SDK_SERVICE=false

# Experimental source port: feature policy selection is complete; input, patch
# and installation validation remain incomplete. See target/beyond1lte/README.md
# VNDK 31 is NOT evidence for ro.board.api_level=31.

# Retain observed HWC1 / working S10 3.1.1 code behavior.
# Source GZD7 patch applicability is a separate, unfinished check.
# Full method excerpts and hashes: target/beyond1lte/README.md
TARGET_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE=true
TARGET_BLUETOOTH_SUPPORT_A2DP_SBM=false
TARGET_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF=false
TARGET_BLUETOOTH_SUPPORT_XLNA_CONTROL=false
TARGET_RIL_SIM_CONFIG_MULTISIM_TRAYCOUNT=1
TARGET_RIL_SUPPORT_WATERPROOF_SIM_TRAY_MSG=true
TARGET_WLAN_SUPPORT_80211AX_6GHZ=false
TARGET_WLAN_SUPPORT_MBO=true
TARGET_WLAN_SUPPORT_MIMO=true
TARGET_WLAN_SUPPORT_WIFI_TO_CELLULAR=true

# Preserve decoded S10 3.1.1 framework policy; see gzd7-followup.md.
# 80211ax/TWT/lowlatency false removes forced defaults, not runtime capabilities.
TARGET_WLAN_CONFIG_CONNECTION_PERSONALIZATION=1
TARGET_WLAN_CONFIG_CPU_CSTATE_DISABLE_THRESHOLD=0
TARGET_WLAN_CONFIG_DATA_ACTIVITY_AFFINITY_BOOSTER_THRESHOLD=0
TARGET_WLAN_CONFIG_DYNAMIC_SWITCH=8
TARGET_WLAN_CONFIG_L1SS_DISABLE_THRESHOLD=0
TARGET_WLAN_SUPPORT_80211AX=false
TARGET_WLAN_SUPPORT_APE_SERVICE=true
TARGET_WLAN_SUPPORT_LOWLATENCY=false
TARGET_WLAN_SUPPORT_MOBILEAP_POWER_SAVEMODE=true
TARGET_WLAN_SUPPORT_MOBILEAP_PRIORITIZE_TRAFFIC=true
TARGET_WLAN_SUPPORT_MOBILEAP_WIFISHARING_LITE=false
TARGET_WLAN_SUPPORT_MOBILEAP_WIFI_CONCURRENCY=true
TARGET_WLAN_SUPPORT_SWITCH_FOR_INDIVIDUAL_APPS=true
TARGET_WLAN_SUPPORT_TWT_CONTROL=false

# Select reporting policy explicitly; a boolean cannot reproduce all three cases.
# gzd7_driver_country | country_fallback | s10_311_legacy_report
# User selected legacy true reporting; retain GZD7 access permission enforcement.
TARGET_WLAN_MOBILEAP_5G_COUNTRY_POLICY=s10_311_legacy_report
