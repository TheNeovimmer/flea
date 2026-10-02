#!/usr/bin/env bash
# The no-root half of tests/fs-matrix.sh, run headless by tests/run-all.sh.
exec "$(dirname "$0")/fs-matrix.sh" --smoke
