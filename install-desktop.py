#!/usr/bin/env python3
"""Promote an app tree's desktop integration to the Nix output root."""

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path


def copy_share_tree(app_root: Path, output_root: Path, name: str) -> None:
    source = app_root / "share" / name
    if not source.exists():
        return
    destination = output_root / "share" / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, destination, dirs_exist_ok=True, symlinks=True)
    else:
        shutil.copy2(source, destination, follow_symlinks=False)


def rewrite_exec_value(value: str, launcher: str) -> str:
    match = re.match(r'("(?:[^"\\]|\\.)*"|\S+)(.*)$', value)
    remainder = match.group(2) if match else ""
    return launcher + remainder


def rewrite_desktop_file(path: Path, launcher: str) -> None:
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    updated: list[str] = []
    in_desktop_entry = False
    found_desktop_entry = False
    found_exec = False
    found_tryexec = False

    for line in lines:
        newline = "\r\n" if line.endswith("\r\n") else "\n" if line.endswith("\n") else ""
        content = line[:-len(newline)] if newline else line

        if content.startswith("[") and content.endswith("]"):
            if in_desktop_entry:
                if not found_exec:
                    updated.append(f"Exec={launcher}\n")
                if not found_tryexec:
                    updated.append(f"TryExec={launcher}\n")
            in_desktop_entry = content == "[Desktop Entry]"
            found_desktop_entry = found_desktop_entry or in_desktop_entry
            found_exec = False
            found_tryexec = False
            updated.append(line)
            continue

        if content.startswith("Exec="):
            value = content[len("Exec="):]
            content = f"Exec={rewrite_exec_value(value, launcher)}"
            if in_desktop_entry:
                found_exec = True
        elif content.startswith("TryExec=") and in_desktop_entry:
            content = f"TryExec={launcher}"
            found_tryexec = True

        updated.append(content + newline)

    if in_desktop_entry:
        if not found_exec:
            updated.append(f"Exec={launcher}\n")
        if not found_tryexec:
            updated.append(f"TryExec={launcher}\n")
    if not found_desktop_entry:
        raise SystemExit(f"missing [Desktop Entry] group in {path}")

    path.write_text("".join(updated), encoding="utf-8")


def create_fallback_desktop_file(destination: Path, launcher: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        "\n".join(
            [
                "[Desktop Entry]",
                "Type=Application",
                "Name=Kwi",
                "GenericName=Terminal",
                "Comment=Modern terminal emulator for KDE Plasma and other desktops",
                f"Exec={launcher}",
                f"TryExec={launcher}",
                "Icon=utilities-terminal",
                "Terminal=false",
                "Categories=Qt;KDE;System;TerminalEmulator;",
                "StartupNotify=true",
                "",
            ]
        ),
        encoding="utf-8",
    )


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: install-desktop.py APP_ROOT OUTPUT_ROOT LAUNCHER")

    app_root, output_root, launcher = map(Path, sys.argv[1:])
    if not app_root.is_dir() or not output_root.is_dir():
        raise SystemExit("application and output roots must already exist")

    # Keep all normal desktop metadata visible to XDG/KDE at the package root.
    for name in ("applications", "icons", "pixmaps", "metainfo", "mime"):
        copy_share_tree(app_root, output_root, name)

    applications = output_root / "share" / "applications"
    desktop_files = sorted(applications.glob("*.desktop")) if applications.is_dir() else []
    if not desktop_files:
        fallback = applications / "org.kde.kwi.desktop"
        create_fallback_desktop_file(fallback, str(launcher))
        desktop_files = [fallback]

    for desktop_file in desktop_files:
        rewrite_desktop_file(desktop_file, str(launcher))

    if not any(path.is_file() for path in (output_root / "share" / "icons").rglob("*")):
        # The desktop entry remains usable on systems with the standard
        # freedesktop/KDE terminal icon theme even if upstream ships no icon.
        for desktop_file in desktop_files:
            text = desktop_file.read_text(encoding="utf-8")
            text = re.sub(r"(?m)^Icon=.*$", "Icon=utilities-terminal", text)
            desktop_file.write_text(text, encoding="utf-8")

    # Confirm that launcher metadata is now suitable for a Nix package.
    for desktop_file in desktop_files:
        contents = desktop_file.read_text(encoding="utf-8")
        if f"Exec={launcher}" not in contents or f"TryExec={launcher}" not in contents:
            raise SystemExit(f"failed to rewrite launcher fields in {desktop_file}")


if __name__ == "__main__":
    main()
