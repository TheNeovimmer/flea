#!/usr/bin/env python3
# Assembles the classic figure worker Qt's WorkerScript can actually load.
#
# Qt's worker engine parses its source as a classic script: module syntax in
# the source is a parse-time SyntaxError (measured in the lane), and compiling
# a 2.8 MB bundle as a worker source wedges the engine outright. So the worker
# carries no bundle at all: the service reads each bundle as text and the
# worker installs it with one eval (which parses megabytes in milliseconds).
# This script only strips FigureWorker.mjs's export prefixes into classic
# syntax. No npm, no network.
#
#   tools/vendor-js/assemble-figure-workers.py [--check]
# Without --check writes ui/vendor/figure-worker.js; with --check rebuilds in
# memory and fails unless it matches what is committed.
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
WORKER = ROOT / "ui/js/FigureWorker.mjs"
DEST = ROOT / "ui/vendor/figure-worker.js"

HEADER = """// Generated from ui/js/FigureWorker.mjs by
// tools/vendor-js/assemble-figure-workers.py. Never hand edit: change the
// worker and reassemble. Classic syntax only, because Qt's WorkerScript
// source cannot carry import or export statements.
"""


def assemble():
    src = WORKER.read_text()
    out = re.sub(r"^export (function|const|var|let|class) ", r"\1 ", src, flags=re.M)
    for line in out.splitlines():
        assert not line.startswith("export"), "unhandled export form: %r" % line
    assert "import(" not in out, "dynamic import survived the transform"
    return HEADER + out


def main():
    check = "--check" in sys.argv
    out = assemble()
    if check:
        if not DEST.is_file() or DEST.read_text() != out:
            print("figure worker: %s differs, reassemble" % DEST.name)
            sys.exit(1)
        print("figure worker: committed output reproduces")
    else:
        DEST.write_text(out)
        print("figure worker: wrote %s (%d bytes)" % (DEST.name, len(out)))


main()
