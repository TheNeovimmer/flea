#!/usr/bin/env python3
"""Verify clipboard publication and the filesystem results of the menu hunt."""
import json
import os
from pathlib import Path
import sys

SELECTED_NAMES = ("alpha.txt", "beta.txt")
FILE_CLIPBOARD_MIME = "x-special/gnome-copied-files"


def publication(action, calls_path, source):
    calls = calls_path.read_text().splitlines()
    if not calls:
        raise ValueError("no clipboard publication calls")
    expected_paths = [(source / name).as_uri() for name in SELECTED_NAMES]
    # Sample input: {"args":["--type","x-special/gnome-copied-files"],"text":"cut\nfile:///source/alpha.txt\nfile:///source/beta.txt\n"}
    for line in calls:
        call = json.loads(line)
        lines = call["text"].splitlines()
        if lines != [action, *expected_paths]:
            raise ValueError("publication must name exactly both selected paths with verb " + action)
        if FILE_CLIPBOARD_MIME not in call["args"]:
            raise ValueError("publication lacks the file clipboard MIME type")


def files(action, source, destination):
    for name in SELECTED_NAMES:
        src, dest = source / name, destination / name
        if action.startswith("pasteas"):
            if action == "pasteas-hard":
                if dest.is_symlink() or not dest.is_file():
                    raise ValueError(name + " is not a regular hard link")
                if (dest.stat().st_dev, dest.stat().st_ino) != (src.stat().st_dev, src.stat().st_ino):
                    raise ValueError(name + " does not share the source inode")
            else:
                if not dest.is_symlink():
                    raise ValueError(name + " is not a symlink")
                target = os.readlink(dest)
                absolute = action == "pasteas-absolute"
                if os.path.isabs(target) != absolute:
                    raise ValueError(name + " has the wrong relative/absolute target form")
                if dest.resolve(strict=True) != src.resolve(strict=True):
                    raise ValueError(name + " does not resolve to the selected source")
        elif not dest.is_file() or dest.is_symlink():
            raise ValueError(name + " is not a destination file")
        if action == "copy" and not (src.exists() or src.is_symlink()):
            raise ValueError(name + " is missing from the Copy source")
        if action == "cut" and (src.exists() or src.is_symlink()):
            raise ValueError(name + " remains at the Cut source")


def main():
    kind, action, first, second = sys.argv[1:]
    try:
        if kind == "publication":
            publication(action, Path(first), Path(second))
        elif kind == "files":
            files(action, Path(first), Path(second))
        else:
            raise ValueError("unknown check " + kind)
    except (ValueError, KeyError, TypeError, OSError) as error:
        print("FAIL " + action + " " + kind + ": " + str(error))
        return 1
    print("PASS " + action + " " + kind + " verified both selected files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
