#!/usr/bin/env bash
# Behavioural test: does ACTIVE_PROJECT exist AT THE MOMENT the panes are created?
# Runs a copy of launch.sh in a temp dir with osascript stubbed. osascript is only
# called to create the panes, so the stub fires exactly at that boundary and probes
# the filesystem there. A textual line-order check cannot prove this.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

run_probe() { # $1 = launcher file to exercise; echoes PRESENT:<value> | ABSENT | ERROR:*
  local launcher=$1 tmp
  tmp=$(mktemp -d)
  cp "$launcher" "$tmp/launch.sh"
  mkdir -p "$tmp/bin" "$tmp/projects"
  cat > "$tmp/bin/osascript" <<'EOS'
#!/usr/bin/env bash
f=$(ls "$PROBE_ROOT"/swarms/*/ACTIVE_PROJECT 2>/dev/null | head -1)
if [ -n "$f" ]; then printf 'PRESENT:%s' "$(cat "$f")" > "$PROBE_ROOT/.probe"
else printf 'ABSENT' > "$PROBE_ROOT/.probe"; fi
echo "AAA,BBB,CCC,DDD"
EOS
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/sleep"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/send-to-agent.sh"
  chmod +x "$tmp/bin/osascript" "$tmp/bin/sleep" "$tmp/send-to-agent.sh"
  ( cd "$tmp" && PROBE_ROOT="$tmp" PATH="$tmp/bin:$PATH" \
      bash launch.sh >/dev/null 2>&1 <<< $'n\n1\n\n\n1\n\n\nn\nprobeproj\n' ) || true
  if [ -f "$tmp/.probe" ]; then cat "$tmp/.probe"; else echo "ERROR:stub-never-ran"; fi
  rm -rf "$tmp"
}

# Rebuild the pre-fix ordering FROM the current file, so the control cannot go stale.
make_regressed() {
  python3 - "$REPO/launch.sh" "$1" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
block = ('SWARM_DIR="$SCRIPT_DIR/swarms/$SWARM_ID"\n'
         'mkdir -p "$SWARM_DIR"\n'
         'printf \'%s\' "$ACTIVE_PROJECT_VALUE" > "$SWARM_DIR/ACTIVE_PROJECT"\n')
anchor = 'cat > "$SWARM_DIR/pane-config.sh" << EOF'
if s.count(block) != 1 or s.count(anchor) != 1:
    sys.exit("control could not be built: anchors moved")
s = s.replace(block, '', 1).replace(anchor, block + anchor, 1)
open(dst, 'w').write(s)
PY
}

echo "--- ACTIVE_PROJECT exists at the pane-creation boundary ---"
got=$(run_probe "$REPO/launch.sh")
case "$got" in
  PRESENT:probeproj) ok "launch.sh: present and correct at pane creation ($got)" ;;
  ABSENT)            bad "launch.sh: ACTIVE_PROJECT did NOT exist when panes were created" ;;
  *)                 bad "launch.sh: harness problem ($got)" ;;
esac

echo "--- control: the same probe MUST detect the pre-fix ordering ---"
REG=$(mktemp)
if make_regressed "$REG"; then
  gotr=$(run_probe "$REG")
  if [ "$gotr" = "ABSENT" ]; then ok "regressed copy correctly reports ABSENT (probe can fail)"
  else bad "regressed copy reported '$gotr', so this probe cannot detect the defect"; fi
else
  bad "could not build the regressed control"
fi
rm -f "$REG"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
