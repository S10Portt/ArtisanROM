#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""User-run HWC1 image preparation. Never run during source-only review.

Reads the pinned local ZIP, streams selected AP/BL/CSC members into a NEW
directory, decompresses LZ4, and optionally unsparses with an existing tool.
No downloads, updates, mounting, repair, file-tree extraction or cleanup.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import struct
import subprocess
import tarfile
import tempfile
import zipfile

EXPECTED_ZIP = "84a96e2d7d372dfb7786e1d99470398d5a8172dceae78920738b32daad208c3b"
PACKAGES = {
    "AP_G973FXXSGHWC1_CL25257816_QB62768582_REV01_user_low_ship_meta_OS12.tar.md5",
    "BL_G973FXXSGHWC1_CL25257816_QB62768582_REV01_user_low_ship.tar.md5",
    "CSC_OXM_G973FOXMGHWA3_CL25257816_QB61057831_REV01_user_low_ship.tar.md5",
}
SELECTED = {
    "system", "vendor", "product", "system_ext", "odm", "vendor_dlkm",
    "odm_dlkm", "system_dlkm", "prism", "optics", "vbmeta", "vbmeta_system",
    "vbmeta_vendor", "boot", "recovery", "dt", "dtb", "dtbo",
}
REQUIRED = {"system", "vendor", "product", "vbmeta"}


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def tool(path):
    found = shutil.which(path)
    if found is None:
        raise ValueError(f"Required existing tool not found: {path}")
    resolved = Path(found).resolve(strict=True)
    if not resolved.is_file() or not os.access(resolved, os.X_OK):
        raise ValueError(f"Not an executable file: {resolved}")
    return resolved


def image_name(member):
    # Never use archive paths as output paths or extract links/special nodes.
    path = PurePosixPath(member.name)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Unsupported archive path: {member.name}")
    name = path.name
    if name.endswith(".lz4"):
        name = name[:-4]
    if name.endswith(".img.ext4"):
        name = name[:-5]
    if not name.endswith(".img") or name[:-4] not in SELECTED:
        return None
    if not member.isfile():
        raise ValueError(f"Selected image is not a regular file: {member.name}")
    return name[:-4]


