#!/usr/bin/env bash
# restart-swarm.sh mode contract: --hard replays swarms/N/launch.env or refuses,
# and a soft refresh builds no pane commands so it must not be model-validated.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD
SID=900
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

# The validator stub stands in for the strict validator S222-A is landing (D71): it
# records every call and refuses an empty id, which is what an absent default now yields.
mksandbox() { # $1 = script under test, $2 = env|env-nomodels|noenv [, $3 = SKIP_PERMS]
  local script=$1 want_env=$2 perms=${3:-y} t
  t=$(mktemp -d)
  cp "$script" "$t/restart-swarm.sh"
  cp -R "$REPO/tools" "$t/tools"
  mkdir -p "$t/.claude/hooks" "$t/swarms/$SID"
  cp "$REPO/.claude/settings.json" "$t/.claude/settings.json"
  cp "$REPO/.claude/hooks/startup.sh" "$REPO/.claude/hooks/startup.py" "$t/.claude/hooks/"
  python3 - "$t/.claude/settings.json" "$t" <<'PS'
import json,sys
p,root=sys.argv[1],sys.argv[2]
d=json.load(open(p))
for g in d.get("hooks",{}).get("SessionStart",[]):
    for h in g.get("hooks",[]):
        if h.get("type")=="command":
            h["command"]=root+"/.claude/hooks/startup.sh"
json.dump(d,open(p,"w"))
PS
  printf '#!/usr/bin/env bash\nexit 0\n' > "$t/send-to-agent.sh"
  cat > "$t/tools/model-lookup.py" <<'STUB'
#!/usr/bin/env bash
d=$(cd "$(dirname "$0")" && pwd)
echo call >> "$d/../validator-calls"
rc=0
while IFS= read -r l; do
  case "$l" in *=) echo "  $l  (empty, refused)"; rc=1 ;; esac
done
exit $rc
STUB
  chmod +x "$t/send-to-agent.sh" "$t/tools/model-lookup.py"
  cat > "$t/swarms/$SID/pane-config.sh" <<'PC'
AGENT_1_SESSION="UUID-A1"
AGENT_2_SESSION="UUID-A2"
AGENT_3_SESSION="UUID-A3"
AGENT_4_SESSION="UUID-A4"
PC
  printf 'probeproj' > "$t/swarms/$SID/ACTIVE_PROJECT"
  if [ "$want_env" = env ]; then
    cat > "$t/swarms/$SID/launch.env" <<PE
MODEL_1='claude-opus-5'
MODEL_2='claude-sonnet-5'
MODEL_3='claude-sonnet-5'
MODEL_4='claude-sonnet-5'
EFFORT_1='xhigh'
EFFORT_2='high'
EFFORT_3='high'
EFFORT_4='high'
ENGINE_1='claude'
ENGINE_2='claude'
ENGINE_3='claude'
ENGINE_4='claude'
SKIP_PERMS='$perms'
PE
  elif [ "$want_env" = env-nomodels ]; then
    cat > "$t/swarms/$SID/launch.env" <<'PE'
ENGINE_1='claude'
ENGINE_2='claude'
ENGINE_3='claude'
ENGINE_4='claude'
SKIP_PERMS='y'
PE
  fi
  echo "$t"
}

OUT=""; RC=0
run() { # $1 = sandbox dir, rest = restart-swarm.sh args after the swarm id
  local t=$1; shift
  OUT=$( cd "$t" && env -u SWARM_ID -u AGENT_NUMBER bash restart-swarm.sh "$SID" --dry-run "$@" 2>&1 ); RC=$?
}
called() { [ -f "$1/validator-calls" ]; }

# Controls are rebuilt FROM the current file so they cannot go stale.
regress() { # $1 = which, $2 = dest
  python3 - "$REPO/restart-swarm.sh" "$1" "$2" <<'PY'
import sys
src, which, dst = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src).read()
if which == "no-refusal":
    old = """  else
    printf 'LAUNCH REFUSED"""
    i = s.find(old)
    if i < 0: sys.exit("control anchor moved: the launch.env refusal")
    j = s.find("\n  fi\n", i)
    if j < 0: sys.exit("control anchor moved: end of the refusal arm")
    s = s[:i] + "  else\n    :\n" + s[j+1:]
elif which == "no-mode-guard":
    old = """if [ "$MODE" = "hard" ]; then
  report_engine_gating "$_eng"
  if ! validate_models "$_mv" "$_eng"; then
    exit 1
  fi
fi
"""
    new = """report_engine_gating "$_eng"
if ! validate_models "$_mv" "$_eng"; then
  exit 1
fi
"""
    if s.count(old) != 1: sys.exit("control anchor moved: the hard-only validation guard")
    s = s.replace(old, new, 1)
elif which == "trailing-status":
    old = """if [ -n "$CALLER_AGENT" ]; then
  log "  Your own pane (Agent $CALLER_AGENT) refreshes in ~${SELF_DELAY}s via the detached finisher."
fi
"""
    new = """[ -n "$CALLER_AGENT" ] && log "  Your own pane (Agent $CALLER_AGENT) refreshes in ~${SELF_DELAY}s via the detached finisher."
"""
    if s.count(old) != 1: sys.exit("control anchor moved: the final self-refresh notice")
    s = s.replace(old, new, 1)
else:
    sys.exit("unknown control")
