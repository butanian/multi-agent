#!/usr/bin/env bash
# Per-pane engine selection. Default must be claude so existing behaviour is untouched.
# The capability is built and left unused: no Codex pane is stood up by this work.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has() { /usr/bin/grep -q -- "$2" <<< "$1"; }

if ! /usr/bin/grep -q 'engine_cmd' tools/launcher-common.sh 2>/dev/null; then
  bad "tools/launcher-common.sh has no engine_cmd"; echo; echo "  0 passed, 1 failed"; exit 1
fi
source tools/launcher-common.sh

echo "--- claude stays the default, and its command is unchanged ---"
c=$(engine_cmd 2 claude "claude-opus-5" "high" "--dangerously-skip-permissions" "--append-system-prompt 'X'")
case "$c" in "claude --model 'claude-opus-5' --effort high"*) ok "claude command keeps its existing shape" ;;
  *) bad "claude command changed shape: $c" ;; esac
has "$c" "--dangerously-skip-permissions" && ok "claude command keeps the perms flag" || bad "perms flag lost: $c"
has "$c" "--append-system-prompt 'X'" && ok "claude command keeps the extra flags" || bad "extra flags lost: $c"
d=$(engine_cmd 2 "" "claude-opus-5" "high" "" "")
case "$d" in claude*) ok "an empty engine defaults to claude" ;; *) bad "empty engine did not default to claude: $d" ;; esac

echo "--- codex gets the invocation R2 actually verified ---"
x=$(engine_cmd 3 codex "gpt-5.6-sol" "xhigh" "--dangerously-skip-permissions" "--append-system-prompt 'X'")
case "$x" in codex*) ok "codex command invokes codex" ;; *) bad "codex command does not invoke codex: $x" ;; esac
for f in "--no-alt-screen" "-s danger-full-access" "-a never" "-m 'gpt-5.6-sol'" "model_reasoning_effort"; do
  has "$x" "$f" && ok "codex command carries $f" || bad "codex command missing $f: $x"
done
has "$x" "xhigh" && ok "codex command carries the effort value" || bad "effort value missing: $x"
case "$x" in *--dangerously-skip-permissions*) bad "codex command carries a claude-only flag" ;; *) ok "no claude-only flags leak into the codex command" ;; esac
case "$x" in *--append-system-prompt*) bad "codex command carries claude's --append-system-prompt" ;; *) ok "claude's system-prompt flag does not leak" ;; esac
has "$x" "AGENTS.md" && ok "codex bootstrap points at AGENTS.md" || bad "codex bootstrap does not mention AGENTS.md: $x"
has "$x" "Agent 3" && ok "codex bootstrap names the agent (no readable banner exists)" || bad "codex bootstrap does not name the agent: $x"

echo "--- an unknown engine must be refused, not silently treated as claude ---"
if u=$(engine_cmd 2 sonnet-cli "m" "high" "" "" 2>&1); then
  bad "unknown engine accepted, producing: $u"
else
  ok "unknown engine refused"
  case "$u" in *[Ff]ix:*) ok "refusal states a remediation" ;; *) bad "refusal has no remediation: $u" ;; esac
fi

echo "--- the launchers no longer hardcode the engine ---"
for f in launch.sh restart-swarm.sh; do
  n=$(/usr/bin/grep -c '"claude --model' "$f" 2>/dev/null || true)
  [ "$n" = "0" ] && ok "$f builds no hardcoded claude command" || bad "$f still hardcodes $n claude command(s)"
  /usr/bin/grep -q 'engine_cmd' "$f" && ok "$f uses engine_cmd" || bad "$f does not use engine_cmd"
done

echo "--- ENGINE_N defaults to claude and is persisted ---"
/usr/bin/grep -qE 'ENGINE_1=\$\{ENGINE_1:-claude\}|ENGINE_1="\$\{ENGINE_1:-claude\}"' launch.sh \
  && ok "launch.sh defaults ENGINE_1 to claude" || bad "launch.sh does not default ENGINE_1 to claude"
/usr/bin/grep -q "ENGINE_1=" launch.sh && ok "launch.sh records ENGINE_1 for restart" || bad "ENGINE_1 not persisted"

