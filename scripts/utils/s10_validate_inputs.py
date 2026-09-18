# SPDX-License-Identifier: GPL-3.0-or-later
"""Stage-specific S10 structural checks. Never run during source-only review."""
from pathlib import Path
import os
import sys


def file(path):
    if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
        raise ValueError(f"missing, empty or unsupported input: {path}")
    with path.open("rb") as stream:
        stream.read(1)
    return path


def prop(path, key, nonempty=True):
    values = [line.split("=", 1)[1].strip() for line in file(path).read_text().splitlines()
              if "=" in line and line.split("=", 1)[0].strip() == key]
    if len(values) != 1 or (nonempty and not values[0]):
        raise ValueError(f"expected one {'nonempty ' if nonempty else ''}{key} in {path}")
    return values[0]


def partition(root, metadata, name):
    if not (root / name).is_dir() or (root / name).is_symlink():
        raise ValueError(f"missing or unsupported partition: {root / name}")
    file(metadata / f"fs_config-{name}")
    file(metadata / f"file_context-{name}")


def reject_host_links(root, firmware_root):
    """Reject observed dump rewrites without following Android absolute links."""
    if not root.is_dir() or root.is_symlink():
        raise ValueError(f"missing or linked partition root: {root}")
    host_prefix = str(firmware_root.resolve()) + "/"

    def fail(error):
        raise error

    for directory, dirs, files in os.walk(root, followlinks=False, onerror=fail):
        for name in dirs + files:
            path = Path(directory) / name
            if path.is_symlink():
                target = os.readlink(path)
                if target.startswith(("/home/", host_prefix)):
                    raise ValueError(f"host-rewritten Android symlink: {path} -> {target}")


def fw_path(root, spec):
    parts = spec.split("/")
    if len(parts) < 2 or any(not p or p in (".", "..") for p in parts[:2]):
        raise ValueError("invalid firmware cache key")
    return root / (parts[0] + "_" + parts[1])


def validate(stage, fw, source_spec, target_spec, work):
    if source_spec.split("/")[0] != "SM-S908B" or target_spec != "SM-G973F/AUT":
        raise ValueError("S10 stage check requires S908B source and G973F/AUT stock")
    source, target = fw_path(fw, source_spec), fw_path(fw, target_spec)
    if stage == "raw-links":
        for name in ("system", "vendor", "product", "odm", "odm_dlkm", "system_dlkm", "vendor_dlkm"):
            path = target / name
            if name in ("system", "vendor", "product") or path.exists() or path.is_symlink():
                reject_host_links(path, fw)
        return
    source_props = source / "system/system/build.prop"
    if prop(source_props, "ro.build.version.sdk") != "36":
        raise ValueError("unsupported source SDK")
    if prop(source_props, "ro.build.version.incremental") != "S908BXXSNGZD7":
        raise ValueError("S10 source requires the observed S908BXXSNGZD7 release")
    if stage == "source":
        for name in ("system", "product", "vendor", "odm"):
            reject_host_links(source / name, fw)
        for name in ("system", "product"):
            partition(source, source, name)
        if (source / "system_ext").is_dir():
            partition(source, source, "system_ext")
        elif not (source / "system/system/system_ext").is_dir():
            raise ValueError("missing source system_ext content")
        prop(source / "odm/etc/build.prop", "ro.product.odm.device")
        for key in ("ringtone", "notification_sound", "alarm_alert", "media_sound",
                    "ringtone_2", "notification_sound_2"):
            # An explicitly empty value is distinguishable from a failed read.
            prop(source / "vendor/build.prop", "ro.config." + key, nonempty=False)
    elif stage == "zip":
        # ZIP still reads these original identities; it no longer needs the
        # source-built kernel manifest or stock camera blobs just to package.
        for root in (source, target):
            for key in ("ro.system.build.fingerprint", "ro.build.product"):
                prop(root / "system/system/build.prop", key)
            prop(root / "vendor/build.prop", "ro.product.vendor.device")
        if prop(target / "vendor/build.prop", "ro.vendor.build.version.incremental") != "G973FXXSGHWC1":
            raise ValueError("ZIP target identity differs from HWC1")
        for name in ("system", "vendor", "product"):
            partition(work, work / "configs", name)
            reject_host_links(work / name, fw)
        for name in ("odm", "odm_dlkm", "system_dlkm", "vendor_dlkm", "system_ext"):
            if (work / name).exists() or (work / name).is_symlink():
                partition(work, work / "configs", name)
                reject_host_links(work / name, fw)
    else:
        raise ValueError("unsupported stage")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 6:
            raise ValueError("expected stage, firmware root, source, target and work root")
        validate(sys.argv[1], Path(sys.argv[2]), sys.argv[3], sys.argv[4], Path(sys.argv[5]))
    except (OSError, ValueError) as error:
        print(f"S10 stage input check failed: {error}", file=sys.stderr)
        sys.exit(1)
