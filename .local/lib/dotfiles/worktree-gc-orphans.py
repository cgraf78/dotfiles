#!/usr/bin/env python3
"""Prove and retire metadata-orphaned checkouts without recursive deletion."""

import hashlib
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

Snapshot = tuple[dict[bytes, tuple[bytes, bytes]], set[bytes]]


class Unsafe(Exception):
    """A checkout cannot be proven safe, or changed during retirement."""


class RetirementFailed(Unsafe):
    """Retirement stopped after moving the checkout to recoverable quarantine."""


def git(common: str, *args: str) -> bytes:
    """Read Git objects without a checkout index or persistent temporary state."""
    return subprocess.check_output(["git", "--git-dir=" + common, *args], stderr=subprocess.DEVNULL)


def recover(directory: str, pointer_base: str = "") -> tuple[str, bytes]:
    """Accept only a missing linked-worktree admin path with a valid owner."""
    pointer = os.path.join(directory, ".git")
    if not stat.S_ISREG(os.lstat(pointer).st_mode):
        raise Unsafe("broken git pointer")
    with open(pointer, "rb") as stream:
        raw = stream.read()
    lines = raw.splitlines()
    if len(lines) != 1 or not lines[0].startswith(b"gitdir: "):
        raise Unsafe("broken git pointer")
    target = os.fsdecode(lines[0][8:])
    if not os.path.isabs(target):
        target = os.path.join(pointer_base or directory, target)
    target = os.path.abspath(target)
    if "\n" in target or "\n" in directory:
        raise Unsafe("unsupported checkout pathname")
    if os.path.realpath(target) != target:
        raise Unsafe("broken git pointer")
    if os.path.lexists(target) or os.path.basename(os.path.dirname(target)) != "worktrees":
        raise Unsafe("broken git pointer")
    common = os.path.dirname(os.path.dirname(target))
    if not os.path.isdir(common) or os.path.realpath(common) != common:
        raise Unsafe("broken git pointer")
    if git(common, "rev-parse", "--git-common-dir").strip() != os.fsencode(common):
        raise Unsafe("broken git pointer")
    return common, raw


def snapshot(directory: str, algorithm: str) -> Snapshot:
    """Read every entry without following symlinks, rejecting external aliases."""
    files, dirs = {}, set()
    root = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    root_device = os.fstat(root).st_dev

    def walk(fd, prefix):
        names = os.listdir(fd)
        if prefix and ".git" in names:
            raise Unsafe("contains another checkout")
        if prefix and {"HEAD", "objects", "refs"}.issubset(names):
            if stat.S_ISREG(os.stat("HEAD", dir_fd=fd, follow_symlinks=False).st_mode) and all(
                stat.S_ISDIR(os.stat(name, dir_fd=fd, follow_symlinks=False).st_mode)
                for name in ("objects", "refs")
            ):
                raise Unsafe("contains a nested bare repository")
        for name in names:
            relative = prefix + os.fsencode(name)
            if relative == b".git":
                continue
            info = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if info.st_dev != root_device:
                raise Unsafe("checkout crosses a filesystem mount")
            if stat.S_ISDIR(info.st_mode):
                dirs.add(relative)
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                try:
                    opened = os.fstat(child)
                    if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
                        raise Unsafe("checkout changed during inspection")
                    walk(child, relative + b"/")
                finally:
                    os.close(child)
            elif stat.S_ISLNK(info.st_mode):
                value = os.fsencode(os.readlink(name, dir_fd=fd))
                files[relative] = (b"120000", digest(value, algorithm))
            elif stat.S_ISREG(info.st_mode) and info.st_nlink == 1:
                child = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=fd)
                try:
                    opened = os.fstat(child)
                    if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
                        raise Unsafe("checkout changed during inspection")
                    with os.fdopen(child, "rb", closefd=False) as stream:
                        value = stream.read()
                    after = os.fstat(child)
                    if (after.st_size, after.st_mtime_ns, after.st_ctime_ns) != (
                        opened.st_size,
                        opened.st_mtime_ns,
                        opened.st_ctime_ns,
                    ):
                        raise Unsafe("checkout changed during inspection")
                finally:
                    os.close(child)
                files[relative] = (
                    b"100755" if info.st_mode & 0o111 else b"100644",
                    digest(value, algorithm),
                )
            else:
                raise Unsafe("unsupported or externally linked checkout entry")

    try:
        walk(root, b"")
    finally:
        os.close(root)
    return files, dirs