open(dst, "w").write(s)
PY
}

echo "--- --hard without launch.env refuses, and names what is missing ---"
t=$(mksandbox "$REPO/restart-swarm.sh" noenv); run "$t" --hard
[ "$RC" -ne 0 ] && ok "refused (rc=$RC)" || bad "hard without launch.env exited 0"
case "$OUT" in *"LAUNCH REFUSED"*"/swarms/$SID/launch.env"*) ok "refusal names swarms/$SID/launch.env" ;;
  *) bad "no LAUNCH REFUSED naming launch.env: $OUT" ;; esac
case "$OUT" in *launch.sh*) ok "refusal tells the user to run launch.sh" ;; *) bad "refusal offers no fix" ;; esac
case "$OUT" in *"would type into"*) bad "it typed into a pane before refusing" ;; *) ok "no pane command was produced" ;; esac
rm -rf "$t"

echo "--- control: with the refusal neutered, that assertion goes red ---"
REG=$(mktemp)
if regress no-refusal "$REG"; then
  t=$(mksandbox "$REG" noenv); run "$t" --hard
  case "$OUT" in *"LAUNCH REFUSED"*"/swarms/$SID/launch.env"*)
      bad "neutered copy still printed the launch.env refusal, so the check proves nothing" ;;
    *)  ok "neutered copy does not print it (the check is keyed on the refusal, not on any failure)" ;; esac
  rm -rf "$t"
else bad "could not build the no-refusal control"; fi
rm -f "$REG"

echo "--- --hard with launch.env replays it (the refusal is not unconditional) ---"
t=$(mksandbox "$REPO/restart-swarm.sh" env); run "$t" --hard
[ "$RC" -eq 0 ] && ok "hard with launch.env succeeds (rc=$RC)" || bad "hard with launch.env failed: $OUT"
case "$OUT" in *"--model 'claude-opus-5'"*) ok "pane 1 relaunches on the recorded model" ;;
  *) bad "recorded model absent from the relaunch line: $OUT" ;; esac
called "$t" && ok "hard is model-validated" || bad "hard skipped model validation"
rm -rf "$t"

echo "--- --hard with launch.env but no MODEL_n invents nothing ---"
t=$(mksandbox "$REPO/restart-swarm.sh" env-nomodels); run "$t" --hard
[ "$RC" -ne 0 ] && ok "empty model is refused, not defaulted (rc=$RC)" || bad "empty model launched anyway"
case "$OUT" in *claude-fable*|*claude-opus*|*claude-sonnet*) bad "a model id was invented: $OUT" ;;
  *) ok "no model id appears anywhere in the run" ;; esac
rm -rf "$t"

echo "--- soft needs no launch.env and is not model-validated ---"
t=$(mksandbox "$REPO/restart-swarm.sh" noenv); run "$t"
[ "$RC" -eq 0 ] && ok "soft without launch.env succeeds (rc=$RC)" || bad "soft without launch.env failed: $OUT"
case "$OUT" in *"/clear"*) ok "soft still refreshes the panes" ;; *) bad "soft refreshed nothing: $OUT" ;; esac
called "$t" && bad "soft called the model validator on empty ids" || ok "soft did not call the model validator"
rm -rf "$t"

echo "--- control: with the hard-only guard removed, soft goes red ---"
REG=$(mktemp)
if regress no-mode-guard "$REG"; then
  t=$(mksandbox "$REG" noenv); run "$t"
  called "$t" && ok "unguarded copy does validate in soft (the check can fail)" \
               || bad "unguarded copy still skipped the validator, so the check proves nothing"
  rm -rf "$t"
else bad "could not build the no-mode-guard control"; fi
rm -f "$REG"

echo "--- control: the old trailing test made a clean refresh exit non-zero ---"
REG=$(mktemp)
if regress trailing-status "$REG"; then
  t=$(mksandbox "$REG" noenv); run "$t"
  [ "$RC" -ne 0 ] && ok "regressed tail reports failure on a clean run (rc=$RC), so rc=0 is a real assertion" \
                  || bad "regressed tail still exited 0, so the rc=0 checks prove nothing"
  rm -rf "$t"
else bad "could not build the trailing-status control"; fi
rm -f "$REG"

echo "--- save-only needs no launch.env either ---"
t=$(mksandbox "$REPO/restart-swarm.sh" noenv); run "$t" --save-only
[ "$RC" -eq 0 ] && ok "save-only without launch.env succeeds (rc=$RC)" || bad "save-only failed: $OUT"
called "$t" && bad "save-only called the model validator" || ok "save-only did not call the model validator"
rm -rf "$t"

echo "--- --skip-perms still means something now that launch.env is mandatory ---"
t=$(mksandbox "$REPO/restart-swarm.sh" env n); run "$t" --hard --skip-perms
case "$OUT" in *--dangerously-skip-permissions*) ok "the flag overrides SKIP_PERMS='n' in launch.env" ;;
  *) bad "the flag was swallowed by launch.env: $OUT" ;; esac
rm -rf "$t"

t=$(mksandbox "$REPO/restart-swarm.sh" env n); run "$t" --hard
case "$OUT" in *--dangerously-skip-permissions*) bad "skip-perms applied without the flag" ;;
  *) ok "control: without the flag, launch.env's 'n' is honoured" ;; esac
rm -rf "$t"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
