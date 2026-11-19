#!/usr/bin/env python3
"""Relocate a Kwi build tree from its CI Nix store paths into this output."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def relative_origin(target: Path, elf: Path) -> str:
    relative = os.path.relpath(target, elf.parent)
    return "$ORIGIN" if relative == "." else f"$ORIGIN/{relative}"


def map_store_path(entry: str, old_prefix: str, new_root: Path, elf: Path) -> str:
    if entry == old_prefix or entry.startswith(old_prefix + "/"):
        suffix = entry[len(old_prefix):].lstrip("/")
        target = new_root / suffix if suffix else new_root
        return relative_origin(target, elf)
    return entry


def rewrite_symlink(
    path: Path, old_kwi: str, old_ghostty: str, app_root: Path, runtime_root: Path
) -> None:
    target = os.readlink(path)
    replacement = target
    if target == old_kwi or target.startswith(old_kwi + "/"):
        replacement = str(app_root) + target[len(old_kwi):]
    elif target == old_ghostty or target.startswith(old_ghostty + "/"):
        replacement = str(runtime_root) + target[len(old_ghostty):]
    if replacement != target:
        path.unlink()
        path.symlink_to(replacement)


def rewrite_text_file(
    path: Path, old_kwi: str, old_ghostty: str, app_root: Path, runtime_root: Path
) -> None:
    try:
        content = path.read_bytes()
        if b"\0" in content:
            return
        text = content.decode("utf-8")
    except (OSError, UnicodeDecodeError):
        return

    updated = text.replace(old_kwi, str(app_root)).replace(
        old_ghostty, str(runtime_root)
    )
    if updated != text:
        path.write_text(updated, encoding="utf-8")


def rewrite_elf_rpath(
    path: Path, old_kwi: str, old_ghostty: str, app_root: Path, runtime_root: Path
) -> None:
    result = subprocess.run(
        ["patchelf", "--print-rpath", str(path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode != 0:
        return

    old_entries = result.stdout.strip().split(":") if result.stdout.strip() else []
    new_entries: list[str] = []
    changed = False
    for entry in old_entries:
        updated = map_store_path(entry, old_kwi, app_root, path)
        updated = map_store_path(updated, old_ghostty, runtime_root, path)
        if updated != entry:
            changed = True
        if updated and updated not in new_entries:
            new_entries.append(updated)

    # Make sure the bundled libghostty-vt is discoverable for ELF objects that
    # link to it, even if the original build did not retain an explicit RPATH.
    needed = subprocess.run(
        ["patchelf", "--print-needed", str(path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if needed.returncode == 0 and any("ghostty-vt" in name for name in needed.stdout.splitlines()):
        ghostty_lib = runtime_root / "lib"
        candidate = relative_origin(ghostty_lib, path)
        if candidate not in new_entries:
            new_entries.insert(0, candidate)
            changed = True

    if changed:
        subprocess.run(
            ["patchelf", "--set-rpath", ":".join(new_entries), str(path)],
            check=True,
        )


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: patch-runtime.py APP_ROOT RUNTIME_ROOT KWI_STORE_PATH LIBGHOSTTY_STORE_PATH"
        )

    app_root = Path(sys.argv[1]).resolve()
    runtime_root = Path(sys.argv[2]).resolve()
    old_kwi = sys.argv[3]
    old_ghostty = sys.argv[4]

    if not old_kwi.startswith("/nix/store/") or not old_ghostty.startswith("/nix/store/"):
        raise SystemExit("release metadata does not contain valid Nix store paths")

    if not app_root.is_dir() or not runtime_root.is_dir():
        raise SystemExit("application and bundled runtime directories must both exist")

    # Relocate references in both the application and the separately bundled
    # library tree. The latter may itself carry RPATHs or symlinks into the
    # original Nix store output.
    for tree in (app_root, runtime_root):
        for path in tree.rglob("*"):
            if path.is_symlink():
                rewrite_symlink(path, old_kwi, old_ghostty, app_root, runtime_root)
            elif path.is_file():
                rewrite_text_file(path, old_kwi, old_ghostty, app_root, runtime_root)
                rewrite_elf_rpath(path, old_kwi, old_ghostty, app_root, runtime_root)


if __name__ == "__main__":
    main()