def identify(path):
    with path.open("rb") as stream:
        header = stream.read(4096)
    if header[1024:1028] == b"\x10\x20\xf5\xf2":
        return "f2fs"
    if header[1024:1028] == b"\xe2\xe1\xf5\xe0":
        return "erofs"
    if header[1080:1082] == b"\x53\xef":
        return "ext-family (confirm with file before mounting)"
    if header[:4] == b"AVB0":
        return "vbmeta"
    if header[:8] == b"ANDROID!":
        return "android-boot"
    return "unclassified; original bytes retained"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zip", type=Path)
    parser.add_argument("--output-parent", type=Path, required=True)
    parser.add_argument("--simg2img", required=True,
                        help="explicit path to an existing executable; never built or installed")
    args = parser.parse_args()
    if args.zip.is_symlink() or not args.zip.is_file():
        raise ValueError("ZIP must be a regular non-symlink file")
    source = args.zip.resolve(strict=True)
    parent = args.output_parent.resolve(strict=True)
    if not parent.is_dir():
        raise ValueError("Output parent must already exist")
    lz4, simg2img = tool("lz4"), tool(args.simg2img)
    print("Checking HWC1 ZIP fingerprint...", flush=True)
    if digest(source) != EXPECTED_ZIP:
        raise ValueError("ZIP differs from the recorded local HWC1 package; refusing input")
    out = Path(tempfile.mkdtemp(prefix="hwc1-images.", dir=parent))
    print(f"Output directory: {out}", flush=True)
    manifest = {
        "scope": "Local pinned ZIP extraction; not Samsung authentication, TAR MD5 verification, AVB verification or builder input approval",
        "zip": str(source), "zip_sha256": EXPECTED_ZIP,
        "tools": {str(p): digest(p) for p in (lz4, simg2img)},
        "script_sha256": digest(Path(__file__).resolve()),
        "images": [], "complete": False,
    }
    seen = {}

    def save():
        (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    save()
    try:
        with zipfile.ZipFile(source) as archive:
            infos = archive.infolist()
            for package in sorted(PACKAGES):
                matches = [entry for entry in infos if entry.filename == package]
                if len(matches) != 1:
                    raise ValueError(f"Expected exactly one package: {package}")
                with archive.open(matches[0]) as zipped:
                    with tarfile.open(fileobj=zipped, mode="r|") as tar:
                        for member in tar:
                            name = image_name(member)
                            if name is None:
                                continue
                            if member.size <= 0:
                                raise ValueError(f"Empty selected image: {member.name}")
                            slot = out / f"{len(manifest['images']):02d}-{name}"
                            slot.mkdir()
                            packed = slot / ("original.img.lz4" if member.name.endswith(".lz4") else "original.img")
                            stream = tar.extractfile(member)
                            if stream is None:
                                raise ValueError(f"Could not read {member.name}")
                            with stream, packed.open("xb") as destination:
                                shutil.copyfileobj(stream, destination, 4 * 1024 * 1024)
                            if packed.stat().st_size != member.size:
                                raise ValueError(f"Truncated member: {member.name}")
                            expanded = packed
                            print(f"Preparing {package}: {member.name}", flush=True)
                            if member.name.endswith(".lz4"):
                                expanded = slot / "decompressed.img"
                                with expanded.open("xb") as destination, (slot / "lz4.log").open("xb") as log:
                                    subprocess.run([str(lz4), "-dc", str(packed)], stdout=destination, stderr=log, check=True)
                            with expanded.open("rb") as stream:
                                header = stream.read(28)
                            raw = expanded
                            sparse_size = None
                            if header[:4] == b"\x3a\xff\x26\xed":
                                if len(header) != 28:
                                    raise ValueError("Truncated sparse header")
                                magic, major, minor, fh, ch, block_size, blocks, chunks, crc = struct.unpack("<I4H4I", header)
                                if major != 1 or fh < 28 or ch < 12 or not block_size or block_size % 4 or not blocks:
                                    raise ValueError("Unsupported sparse header")
                                sparse_size = block_size * blocks
                                raw = slot / "raw.img"
                                with (slot / "simg2img.log").open("xb") as log:
                                    subprocess.run([str(simg2img), str(expanded), str(raw)], stdout=log, stderr=subprocess.STDOUT, check=True)
                                if raw.stat().st_size != sparse_size:
                                    raise ValueError("Unsparsed logical size mismatch")
                            if raw.stat().st_size == 0:
                                raise ValueError("Empty output image")
                            raw_hash = digest(raw)
                            record = {
                                "partition": name, "package": package, "member": member.name,
                                "packed_path": str(packed.relative_to(out)), "packed_sha256": digest(packed),
                                "raw_path": str(raw.relative_to(out)), "raw_bytes": raw.stat().st_size,
                                "raw_sha256": raw_hash, "sparse_logical_bytes": sparse_size,
                                "format": identify(raw),
                            }
                            manifest["images"].append(record)
                            save()
                            if name in seen and seen[name] != raw_hash:
                                raise ValueError(f"Conflicting copies of {name}; retained separately for review")
                            seen[name] = raw_hash
                    # Finish the ZIP member to check its CRC, including the TAR MD5 trailer.
                    while zipped.read(4 * 1024 * 1024):
                        pass
        missing = REQUIRED - seen.keys()
        if missing:
            raise ValueError(f"Required images absent: {sorted(missing)}")
        if digest(source) != EXPECTED_ZIP:
            raise ValueError("Input ZIP changed during preparation")
        manifest["complete"] = True
        save()
        print(f"Image preparation finished: {out / 'manifest.json'}", flush=True)
    except Exception as error:
        manifest["error"] = str(error)
        save()
        raise


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, EOFError, tarfile.TarError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        raise SystemExit(f"HWC1 preparation failed; retained output is incomplete: {error}")
