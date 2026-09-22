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
mksandbox() { # $1 = script, $2 = env|env-nomodels|noenv [, $3 = SKIP_PERMS [, $4 = strict|permissive]]
  local script=$1 want_env=$2 perms=${3:-y} validator=${4:-strict} t
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
  if [ "$validator" = permissive ]; then
    # What tools/model-lookup.py does TODAY: an empty id is "the launcher falls back
    # to its default" and passes. The refusal must not be delegated to it.
    cat > "$t/tools/model-lookup.py" <<'STUB'
#!/usr/bin/env bash
d=$(cd "$(dirname "$0")" && pwd)
echo call >> "$d/../validator-calls"
cat >/dev/null
exit 0
STUB
  else
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
  fi
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

withproject() { # give the sandbox work logs, so Phase 1 does not take its no-op path
  mkdir -p "$1/projects/probeproj"
  printf '# log\n' > "$1/projects/probeproj/agent1.md"
}

OUT=""; RC=0
run() { # $1 = sandbox dir, rest = restart-swarm.sh args after the swarm id
  local t=$1; shift
  OUT=$( cd "$t" && env -u SWARM_ID -u AGENT_NUMBER bash restart-swarm.sh "$SID" --dry-run "$@" 2>&1 ); RC=$?
}
run_skipping_preflight() {
  local t=$1; shift
  OUT=$( cd "$t" && env -u SWARM_ID -u AGENT_NUMBER SWARM_SKIP_PREFLIGHT=1 \
           bash restart-swarm.sh "$SID" --dry-run "$@" 2>&1 ); RC=$?
}
# Two predicates, because no single signal works for both directions.
# validate_models execs model-lookup.py only for non-empty ids, so the stub's marker is
# proof it ran but its absence is not proof it did not: for the all-empty ids a soft
# refresh produces, validate_models refuses in bash and never reaches the stub.
validator_ran() { [ -f "$1/validator-calls" ]; }
validation_attempted() { # $1 = sandbox, $2 = output
  [ -f "$1/validator-calls" ] && return 0
  case "$2" in *"model-validated"*|*"LAUNCH REFUSED: empty value for"*) return 0 ;; esac
  return 1
}

# Controls are rebuilt FROM the current file so they cannot go stale.
regress() { # $1 = which, $2 = dest
  python3 - "$REPO/restart-swarm.sh" "$1" "$2" <<'PY'
import sys
src, which, dst = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src).read()
if which == "no-refusal":
    head = """  if [ ! -f "$SWARM_DIR/launch.env" ]; then
    printf 'LAUNCH REFUSED"""
    i = s.find(head)
    if i < 0: sys.exit("control anchor moved: the missing-launch.env guard")
    j = s.find("\n  fi\n", i)
    if j < 0: sys.exit("control anchor moved: end of the missing-launch.env guard")
    s = s[:i] + s[j+6:]
elif which == "late-refusal":
    head = 'if [ "$MODE" = "hard" ] && [ "$SAVE_ONLY" = 0 ]; then'
    i = s.find(head)
    if i < 0: sys.exit("control anchor moved: the replay-parameter block")
    j = s.find("\nfi\n", i)
    if j < 0: sys.exit("control anchor moved: end of the replay-parameter block")
    block = s[i:j+4]
    s = s[:i] + s[j+4:]
    anchor = "# Full shell line that relaunches a given agent in its pane (--hard).\n"
    if s.count(anchor) != 1: sys.exit("control anchor moved: launch_line_for")
    s = s.replace(anchor, block + "\n" + anchor, 1)
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
elif which == "no-validation":
    old = """  if ! validate_models "$_mv" "$_eng"; then
    exit 1
  fi
"""
    if s.count(old) != 1: sys.exit("control anchor moved: the validate_models call")
    s = s.replace(old, "", 1)
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

echo "--- and it refuses before asking four agents to checkpoint ---"
t=$(mksandbox "$REPO/restart-swarm.sh" noenv); withproject "$t"; run "$t" --hard
case "$OUT" in *"Phase 1"*) bad "agents were asked to checkpoint for a restart that cannot happen" ;;
  *) ok "no checkpoint phase ran" ;; esac
case "$OUT" in *"Phase 2"*) bad "it snapshotted before refusing" ;; *) ok "no snapshot phase ran" ;; esac
rm -rf "$t"

echo "--- control: with the refusal neutered, that assertion goes red ---"
REG=$(mktemp)
if regress no-refusal "$REG"; then
  t=$(mksandbox "$REG" noenv); withproject "$t"; run "$t" --hard
  case "$OUT" in *"LAUNCH REFUSED"*"/swarms/$SID/launch.env"*)
      bad "neutered copy still printed the launch.env refusal, so the check proves nothing" ;;
    *)  ok "neutered copy does not print it (the check is keyed on the refusal, not on any failure)" ;; esac
  rm -rf "$t"
