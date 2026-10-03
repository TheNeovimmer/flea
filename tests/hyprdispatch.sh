#!/usr/bin/env bash
# Selector lint and compositor-free regression proof share this headless suite.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
failed=0
python3 tests/hyprdispatch.py || failed=$((failed + 1))
python3 tests/hypr-dispatch-proof.py || failed=$((failed + 1))
printf 'hyprdispatch: %d checks passed, %d failed\n' "$((2 - failed))" "$failed"
[[ "$failed" == 0 ]]
