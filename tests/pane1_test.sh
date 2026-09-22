#!/usr/bin/env bash
# Pane 1 is wired differently from the workers: restricted tool set, and NO thoroughness
# prompt (the hook supplies pane 1's terse delegate-and-decide prompt instead, so there
# is exactly one source of truth for per-pane prompts).
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has() { /usr/bin/grep -q -- "$2" <<< "$1"; }

echo "--- the orchestrator flags are defined ONCE, not copied per launcher ---"
n=$(/usr/bin/grep -rl 'ORCH_TOOL_FLAGS=' tools launch.sh restart-swarm.sh workspace.sh 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = "1" ] && ok "ORCH_TOOL_FLAGS assigned in exactly one file" || bad "assigned in $n files (duplication)"
src=$(/usr/bin/grep -rh 'ORCH_TOOL_FLAGS=' tools 2>/dev/null | head -1)
has "$src" "--tools Read,Write,Edit,Bash,Skill" && ok "approved tool list, Skill included" || bad "tool list wrong: $src"
has "$src" "--strict-mcp-config" && ok "carries --strict-mcp-config" || bad "missing --strict-mcp-config"
has "$src" "--settings" && ok "carries a --settings file (the read deny)" || bad "no --settings file: $src"
has "$src" "pane1-settings.json" && ok "points at tools/pane1-settings.json" || bad "wrong settings path: $src"
# Grepping the literal is not enough: an unset variable in it still greps clean while
# every pane 1 launch dies with "Settings file not found". EXPAND it and check the path.
expanded=$(bash -c 'source tools/launcher-common.sh; printf "%s" "$ORCH_TOOL_FLAGS"')
sp=$(printf '%s' "$expanded" | sed -n 's/.*--settings \([^ ]*\).*/\1/p')
case "$sp" in
  /*) ok "the settings path expands to an absolute path ($sp)" ;;
  *)  bad "the settings path did not expand to an absolute path: '$sp'" ;;
esac
[ -f "$sp" ] && ok "the expanded settings path exists on disk" || bad "the expanded settings path does not exist: '$sp'"
case "$expanded" in *'$'*) bad "ORCH_TOOL_FLAGS still contains an unexpanded variable: $expanded" ;; *) ok "no unexpanded variables remain" ;; esac

echo "--- the deny file itself, including the three fail-open traps from the spec ---"
PS=tools/pane1-settings.json
[ -f "$PS" ] && ok "$PS exists" || bad "$PS missing"
git check-ignore -q "$PS" 2>/dev/null && bad "$PS is gitignored, so a clone would launch without it" || ok "$PS is not gitignored"
python3 -c "import json;json.load(open('$PS'))" 2>/dev/null && ok "parses as JSON (a malformed file silently disables the whole deny list)" || bad "$PS is not valid JSON"
if python3 -c "import json;d=json.load(open('$PS'));import sys;sys.exit(0 if d['permissions']['deny'] else 1)" 2>/dev/null; then
  ok "has a non-empty permissions.deny list"
else bad "no deny entries, the file would be inert"; fi
while IFS= read -r e; do
  case "$e" in
    *'{'*) bad "deny entry uses brace alternation, which is SILENTLY IGNORED: $e" ;;
    Read\(//*) ok "deny entry uses the // prefix: $e" ;;
    *) bad "deny entry is not a // prefixed Read rule, single-slash is silently inert: $e" ;;
  esac
done < <(python3 -c "import json;[print(x) for x in json.load(open('$PS'))['permissions']['deny']]" 2>/dev/null)

echo "--- nothing claims this is containment ---"
body=$(cat "$PS")
if /usr/bin/grep -qiE 'speed bump' <<< "$body"; then ok "the file labels itself a speed bump"; else bad "the file does not carry the agreed label"; fi
# "not containment" is the agreed label, so strip the disclaimed form before looking
# for a positive claim; otherwise the file gets flagged for correctly disclaiming it.
stripped=$(printf '%s' "$body" | sed -E 's/not containment//gi; s/does NOT[^.]*\.//g')
if /usr/bin/grep -qiE 'sandbox|containment|prevents? read|cannot read|fully block' <<< "$stripped"; then
  bad "the file makes a positive containment claim"
else ok "the file makes no containment claim beyond the speed-bump label"; fi
has "$body" 'does NOT' && ok "the file states its own limits inline" || bad "the file does not state its limits"

echo "--- launch.sh: pane 1 restricted, workers untouched ---"
c1=$(/usr/bin/grep -m1 '^CMD1=' launch.sh)
has "$c1" 'ORCH_TOOL_FLAGS' && ok "CMD1 applies the orchestrator flags" || bad "CMD1 lacks them: $c1"
case "$c1" in *THINK_FLAG*) bad "CMD1 still carries THINK_FLAG; the hook supplies pane 1's prompt" ;; *) ok "CMD1 does not carry THINK_FLAG" ;; esac
for n in 2 3 4; do
  c=$(/usr/bin/grep -m1 "^CMD$n=" launch.sh)
  has "$c" 'THINK_FLAG' && ok "CMD$n keeps THINK_FLAG" || bad "CMD$n lost THINK_FLAG: $c"
  case "$c" in *ORCH_TOOL_FLAGS*) bad "CMD$n wrongly restricted like pane 1" ;; *) ok "CMD$n is not restricted" ;; esac
done

echo "--- workspace.sh and restart-swarm.sh keep the same split ---"
o=$(/usr/bin/grep -m1 '^CMD_ORCH=' workspace.sh); w=$(/usr/bin/grep -m1 '^CMD_WORKER=' workspace.sh)
has "$o" 'ORCH_TOOL_FLAGS' && ok "CMD_ORCH applies the flags" || bad "CMD_ORCH lacks them: $o"
case "$o" in *THINK_FLAG*) bad "CMD_ORCH still carries THINK_FLAG" ;; *) ok "CMD_ORCH drops THINK_FLAG" ;; esac
has "$w" 'THINK_FLAG' && ok "CMD_WORKER keeps THINK_FLAG" || bad "CMD_WORKER lost THINK_FLAG"
blk=$(sed -n '/^launch_line_for()/,/^}/p' restart-swarm.sh)
has "$blk" 'ORCH_TOOL_FLAGS' && ok "launch_line_for restricts agent 1 on refresh" || bad "a refresh would relaunch pane 1 unrestricted"
has "$blk" 'THINK_PROMPT' && ok "launch_line_for keeps the worker prompt" || bad "workers lost the thorough prompt on refresh"
/usr/bin/grep -qE 'a" = 1' <<< "$blk" && ok "launch_line_for branches on the agent number" || bad "no per-agent branch"

echo "--- the preflight refuses a malformed deny file (it would silently do nothing) ---"
bd=$(mktemp -d); mkdir -p "$bd/swarms/220" "$bd/tools" "$bd/.claude/hooks"
cp -R "$REPO/.claude/hooks/." "$bd/.claude/hooks/"; cp "$REPO/.claude/settings.json" "$bd/.claude/"
printf 'demo' > "$bd/swarms/220/ACTIVE_PROJECT"
cp "$REPO/tools/pane1-settings.json" "$bd/tools/"
( source tools/preflight-hook.sh; preflight_hook "$bd/.claude/settings.json" "$bd" 220 1 ) >/dev/null 2>&1   && ok "valid deny file passes" || bad "valid deny file was refused"
printf '{ "permissions": { "deny": [ ,, ] }\n' > "$bd/tools/pane1-settings.json"
if ( source tools/preflight-hook.sh; preflight_hook "$bd/.claude/settings.json" "$bd" 220 1 ) >/dev/null 2>&1; then
  bad "malformed deny file PASSED the gate; it would silently disable every deny rule"
else ok "malformed deny file refused"; fi
rm -rf "$bd"

echo "--- model and effort values are validated before panes start ---"
for f in launch.sh restart-swarm.sh workspace.sh; do
  v=$(/usr/bin/grep -n 'validate_models' "$f" | head -1 | cut -d: -f1)
  if [ -z "$v" ]; then bad "$f: never validates models/efforts"; continue; fi
  ok "$f: calls the validator"
  case "$f" in
    restart-swarm.sh) p=$(/usr/bin/grep -n 'Phase 3' "$f" | head -1 | cut -d: -f1) ;;
    *)                p=$(/usr/bin/grep -n 'export AGENT_NUMBER=1' "$f" | head -1 | cut -d: -f1) ;;
  esac
  [ -n "$p" ] && [ "$v" -lt "$p" ] && ok "$f: validation ($v) precedes pane work ($p)" || bad "$f: validation ($v) does not precede pane work ($p)"
done

echo "--- the validator actually rejects a bad value (control) ---"
printf 'MODEL_1=claude-opus-5\nEFFORT_1=high\n' | python3 tools/model-lookup.py --check - >/dev/null 2>&1 \
  && ok "good model/effort pair accepted" || bad "validator rejected a valid pair"
printf 'MODEL_1=claude-opus-9\nEFFORT_1=high\n' | python3 tools/model-lookup.py --check - >/dev/null 2>&1 \
  && bad "validator accepted a bogus model id" || ok "bogus model id rejected"
printf 'MODEL_1=claude-opus-5\nEFFORT_1=ludicrous\n' | python3 tools/model-lookup.py --check - >/dev/null 2>&1 \
  && bad "validator accepted a bogus effort" || ok "bogus effort rejected (the CLI would have downgraded silently)"

echo "--- the launchers' OWN shipped defaults must pass their own validator ---"
mk() { printf 'MODEL_1=%s\nEFFORT_1=%s\n' "$1" "$2"; }
ds=$(/usr/bin/grep -m1 'DEFAULT_STRONG_MODEL=' launch.sh | cut -d'"' -f2)
dc=$(/usr/bin/grep -m1 'DEFAULT_CHEAP_MODEL=' launch.sh | cut -d'"' -f2)
for m in "$ds" "$dc"; do
  if mk "$m" high | python3 tools/model-lookup.py --check - >/dev/null 2>&1; then ok "launch.sh default $m is valid"
  else bad "launch.sh ships default $m, which its own validator refuses"; fi
done
while IFS= read -r m; do
  [ -n "$m" ] || continue
  if mk "$m" high | python3 tools/model-lookup.py --check - >/dev/null 2>&1; then ok "picker option $m is valid"
  else bad "picker offers $m, which its own validator refuses"; fi
done < <(/usr/bin/grep -m1 'MODEL_CHOICES=' launch.sh | tr '()"' '\n\n\n' | /usr/bin/grep '^claude-')

echo "--- pane 1's output rules reach the hook's injected prompt ---"
run1() { AGENT_NUMBER="$1" SWARM_ID=220 .claude/hooks/startup.sh <<< '{"session_id":"t","source":"startup","cwd":"'"$REPO"'"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'; }
a1=$(run1 1); a2=$(run1 2)
has "$a1" '150 words' && ok "agent 1 carries the 150-word reply limit" || bad "agent 1 has no word limit"
case "$a2" in *"150 words"*) bad "workers wrongly got the orchestrator word limit" ;; *) ok "workers do not carry the word limit" ;; esac
has "$a1" 'deliverable' && ok "agent 1 carries the dispatch format" || bad "agent 1 has no dispatch format"
if /usr/bin/grep -qiE 'lead with' <<< "$a1"; then ok "agent 1 told to lead with the inference and decision"; else bad "agent 1 not told what to lead with"; fi
if /usr/bin/grep -qiE 'index\.md' <<< "$a1"; then ok "agent 1 carries the index.md decision length rule"; else bad "no index.md rule"; fi

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