else bad "could not build the no-refusal control"; fi
rm -f "$REG"

echo "--- control: moved back below the checkpoint, the earliness checks go red ---"
REG=$(mktemp)
if regress late-refusal "$REG"; then
  t=$(mksandbox "$REG" noenv); withproject "$t"; run "$t" --hard
  case "$OUT" in *"Phase 1"*) ok "the late copy does reach the checkpoint phase" ;;
    *) bad "the late copy skipped Phase 1 anyway, so the earliness checks prove nothing" ;; esac
  case "$OUT" in *"LAUNCH REFUSED"*"/swarms/$SID/launch.env"*)
      ok "and still refuses, so earliness and refusal are independent assertions" ;;
    *) bad "the late copy did not refuse at all, so this control tests the wrong thing" ;; esac
  rm -rf "$t"
else bad "could not build the late-refusal control"; fi
rm -f "$REG"

echo "--- --hard with launch.env replays it (the refusal is not unconditional) ---"
t=$(mksandbox "$REPO/restart-swarm.sh" env); run "$t" --hard
[ "$RC" -eq 0 ] && ok "hard with launch.env succeeds (rc=$RC)" || bad "hard with launch.env failed: $OUT"
case "$OUT" in *"--model 'claude-opus-5'"*) ok "pane 1 relaunches on the recorded model" ;;
  *) bad "recorded model absent from the relaunch line: $OUT" ;; esac
validator_ran "$t" && ok "hard is model-validated" || bad "hard skipped model validation"
rm -rf "$t"

echo "--- control: with the validate_models call removed, the hard check goes red ---"
REG=$(mktemp)
if regress no-validation "$REG"; then
  t=$(mksandbox "$REG" env); run "$t" --hard
  validator_ran "$t" && bad "still reported as validated with no validate_models call, so that check proves nothing" \
                        || ok "reports not validated (the hard check is keyed on the call, not on the gating report)"
  rm -rf "$t"
else bad "could not build the no-validation control"; fi
rm -f "$REG"

echo "--- --hard with launch.env but no MODEL_n invents nothing ---"
t=$(mksandbox "$REPO/restart-swarm.sh" env-nomodels); run "$t" --hard
[ "$RC" -ne 0 ] && ok "empty model is refused, not defaulted (rc=$RC)" || bad "empty model launched anyway"
case "$OUT" in *claude-fable*|*claude-opus*|*claude-sonnet*) bad "a model id was invented: $OUT" ;;
  *) ok "no model id appears anywhere in the run" ;; esac
rm -rf "$t"

echo "--- the empty-model refusal is local, not delegated to a skippable validator ---"
t=$(mksandbox "$REPO/restart-swarm.sh" env-nomodels y permissive); withproject "$t"
run_skipping_preflight "$t" --hard
case "$OUT" in *"Phase 1"*) bad "an unreplayable launch.env still cost four agents a checkpoint" ;;
  *) ok "an incomplete launch.env is refused before Phase 1 too" ;; esac
[ "$RC" -ne 0 ] && ok "refused with a permissive validator and SWARM_SKIP_PREFLIGHT=1 (rc=$RC)" \
                || bad "an empty model survived both, so the check is delegated"
case "$OUT" in *"--model ''"*) bad "a pane was relaunched on an empty model" ;;
  *) ok "no pane command carries an empty model" ;; esac
case "$OUT" in *MODEL_1*) ok "the refusal names the field that is empty" ;;
  *) bad "the refusal does not say which value is missing: $OUT" ;; esac
rm -rf "$t"

echo "--- soft needs no launch.env and is not model-validated ---"
t=$(mksandbox "$REPO/restart-swarm.sh" noenv); run "$t"
[ "$RC" -eq 0 ] && ok "soft without launch.env succeeds (rc=$RC)" || bad "soft without launch.env failed: $OUT"
case "$OUT" in *"/clear"*) ok "soft still refreshes the panes" ;; *) bad "soft refreshed nothing: $OUT" ;; esac
validation_attempted "$t" "$OUT" && bad "soft called the model validator on empty ids" || ok "soft did not call the model validator"
rm -rf "$t"

echo "--- control: with the hard-only guard removed, soft goes red ---"
REG=$(mktemp)
if regress no-mode-guard "$REG"; then
  t=$(mksandbox "$REG" noenv); run "$t"
  validation_attempted "$t" "$OUT" && ok "unguarded copy does validate in soft (the check can fail)" \
               || bad "unguarded copy still skipped the validator, so the check proves nothing"
  [ "$RC" -ne 0 ] && ok "and a strict validator then fails the soft refresh outright (rc=$RC)" \
                  || bad "unguarded copy validated but still exited 0, so the harm is unproven"
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
validation_attempted "$t" "$OUT" && bad "save-only called the model validator" || ok "save-only did not call the model validator"
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
