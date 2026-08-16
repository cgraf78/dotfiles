#!/usr/bin/env python3
"""Compute a no-follow identity for the one-time legacy dot library tree."""

from __future__ import annotations

import hashlib
import os
import stat
import sys
from collections.abc import Iterator


def _field(digest: hashlib._Hash, value: bytes) -> None:
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def _entries(root: bytes) -> Iterator[tuple[bytes, os.stat_result, bytes | None]]:
    def visit(
        directory: bytes, relative: bytes
    ) -> Iterator[tuple[bytes, os.stat_result, bytes | None]]:
        with os.scandir(directory) as scanner:
            entries = sorted(scanner, key=lambda entry: entry.name)
        for entry in entries:
            name = entry.name
            child_relative = name if not relative else relative + b"/" + name
            metadata = entry.stat(follow_symlinks=False)
            target: bytes | None = None
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(entry.path)
            yield child_relative, metadata, target
            if stat.S_ISDIR(metadata.st_mode):
                yield from visit(entry.path, child_relative)

    yield from visit(root, b"")


def identity(path: str) -> str:
    root = os.fsencode(os.path.abspath(path))
    root_metadata = os.lstat(root)
    if not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode):
        raise ValueError("legacy library root is not a real directory")

    digest = hashlib.sha256(b"cgraf78 dot legacy library tree v1\0")
    for relative, metadata, target in _entries(root):
        mode = metadata.st_mode
        if stat.S_ISDIR(mode):
            kind = b"directory"
        elif stat.S_ISREG(mode):
            kind = b"file"
        elif stat.S_ISLNK(mode):
            kind = b"symlink"
        else:
            raise ValueError(f"unsupported legacy library entry: {os.fsdecode(relative)}")

        _field(digest, relative)
        _field(digest, kind)
        _field(digest, f"{stat.S_IMODE(mode):04o}".encode("ascii"))
        if kind == b"file":
            _field(digest, str(metadata.st_size).encode("ascii"))
            with open(root + b"/" + relative, "rb", buffering=0) as source:
                while chunk := source.read(1024 * 1024):
                    digest.update(chunk)
        elif kind == b"symlink":
            assert target is not None
            _field(digest, target)

    return f"{root_metadata.st_dev}:{root_metadata.st_ino}\t{digest.hexdigest()}"


def main() -> int:
    if len(sys.argv) == 4 and sys.argv[1] == "symlink":
        try:
            os.symlink(sys.argv[2], sys.argv[3])
        except OSError as error:
            print(f"dot library handoff: {error}", file=sys.stderr)
            return 1
        return 0
    if len(sys.argv) != 2:
        print("usage: dot-library-tree.py ROOT | symlink TARGET PATH", file=sys.stderr)
        return 2
    try:
        print(identity(sys.argv[1]))
    except (OSError, ValueError) as error:
        print(f"dot library handoff: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
