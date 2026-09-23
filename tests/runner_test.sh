#!/usr/bin/env bash
# Tests the test runner itself. Agent 1 found run.sh reported success when zero test
# files matched, which would have made a rename or bad glob look like a green suite.
set -uo pipefail
cd "$(dirname "$0")"
RUNNER=$PWD/run.sh
MIN=$(/usr/bin/grep -m1 '^MIN_SUITES=' "$RUNNER" | cut -d= -f2)
mkpass() { local d=$1 n=$2 i; for i in $(seq 1 "$n"); do printf '#!/usr/bin/env bash\nexit 0\n' > "$d/s${i}_test.sh"; done; }
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

echo "--- runner refuses to pass when it ran nothing ---"
d=$(mktemp -d); cp "$RUNNER" "$d/run.sh"
out=$(cd "$d" && bash run.sh 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "zero test files exits non-zero (rc=$rc)" || bad "zero test files exited 0: $out"
case "$out" in *"NO TEST FILES MATCHED"*) ok "says why it refused" ;; *) bad "no diagnosis: $out" ;; esac
case "$out" in *"ALL"*"PASSED"*) bad "still claimed success with nothing run" ;; *) ok "does not claim success" ;; esac
rm -rf "$d"

echo "--- runner is loud when a suite disappears ---"
d=$(mktemp -d); cp "$RUNNER" "$d/run.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/a_test.sh"
out=$(cd "$d" && bash run.sh 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "fewer suites than MIN_SUITES exits non-zero (rc=$rc)" || bad "missing suites passed silently"
case "$out" in *"went missing"*) ok "names the missing-suite condition" ;; *) bad "no diagnosis: $out" ;; esac
rm -rf "$d"

echo "--- control: a failing suite still fails (aggregation works) ---"
d=$(mktemp -d); cp "$RUNNER" "$d/run.sh"
mkpass "$d" "$MIN"
printf '#!/usr/bin/env bash\nexit 1\n' > "$d/z_test.sh"
out=$(cd "$d" && bash run.sh 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "one failing suite among the full complement exits 1" || bad "failing suite reported rc=$rc"
rm -rf "$d"

echo "--- control: all-passing full complement exits 0 (not always-red) ---"
d=$(mktemp -d); cp "$RUNNER" "$d/run.sh"
mkpass "$d" "$MIN"
out=$(cd "$d" && bash run.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "$MIN passing suites exit 0" || bad "green case wrongly failed: $out"
rm -rf "$d"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
