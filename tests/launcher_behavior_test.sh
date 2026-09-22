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
  : "${PF_ERR_OUT:=/dev/null}"
  cp "$launcher" "$tmp/launch.sh"
  mkdir -p "$tmp/bin" "$tmp/projects"
  cp -R "$REPO/tools" "$tmp/tools"
  mkdir -p "$tmp/.claude/hooks"
  cp "$REPO/.claude/settings.json" "$tmp/.claude/settings.json"
  cp "$REPO/.claude/hooks/startup.sh" "$REPO/.claude/hooks/startup.py" "$tmp/.claude/hooks/"
  # settings.json registers an absolute path into the real repo; retarget it at the copy
  python3 - "$tmp/.claude/settings.json" "$tmp" <<'PS'
import json,sys
p,root=sys.argv[1],sys.argv[2]
d=json.load(open(p))
for g in d.get("hooks",{}).get("SessionStart",[]):
    for h in g.get("hooks",[]):
        if h.get("type")=="command":
            h["command"]=root+"/.claude/hooks/startup.sh"
json.dump(d,open(p,"w"))
PS
  [ -n "${PF_BREAK:-}" ] && printf '#!/usr/bin/env bash\nexit 3\n' > "$tmp/.claude/hooks/startup.sh"
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
  ( cd "$tmp" && PROBE_ROOT="$tmp" PF_ERR_OUT="$PF_ERR_OUT" PATH="$tmp/bin:$PATH" \
      bash launch.sh >/dev/null 2>"$PF_ERR_OUT" <<< $'n\n1\n\n\n1\n\n\nn\nprobeproj\n' )
  local lrc=$?
  if [ -f "$tmp/.probe" ]; then cat "$tmp/.probe"; else echo "NOPANES:rc=$lrc"; fi
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

echo "--- the preflight gates pane creation (a broken hook must stop the launch) ---"
gotb=$(PF_BREAK=1 run_probe "$REPO/launch.sh")
case "$gotb" in
  NOPANES:*) ok "broken hook: no panes were created ($gotb)" ;;
  PRESENT:*|ABSENT) bad "broken hook: launcher created panes anyway ($gotb)" ;;
  *)         bad "broken hook: unexpected ($gotb)" ;;
esac

echo "--- control: the same probe MUST detect the pre-fix ordering ---"
REG=$(mktemp)
if make_regressed "$REG"; then
  ERRF=$(mktemp)
  gotr=$(PF_ERR_OUT="$ERRF" run_probe "$REG")
  errtxt=$(cat "$ERRF"); rm -f "$ERRF"
  case "$gotr" in
    PRESENT:*)
      bad "regressed copy still had ACTIVE_PROJECT present, so this probe cannot detect the defect" ;;
    ABSENT)
      ok "regressed copy reaches pane creation with ACTIVE_PROJECT absent (probe can fail)" ;;
    NOPANES:*)
      # The preflight now refuses the regressed ordering before panes exist. That is a
      # stronger outcome, but only if it refused for THIS reason and not another.
      case "$errtxt" in
        *"active project is resolved before panes start"*)
          ok "regressed copy refused by the preflight, citing the active-project assertion" ;;
        *) bad "regressed copy aborted, but not for the ordering reason: $errtxt" ;;
      esac ;;
    *) bad "regressed copy: unexpected result '$gotr'" ;;
  esac
else
  bad "could not build the regressed control"
fi
rm -f "$REG"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
