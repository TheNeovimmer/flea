#!/usr/bin/env bash
# Exercise retained picker identities and batch selection in the suite's isolated test sandbox.
set -euo pipefail
cd "$(dirname "$0")/.."
cargo test --locked backend::picker::tests -- --test-threads=1
