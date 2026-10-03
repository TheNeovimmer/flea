#!/usr/bin/env bash
# Focused existing unit tests for menu writes, link creation/reveal and permission safety.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
failed=0
checks=0
for module in menu_actions permissions link opsdispatch; do
    filter="backend::$module::"
    output=$(cargo test -q "$filter" 2>&1)
    code=$?
    printf '%s\n' "$output"
    module_checks=0
    # Sample input: test result: ok. 12 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;
    while read -r first second status passed passed_label failed_tests rest; do
        [[ "$first $second" == 'test result:' ]] || continue
        [[ "$passed" =~ ^[0-9]+$ && "$failed_tests" =~ ^[0-9]+$ ]] || continue
        module_checks=$((module_checks + passed + failed_tests))
    done <<< "$output"
    checks=$((checks + module_checks))
    if [ "$module_checks" -eq 0 ]; then
        printf 'FAIL menu-backend-hunt %s ran no tests\n' "$filter"
        failed=$((failed + 1))
    fi
    if [ "$code" -ne 0 ]; then
        printf 'FAIL menu-backend-hunt %s exit=%s\n' "$module" "$code"
        failed=$((failed + 1))
    fi
done
printf 'menu-backend-hunt: %s checks, %s failed\n' "$checks" "$failed"
[ "$failed" -eq 0 ]
