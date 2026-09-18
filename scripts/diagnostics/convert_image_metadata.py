#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""User-run conversion of collected image metadata; do not run in static review.

Creates a NEW output directory only. Does not extract files, inspect host owners,
modify a firmware cache, run a builder, or certify a final work tree.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import struct
import tempfile


def encode_builder_context_path(path):
    # common_utils.sh searches the serialized key literally with grep -F.
    # Match _HANDLE_SPECIAL_CHARS, rather than Python's broader re.escape.
    if any(char in r"\^$?{}()|" for char in path):
        raise ValueError(f"unsupported builder context escaping: {path!r}")
    return "".join("\\" + char if char in ".+[]*" else char for char in path)


def read_file(root, name, nonempty=True):
    path = root / name
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"invalid evidence file: {path}")
    data = path.read_bytes()
    if nonempty and not data:
        raise ValueError(f"empty evidence file: {path}")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--partition", choices=("system", "vendor", "product", "odm", "system_ext", "vendor_dlkm", "odm_dlkm", "system_dlkm"), required=True)
    parser.add_argument("--output-parent", type=Path, required=True)
    args = parser.parse_args()
    root = args.evidence.resolve(strict=True)
    parent = args.output_parent.resolve(strict=True)
    if not root.is_dir() or not parent.is_dir():
        raise ValueError("evidence and output parent must be directories")
    read_file(root, "collection-complete.txt")
    for name in ("mount.log", "inodes.errors.txt", "xattrs.errors.txt", "build-props.errors.txt"):
        if read_file(root, name, nonempty=False):
            raise ValueError(f"collection has diagnostics requiring review: {name}")
    before = read_file(root, "image.before.sha256")
    if before != read_file(root, "image.after.sha256"):
        raise ValueError("image fingerprint records differ")
    if not re.match(rb"^[0-9a-f]{64}  .+\n$", before):
        raise ValueError("unsupported image fingerprint record")
    inode_data = read_file(root, "inodes.nul")
    fields = inode_data.split(b"\0")
    if fields.pop() != b"" or len(fields) % 6:
        raise ValueError("malformed NUL inode records")
    entries = {}
    for i in range(0, len(fields), 6):
        path, kind, uid, gid, mode, link = [v.decode("utf-8") for v in fields[i:i + 6]]
        if path in entries or kind not in ("d", "f", "l"):
            raise ValueError(f"duplicate path or unsupported file type: {path}")
        if path and (PurePosixPath(path).is_absolute() or ".." in PurePosixPath(path).parts or str(PurePosixPath(path)) != path):
            raise ValueError(f"noncanonical image path: {path}")
        if any(c.isspace() or ord(c) < 32 for c in path) or "\\" in path:
            raise ValueError(f"path cannot be serialized unambiguously: {path!r}")
        if not uid.isdecimal() or not gid.isdecimal() or not re.fullmatch(r"[0-7]{3,4}", mode):
            raise ValueError(f"invalid inode metadata: {path}")
        if (kind != "l" and link) or (kind == "l" and not link):
            raise ValueError(f"invalid link record: {path}")
        entries[path] = {"type": kind, "uid": int(uid), "gid": int(gid), "mode": mode, "link": link}
    if entries.get("", {}).get("type") != "d":
        raise ValueError("missing image root directory")
    for path in entries:
        if path:
            ancestor = str(PurePosixPath(path).parent)
            ancestor = "" if ancestor == "." else ancestor
            if entries.get(ancestor, {}).get("type") != "d":
                raise ValueError(f"missing directory parent: {path}")
    if args.partition == "system" and entries.get("system", {}).get("type") != "d":
        raise ValueError("S10 converter requires the observed system-as-root image layout")

    xattr_data = read_file(root, "security-xattrs.txt")
    attrs = {}
    current = None
    # Do not infer paths from the current location of an archived evidence folder.
    # The first original getfattr block describes the mounted image root.
    original_mount = None
    for line in xattr_data.decode("utf-8").splitlines():
        if line.startswith("# file: "):
            absolute = line[8:]
            if "\\" in absolute:
                raise ValueError("escaped getfattr paths require separate review")
            if original_mount is None:
                original_mount = absolute
                if not absolute.startswith("/") or not absolute.endswith("/mount"):
                    raise ValueError("unexpected original mount root")
            if absolute == original_mount:
                current = ""
            elif absolute.startswith(original_mount + "/"):
                current = absolute[len(original_mount) + 1:]
            else:
                raise ValueError("xattr path escapes original mount")
            if current in attrs:
                raise ValueError(f"duplicate xattr path: {current}")
            attrs[current] = {}
        elif line:
            if current is None or "=0x" not in line:
                raise ValueError("unsupported xattr syntax")
            key, value = line.split("=0x", 1)
            if key not in ("security.selinux", "security.capability") or key in attrs[current]:
                raise ValueError("unexpected or duplicate xattr")
            attrs[current][key] = bytes.fromhex(value)
    if set(attrs) != set(entries):
        raise ValueError("inode/xattr path coverage mismatch")

    fs_lines, context_lines = [], []
    for path in sorted(entries):
        entry, attr = entries[path], attrs[path]
        context = attr.get("security.selinux", b"").removesuffix(b"\0").decode("ascii")
        if not re.fullmatch(r"[A-Za-z0-9_:,.-]+", context) or len(context.split(":")) < 4:
            raise ValueError(f"missing/unsupported SELinux label: {path}")
        cap = 0
        if "security.capability" in attr:
            value = attr["security.capability"]
            if len(value) != 20:
                raise ValueError(f"unsupported capability revision: {path}")
            flags, low, inherit_low, high, inherit_high = struct.unpack("<5I", value)
            if flags != 0x02000001 or inherit_low or inherit_high:
                raise ValueError(f"unrepresentable capability flags/inheritance: {path}")
            cap = low | high << 32
        # Match extract_fw.sh's empty fs_config root and system-as-root paths.
        fs_path = path if args.partition == "system" or not path else args.partition + "/" + path
        context_path = "/" + path if args.partition == "system" else "/" + args.partition + ("/" + path if path else "")
        fs_lines.append(f"{fs_path} {entry['uid']} {entry['gid']} {entry['mode']} capabilities=0x{cap:x}\n")
        context_lines.append(f"{encode_builder_context_path(context_path)} {context}\n")
        entry["selinux"] = context
        entry["capabilities"] = f"0x{cap:x}"
        entry["capability_xattr_present"] = "security.capability" in attr
        entry["capability_xattr_hex"] = attr.get("security.capability", b"").hex()

    out = Path(tempfile.mkdtemp(prefix=f"metadata-{args.partition}.", dir=parent))
    (out / f"fs_config-{args.partition}").write_text("".join(fs_lines))
    (out / f"file_context-{args.partition}").write_text("".join(context_lines))
    # Retain original link targets and types: fs_config alone cannot represent them.
    (out / "paths.json").write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n")
    report = {
        "scope": "Converted source-image metadata only; final file-tree matching, builder and SELinux tooling not run",
        "partition": args.partition, "source_evidence": str(root),
        "image_fingerprint_record": before.decode(), "paths": len(entries),
        "input_sha256": {"inodes.nul": hashlib.sha256(inode_data).hexdigest(), "security-xattrs.txt": hashlib.sha256(xattr_data).hexdigest()},
        "complete": True,
        "metadata_conversion": "complete", "tree_binding": "unverified", "expanded_tree": "unverified",
        "converter_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "output_sha256": {name: hashlib.sha256((out / name).read_bytes()).hexdigest()
                          for name in (f"fs_config-{args.partition}", f"file_context-{args.partition}", "paths.json")},
    }
    (out / "conversion.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Metadata conversion directory: {out}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, ValueError) as error:
        raise SystemExit(f"Metadata conversion failed: {error}")
