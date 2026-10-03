#!/usr/bin/env bash
# Selector lint and compositor-free regression proof share this headless suite.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
failed=0
checks=2
python3 tests/hyprdispatch.py || failed=$((failed + 1))
python3 tests/hypr-dispatch-proof.py || failed=$((failed + 1))
printf 'hyprdispatch: %d checks passed, %d failed\n' "$((checks - failed))" "$failed"
[[ "$failed" == 0 ]]
