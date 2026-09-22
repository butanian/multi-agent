#!/usr/bin/env bash
# Entrypoint for the harness test suite. Run: bash tests/run.sh
# Exits non-zero if any test file fails, if none are found, or if files went missing.
# MIN_SUITES guards against silent loss: a rename or bad glob must be loud, not green.
# Bump it when adding a suite; it only fires when files DISAPPEAR.
MIN_SUITES=12
cd "$(dirname "$0")"
rc=0
found=0
for t in *_test.sh; do
  [ -e "$t" ] || continue
  found=$((found+1))
  echo "== $t"
  bash "$t" || rc=1
done

if [ "$found" -eq 0 ]; then
  echo "NO TEST FILES MATCHED *_test.sh — refusing to report success" >&2
  exit 2
fi
if [ "$found" -lt "$MIN_SUITES" ]; then
  echo "ONLY $found SUITES FOUND, EXPECTED AT LEAST $MIN_SUITES — a suite went missing" >&2
  rc=1
fi
if [ "$rc" -eq 0 ]; then echo "ALL $found SUITES PASSED"; else echo "SUITE FAILURES PRESENT"; fi
exit "$rc"
