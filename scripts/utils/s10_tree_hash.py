# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-only cache digest; invoked by the builder, not during static review.

Hash contents, file kinds, modes, owners, empty directories and symlink text.
Android absolute symlinks are not followed into the build host. Metadata files
are hashed as ordinary inputs; host ownership is never used to restore Android
metadata. The digest is a cache key, not a build or runtime attestation.
"""
import hashlib
import json
import os
from pathlib import Path
import stat
import sys


def fingerprint(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def tree_digest(mode, salt, roots):
    digest = hashlib.sha256()

    def record(value):
        data = json.dumps(value, ensure_ascii=True, separators=(",", ":")).encode()
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)

    def walk(path, relative):
        before = path.lstat()
        record([relative, stat.S_IFMT(before.st_mode), stat.S_IMODE(before.st_mode),
                before.st_uid, before.st_gid])
        attributes = []
        for name in sorted(os.listxattr(path, follow_symlinks=False)):
            value = os.getxattr(path, name, follow_symlinks=False)
            attributes.append([name, hashlib.sha256(value).hexdigest()])
        record(["xattrs", attributes])
        if stat.S_ISLNK(before.st_mode):
            record(["link", os.readlink(path)])
        elif stat.S_ISREG(before.st_mode):
            content = hashlib.sha256()
            with path.open("rb") as stream:
                if fingerprint(os.fstat(stream.fileno())) != fingerprint(before):
                    raise ValueError(f"input changed while opening: {path}")
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    content.update(block)
                if fingerprint(os.fstat(stream.fileno())) != fingerprint(before):
                    raise ValueError(f"input changed while hashing: {path}")
            record(["file", before.st_size, content.hexdigest()])
        elif stat.S_ISDIR(before.st_mode):
            for child in sorted(path.iterdir(), key=lambda p: p.name):
                # Only the root completion record and its temporary siblings
                # are excluded; other hidden files are significant.
                if mode == "work" and relative == "." and (
                    child.name == ".completed" or child.name.startswith(".completed.")
                ):
                    continue
                walk(child, child.name if relative == "." else relative + "/" + child.name)
        else:
            raise ValueError(f"unsupported cache input type: {path}")
        if fingerprint(path.lstat()) != fingerprint(before):
            raise ValueError(f"input changed during tree scan: {path}")

    record(["s10-tree-v1", mode, salt])
    for index, root in enumerate(roots):
        path = Path(root)
        record(["root", index, str(path)])
        if not path.exists() and not path.is_symlink():
            if mode == "work":
                raise ValueError(f"missing work root: {path}")
            record(["missing"])
        else:
            walk(path, ".")
    return digest.hexdigest()


if __name__ == "__main__":
    try:
        if len(sys.argv) < 4 or sys.argv[1] not in ("inputs", "work"):
            raise ValueError("expected inputs|work, salt and root paths")
        print(tree_digest(sys.argv[1], sys.argv[2], sys.argv[3:]))
    except (OSError, ValueError) as error:
        print(f"S10 cache scan failed: {error}", file=sys.stderr)
        sys.exit(1)
