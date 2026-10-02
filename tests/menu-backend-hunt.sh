#!/usr/bin/env bash
# Focused existing unit tests for menu writes, link creation/reveal and permission safety.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
failed=0
checks=0
for module in menu_actions permissions link opsdispatch; do
    output=$(cargo test -q "backend::$module::" 2>&1)
    code=$?
    printf '%s\n' "$output"
    checks=$((checks + $(printf '%s\n' "$output" | awk '/^test result:/ { n += $4 + $6 } END { print n + 0 }')))
    if [ "$code" -ne 0 ]; then
        printf 'FAIL menu-backend-hunt %s exit=%s\n' "$module" "$code"
        failed=$((failed + 1))
    fi
done
printf 'menu-backend-hunt: %s checks, %s failed\n' "$checks" "$failed"
[ "$failed" -eq 0 ]