echo "--- model validation must skip non-claude panes ---"
# A codex model id is not a claude model id, so validating it would refuse every
# mixed-engine launch. This is the gate-wired-to-the-wrong-thing shape again.
if out=$(validate_models "MODEL_2=gpt-5.6-sol
EFFORT_2=xhigh" "claude codex claude claude" 2>&1); then
  ok "a codex pane's model is not validated against the claude catalog"
else
  bad "validate_models refused a codex model: $out"
fi
if out=$(validate_models "MODEL_1=claude-opus-9
EFFORT_1=high" "claude claude claude claude" 2>&1); then
  bad "validate_models accepted a bogus CLAUDE model when engines were passed"
else
  ok "a claude pane's model is still validated"
fi

echo "--- an excluded codex pane must be VISIBLE, never silently ungated ---"
if ! /usr/bin/grep -q 'report_engine_gating' tools/launcher-common.sh; then
  bad "no report_engine_gating; an excluded pane would be silent"
else
  out=$(report_engine_gating "claude codex claude claude" 2>&1)
  has "$out" "pane 2" && ok "names the excluded pane" || bad "does not name the excluded pane: $out"
  has "$out" "codex" && ok "names its engine" || bad "does not name the engine: $out"
  /usr/bin/grep -qi 'not preflighted' <<< "$out" && ok "says it is not preflighted" || bad "does not say it is unpreflighted: $out"
  /usr/bin/grep -qi 'not model-validated' <<< "$out" && ok "says it is not model-validated" || bad "does not say it is unvalidated: $out"
  case "$out" in *"pane 1"*) bad "listed a claude pane as excluded" ;; *) ok "does not list claude panes as excluded" ;; esac

  allc=$(report_engine_gating "claude claude claude claude" 2>&1)
  [ -n "$(printf '%s' "$allc" | tr -d '[:space:]')" ] && ok "all-claude still states the gating status" \
    || bad "all-claude printed nothing, so a reader cannot tell gating ran"
  /usr/bin/grep -qi 'not preflighted' <<< "$allc" && bad "all-claude wrongly reports an exclusion" \
    || ok "all-claude reports no exclusions"
fi

echo "--- and the launchers actually call it ---"
for f in launch.sh restart-swarm.sh; do
  /usr/bin/grep -q 'report_engine_gating' "$f" && ok "$f reports engine gating" || bad "$f never reports engine gating"
done

echo "--- a codex pane must not get two startup commands ---"
# engine_cmd already hands a Codex pane a positional bootstrap prompt, so the launcher's
# blanket startup kick would be a second, racing instruction.
k=$(/usr/bin/grep -c 'send-to-agent.sh [0-9] "Execute your startup protocol' launch.sh 2>/dev/null || true)
[ "$k" = "0" ] && ok "launch.sh no longer kicks panes unconditionally" \
  || bad "launch.sh still sends $k unconditional kicks, so a codex pane would get two starts"
# Behavioural, not structural: run launch.sh with pane 2 on codex under a stubbed
# osascript and a logging send-to-agent.sh, then check who actually got kicked.
kicked=$(
  t=$(mktemp -d)
  cp launch.sh "$t/"; mkdir -p "$t/bin" "$t/projects" "$t/.claude/hooks"
  cp -R tools "$t/tools"; cp .claude/settings.json "$t/.claude/"
  cp .claude/hooks/startup.sh .claude/hooks/startup.py "$t/.claude/hooks/"
  python3 - "$t/.claude/settings.json" "$t" <<'PS'
import json,sys
d=json.load(open(sys.argv[1]))
for g in d.get("hooks",{}).get("SessionStart",[]):
    for h in g.get("hooks",[]):
        if h.get("type")=="command": h["command"]=sys.argv[2]+"/.claude/hooks/startup.sh"
json.dump(d,open(sys.argv[1],"w"))
PS
  printf '#!/usr/bin/env bash\necho "A,B,C,D"\n' > "$t/bin/osascript"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$t/bin/sleep"
  printf '#!/usr/bin/env bash\necho "$1" >> "$t/kicks"\nexit 0\n' > "$t/send-to-agent.sh"
  sed -i '' "s|\$t/kicks|$t/kicks|" "$t/send-to-agent.sh" 2>/dev/null || true
  chmod +x "$t/bin/osascript" "$t/bin/sleep" "$t/send-to-agent.sh"
  ( cd "$t" && ENGINE_2=codex MODEL_2=gpt-5.6-sol EFFORT_2=xhigh PATH="$t/bin:$PATH" \
      bash launch.sh >/dev/null 2>&1 <<< $'y\n1\n\n\n1\n\n\nn\nkicktest\n' ) || true
  tr '\n' ' ' < "$t/kicks" 2>/dev/null
  rm -rf "$t"
)
case " $kicked " in *" 2 "*) bad "the codex pane WAS kicked, so it gets two starts (kicked: $kicked)" ;;
  *) ok "the codex pane was not kicked (kicked: ${kicked:-none})" ;; esac
for n in 1 3 4; do
  case " $kicked " in *" $n "*) ok "claude pane $n was still kicked" ;;
    *) bad "claude pane $n was NOT kicked, the guard is too broad (kicked: $kicked)" ;; esac
done

echo "--- AGENTS.md must not overstate the posture it gives pane 1 ---"
# The codex branch does not apply ORCH_TOOL_FLAGS, so a Codex pane 1 is NOT restricted
# the way a Claude pane 1 is. Saying "same posture" without qualification is false.
if /usr/bin/grep -q 'same posture' AGENTS.md; then
  # scope to the paragraph, a file-wide grep matched an unrelated "does not apply"
  para=$(awk '/same posture/{f=1} f{print} f&&/^$/{exit}' AGENTS.md)
  /usr/bin/grep -qiE 'tool restriction|ORCH_TOOL_FLAGS|not restricted' <<< "$para" \
    && ok "the posture claim is qualified in its own paragraph" \
    || bad "AGENTS.md claims the same posture without noting pane 1 loses the tool restriction"
else
  ok "no unqualified same-posture claim"
fi

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
