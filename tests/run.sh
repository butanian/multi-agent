#!/usr/bin/env bash
# Entrypoint for the harness test suite. Run: bash tests/run.sh
# Exits non-zero if any test file fails.
cd "$(dirname "$0")"
rc=0
for t in *_test.sh; do
  [ -e "$t" ] || continue
  echo "== $t"
  bash "$t" || rc=1
done
if [ "$rc" -eq 0 ]; then echo "ALL SUITES PASSED"; else echo "SUITE FAILURES PRESENT"; fi
exit "$rc"
