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


def record_bytes(source, snapshot):
    snapshot.write_text(json.dumps({name: (source / name).read_bytes().hex() for name in SELECTED_NAMES}))


def terminals(calls_path, source, destination):
    # Sample input: /fixture/source\n/fixture/copy-dest\n records the directory argv of two opens.
    calls = calls_path.read_text().splitlines()
    if calls != [str(source), str(destination)]:
        raise ValueError("terminal argv must open the background directory then the selected place exactly once")


def files(action, source, destination, source_bytes):
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
        if dest.read_bytes() != source_bytes[name]:
            raise ValueError(name + " destination bytes differ from the recorded source")
        if action == "copy" and not (src.exists() or src.is_symlink()):
            raise ValueError(name + " is missing from the Copy source")
        if action == "cut" and (src.exists() or src.is_symlink()):
            raise ValueError(name + " remains at the Cut source")


def main():
    kind, action, first, second = sys.argv[1:5]
    try:
        if kind == "publication":
            publication(action, Path(first), Path(second))
        elif kind == "files":
            # Sample input: {"alpha.txt":"616c7068610a","beta.txt":"626574610a"} stores the fixture bytes as hex.
            recorded = json.loads(Path(sys.argv[5]).read_text())
            source_bytes = {name: bytes.fromhex(recorded[name]) for name in SELECTED_NAMES}
            files(action, Path(first), Path(second), source_bytes)
        elif kind == "record":
            record_bytes(Path(first), Path(second))
        elif kind == "terminals":
            terminals(Path(first), Path(second), Path(sys.argv[5]))
        else:
            raise ValueError("unknown check " + kind)
    except (ValueError, KeyError, TypeError, OSError, IndexError) as error:
        print("FAIL " + action + " " + kind + ": " + str(error))
        return 1
    targets = "directories" if kind == "terminals" else "files"
    print("PASS " + action + " " + kind + " verified both selected " + targets)
    return 0


if __name__ == "__main__":
    sys.exit(main())