def digest(value: bytes, algorithm: str) -> bytes:
    """Compute Git's blob identity without writing an object."""
    return (
        hashlib.new(algorithm, b"blob " + str(len(value)).encode() + b"\0" + value)
        .hexdigest()
        .encode()
    )


def tree(common: str, oid: str) -> Snapshot:
    """Reject submodules and derive the exact directory shape of a Git tree."""
    files, dirs = {}, set()
    for entry in git(common, "ls-tree", "-rz", oid).split(b"\0"):
        if not entry:
            continue
        header, name = entry.split(b"\t", 1)
        mode, kind, blob = header.split()
        if kind != b"blob" or mode not in (b"100644", b"100755", b"120000"):
            raise Unsafe("merged tree contains unsupported entries")
        files[name] = (mode, blob)
        parts = name.split(b"/")
        for end in range(1, len(parts)):
            dirs.add(b"/".join(parts[:end]))
    return files, dirs


def prove(directory: str, common: str, base: str) -> tuple[str, Snapshot, str]:
    """Find an exact snapshot in first-parent merged history."""
    algorithm = git(common, "rev-parse", "--show-object-format").strip().decode()
    observed = snapshot(directory, algorithm)
    files, _ = observed
    dirs = set()
    for name in files:
        parts = name.split(b"/")
        for end in range(1, len(parts)):
            dirs.add(b"/".join(parts[:end]))

    def tree_digest(prefix):
        entries = []
        for name, (mode, blob) in files.items():
            if name.startswith(prefix) and b"/" not in name[len(prefix) :]:
                entries.append((name[len(prefix) :], mode, blob))
        for name in dirs:
            if name.startswith(prefix) and b"/" not in name[len(prefix) :]:
                entries.append((name[len(prefix) :], b"40000", tree_digest(name + b"/")))
        value = b"".join(
            mode + b" " + name + b"\0" + bytes.fromhex(blob.decode())
            for name, mode, blob in sorted(
                entries, key=lambda item: item[0] + (b"/" if item[1] == b"40000" else b"")
            )
        )
        return (
            hashlib.new(algorithm, b"tree " + str(len(value)).encode() + b"\0" + value)
            .hexdigest()
            .encode()
        )

    observed_tree = tree_digest(b"")
    for line in git(common, "log", "--first-parent", "--format=%H %T", base).splitlines():
        oid, tree_oid = line.split()
        if tree_oid == observed_tree and (files, dirs) == tree(common, oid.decode()):
            return oid.decode(), observed, algorithm
    raise Unsafe("orphaned checkout differs from merged history")


def unregistered(common: str, directory: str) -> None:
    """Re-read owner registration immediately before moving/removing files."""
    for line in git(common, "worktree", "list", "--porcelain", "-z").split(b"\0"):
        if line.startswith(b"worktree "):
            registered = os.path.realpath(os.fsdecode(line[9:]))
            if registered == directory:
                raise Unsafe("registered worktree with broken pointer")


def idle(directory: str) -> None:
    """Require a usable process inventory and reject a visible working directory."""
    if not os.path.isdir("/proc") or not os.path.isdir("/proc/self/cwd"):
        raise Unsafe("process working-directory inventory unavailable")
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            cwd = os.path.realpath(os.readlink("/proc/" + name + "/cwd"))
        except OSError:
            continue
        if cwd == directory or cwd.startswith(directory + os.sep):
            raise Unsafe("in use (a process's working directory)")


