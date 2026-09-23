#!/usr/bin/env bash
# Behavioural: the model and effort strings handed to validate_models must be the ones
# that actually reach the pane commands. Line-order checks cannot see this. A launcher
# that validates empty placeholders and then launches real models passes "validation
# precedes pane creation" while gating nothing at all.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

# Runs a launcher in a sandbox with validate_models replaced by a recorder and osascript
# replaced by a transcript. Echoes the temp dir; caller reads .validated and .panes.
run_launcher() { # $1 = launcher basename, $2 = source file to run
  local name=$1 src=$2 tmp stdin
  tmp=$(mktemp -d)
  cp "$src" "$tmp/$name"
  cp -R "$REPO/tools" "$tmp/tools"
  mkdir -p "$tmp/bin" "$tmp/projects/probeproj" "$tmp/.claude/hooks"
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
  # Last definition wins, so this replaces the real gate with a recorder. Everything
  # else in launcher-common.sh stays real.
  cat >> "$tmp/tools/launcher-common.sh" <<'EOS'

validate_models() { printf '%s\n' "$1" >> "$VM_REC"; return 0; }
EOS
  cat > "$tmp/bin/osascript" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PANE_REC"
printf 'AAA,BBB,CCC,DDD\n'
EOS
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/sleep"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/send-to-agent.sh"
  chmod +x "$tmp/bin/osascript" "$tmp/bin/sleep" "$tmp/send-to-agent.sh"

  case "$name" in
    launch.sh)    stdin=$'n\n1\n\n\n1\n\n\nn\nprobeproj\n' ;;
    workspace.sh) stdin=$'1\nn\n' ;;
  esac
  ( cd "$tmp" && VM_REC="$tmp/.validated" PANE_REC="$tmp/.panes" PATH="$tmp/bin:$PATH" \
      bash "$name" >/dev/null 2>&1 <<< "$stdin" )
  printf '%s' "$tmp"
}

validated() { # $1 = tmp, $2 = key e.g. MODEL_1
  [ -f "$1/.validated" ] || return 0
  sed -n "s/^$2=//p" "$1/.validated" | head -1
}
pane_field() { # $1 = tmp, $2 = agent number, $3 = model|effort
  local line
  line=$(/usr/bin/grep -m1 "AGENT_NUMBER=$2 " "$1/.panes" 2>/dev/null) || return 0
  case "$3" in
    model)  printf '%s' "$line" | sed -n "s/.*--model '\([^']*\)'.*/\1/p" ;;
    effort) printf '%s' "$line" | sed -n 's/.*--effort \([A-Za-z]*\).*/\1/p' ;;
  esac
}

# Returns 0 when every validated string matches the pane it gates.
check_launcher() { # $1 = tmp dir, $2 = label, $3 = quiet|loud
  local tmp=$1 label=$2 mode=$3 n v p rc=0
  for n in 1 2; do
    for f in model effort; do
      case "$f" in model) key=MODEL_$n ;; effort) key=EFFORT_$n ;; esac
      v=$(validated "$tmp" "$key")
      p=$(pane_field "$tmp" "$n" "$f")
      if [ -z "$v" ]; then
        rc=1
        [ "$mode" = loud ] && bad "$label: $key was validated as an empty string, so the gate checked nothing"
      elif [ "$v" != "$p" ]; then
        rc=1
        [ "$mode" = loud ] && bad "$label: validated $key='$v' but pane $n launches '$p'"
      else
        [ "$mode" = loud ] && ok "$label: $key='$v' is the string pane $n actually launches"
      fi
    done
  done
  return $rc
}

for L in launch.sh workspace.sh; do
  echo "--- $L: every validated string is the string the pane launches ---"
  T=$(run_launcher "$L" "$REPO/$L")
  if [ ! -s "$T/.panes" ]; then
    bad "$L: harness problem, no panes were created"
  elif [ ! -s "$T/.validated" ]; then
    bad "$L: validate_models was never called"
  else
    check_launcher "$T" "$L" loud
  fi
  rm -rf "$T"
done

# Rebuild the pre-fix ordering FROM the current file so the control cannot go stale.
# Without this the check above could rot into a tautology and nobody would know.
echo "--- control: the check MUST fail when validation moves back before assignment ---"
REG=$(mktemp)
if python3 - "$REPO/workspace.sh" "$REG" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
gate = s[s.index('if ! validate_models'):s.index('fi\n', s.index('if ! validate_models')) + 3]
assign_start = s.index('ORCH_MODEL=')
assign = s[assign_start:s.index('\n', s.index('WORKER_MODEL=')) + 1]
if s.count(gate) != 1 or s.count(assign) != 1 or s.index(assign) > s.index(gate):
    sys.exit("control could not be built: workspace.sh no longer assigns before it validates")
open(dst, 'w').write(s.replace(assign, '', 1).replace(gate, gate + assign, 1))
PY
then
  T=$(run_launcher workspace.sh "$REG")
  if [ ! -s "$T/.panes" ]; then
    bad "control: regressed copy created no panes, so this proves nothing"
  elif check_launcher "$T" regressed quiet; then
    bad "control: regressed copy PASSED, so this test cannot detect the defect it exists for"
  else
    ok "regressed copy validates strings the panes do not use, and the check catches it"
  fi
  rm -rf "$T"
else
  bad "could not build the regressed control"
fi
rm -f "$REG"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
