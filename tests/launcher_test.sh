#!/usr/bin/env bash
# Launcher lane tests (Agent 3). Run: bash tests/launcher_test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected $3, got $2)"; fi; }

# line number of the first match, or empty
at() { /usr/bin/grep -n "$2" "$1" | head -1 | cut -d: -f1; }
count() { /usr/bin/grep -c "$2" "$1"; }

echo "--- syntax ---"
for f in launch.sh restart-swarm.sh workspace.sh; do
  if bash -n "$f" 2>/dev/null; then ok "bash -n $f"; else bad "bash -n $f"; fi
done

echo "--- ACTIVE_PROJECT is written before panes start (the R5 ordering race) ---"
for f in launch.sh workspace.sh; do
  w=$(at "$f" '> "\$SWARM_DIR/ACTIVE_PROJECT"')
  m=$(at "$f" 'mkdir -p "\$SWARM_DIR"')
  p=$(at "$f" 'export AGENT_NUMBER=1')
  if [ -z "$w" ] || [ -z "$m" ] || [ -z "$p" ]; then
    bad "$f: could not locate anchors (write=$w mkdir=$m pane1=$p)"; continue
  fi
  if [ "$w" -lt "$p" ]; then ok "$f: ACTIVE_PROJECT write ($w) before pane 1 start ($p)"
  else bad "$f: ACTIVE_PROJECT write ($w) is AFTER pane 1 start ($p)"; fi
  if [ "$m" -lt "$p" ]; then ok "$f: mkdir SWARM_DIR ($m) before pane 1 start ($p)"
  else bad "$f: mkdir SWARM_DIR ($m) is AFTER pane 1 start ($p)"; fi
  check "$f: exactly one ACTIVE_PROJECT write" "$(count "$f" '> "\$SWARM_DIR/ACTIVE_PROJECT"')" "1"
done

echo "--- every launcher runs the preflight before it creates panes ---"
for f in launch.sh workspace.sh restart-swarm.sh; do
  c=$(at "$f" 'preflight_hook')
  src=$(at "$f" 'preflight-hook.sh')
  if [ -z "$c" ] || [ -z "$src" ]; then bad "$f: does not source and call the preflight"; continue; fi
  ok "$f: sources and calls the preflight"
  case "$f" in
    restart-swarm.sh) p=$(at "$f" 'Phase 3') ;;
    *)                p=$(at "$f" 'export AGENT_NUMBER=1') ;;
  esac
  if [ -n "$p" ] && [ "$c" -lt "$p" ]; then ok "$f: preflight call ($c) precedes pane work ($p)"
  else bad "$f: preflight call ($c) does not precede pane work ($p)"; fi
done

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