def retire(directory: str, common: str, base: str, pointer: bytes) -> str:
    """Quarantine before deletion; preserve changed remnants for recovery.

    Revalidation bounds ordinary races but cannot make unlink transactional
    against a writer holding an already-open descriptor. Never follow changed
    parent symlinks or recursively delete an unchecked entry.
    """
    oid, expected, algorithm = prove(directory, common, base)
    idle(directory)
    unregistered(common, directory)
    parent = os.path.dirname(directory)
    container = tempfile.mkdtemp(prefix=".dot-worktree-gc-quarantine-", dir=parent)
    quarantine = os.path.join(container, "checkout")
    try:
        os.rename(directory, quarantine)
    except OSError:
        os.rmdir(container)
        raise

    try:
        idle(quarantine)
        unregistered(common, directory)
        if (
            recover(quarantine, directory) != (common, pointer)
            or snapshot(quarantine, algorithm) != expected
        ):
            raise Unsafe("checkout changed during cleanup")
        root = os.open(quarantine, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        root_info = os.fstat(root)
        try:
            # Open every parent from the anchored root; no pathname may redirect
            # traversal to a concurrently substituted symlink outside quarantine.
            for relative in sorted(expected[0]):
                now = os.stat(quarantine, follow_symlinks=False)
                if (now.st_dev, now.st_ino) != (root_info.st_dev, root_info.st_ino):
                    raise Unsafe("checkout changed during cleanup")
                parts = os.fsdecode(relative).split("/")
                fd = os.dup(root)
                try:
                    for component in parts[:-1]:
                        child = os.open(
                            component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd
                        )
                        os.close(fd)
                        fd = child
                    name = parts[-1]
                    info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                    wanted_mode, wanted_blob = expected[0][relative]
                    if wanted_mode == b"120000" and stat.S_ISLNK(info.st_mode):
                        value = os.fsencode(os.readlink(name, dir_fd=fd))
                    elif (
                        wanted_mode in (b"100644", b"100755")
                        and stat.S_ISREG(info.st_mode)
                        and info.st_nlink == 1
                    ):
                        if bool(info.st_mode & 0o111) != (wanted_mode == b"100755"):
                            raise Unsafe("checkout changed during cleanup")
                        child = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=fd)
                        try:
                            opened = os.fstat(child)
                            if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
                                raise Unsafe("checkout changed during cleanup")
                            with os.fdopen(child, "rb", closefd=False) as stream:
                                value = stream.read()
                        finally:
                            os.close(child)
                    else:
                        raise Unsafe("checkout changed during cleanup")
                    if digest(value, algorithm) != wanted_blob:
                        raise Unsafe("checkout changed during cleanup")
                    current = os.stat(name, dir_fd=fd, follow_symlinks=False)
                    if (
                        current.st_dev,
                        current.st_ino,
                        current.st_mtime_ns,
                        current.st_ctime_ns,
                    ) != (info.st_dev, info.st_ino, info.st_mtime_ns, info.st_ctime_ns):
                        raise Unsafe("checkout changed during cleanup")
                    os.unlink(name, dir_fd=fd)
                finally:
                    os.close(fd)
            for relative in sorted(expected[1], key=lambda item: item.count(b"/"), reverse=True):
                parts = os.fsdecode(relative).split("/")
                fd = os.dup(root)
                try:
                    for component in parts[:-1]:
                        child = os.open(
                            component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd
                        )
                        os.close(fd)
                        fd = child
                    os.rmdir(parts[-1], dir_fd=fd)
                finally:
                    os.close(fd)
            if os.listdir(root) != [".git"]:
                raise Unsafe("checkout changed during cleanup")
            child = os.open(".git", os.O_RDONLY | os.O_NOFOLLOW, dir_fd=root)
            try:
                info = os.fstat(child)
                if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                    raise Unsafe("checkout changed during cleanup")
                with os.fdopen(child, "rb", closefd=False) as stream:
                    if stream.read() != pointer:
                        raise Unsafe("checkout changed during cleanup")
                current = os.stat(".git", dir_fd=root, follow_symlinks=False)
                if (current.st_dev, current.st_ino, current.st_mtime_ns, current.st_ctime_ns) != (
                    info.st_dev,
                    info.st_ino,
                    info.st_mtime_ns,
                    info.st_ctime_ns,
                ):
                    raise Unsafe("checkout changed during cleanup")
            finally:
                os.close(child)
            os.unlink(".git", dir_fd=root)
        finally:
            os.close(root)
        os.rmdir(quarantine)
        os.rmdir(container)
        return oid
    except (OSError, Unsafe):
        raise RetirementFailed(
            "cleanup stopped; preserved remaining files at " + quarantine
        ) from None


def main() -> int:
    """Expose tab-separated machine results, keeping unexpected errors closed."""
    try:
        mode, directory_arg = sys.argv[1:3]
        directory = str(Path(directory_arg).absolute())
        common, pointer = recover(directory)
        if mode == "owner":
            print(common)
        elif mode == "prove":
            idle(directory)
            unregistered(common, directory)
            print(prove(directory, common, sys.argv[3])[0])
        elif mode == "remove":
            print(retire(directory, common, sys.argv[3], pointer))
        else:
            return 1
    except (OSError, Unsafe, subprocess.SubprocessError, ValueError) as error:
        print(
            str(error) if isinstance(error, Unsafe) else "orphaned checkout could not be inspected",
            file=sys.stderr,
        )
        return 2 if isinstance(error, RetirementFailed) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
