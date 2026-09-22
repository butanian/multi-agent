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

# HELD: pane 1's tool restriction (--tools plus --strict-mcp-config plus a --settings
# file carrying a path-scoped Read deny) lands as one piece with that deny file, per
# Aneesh's reversal of the earlier no-settings-file decision. Asserting it now would
# either fail or, worse, pass against a half-built wiring.

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
