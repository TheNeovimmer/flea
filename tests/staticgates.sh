#!/usr/bin/env bash
# Five source gates share one scanner; temporary negative controls run before the tree checks.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/staticgates_tests.py
exec python3 tests/staticgates.py "$@"
