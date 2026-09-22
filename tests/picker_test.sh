#!/usr/bin/env bash
# The model menu must come from the entitlement layer, not a literal. Swarm 220 shipped
# a picker whose four hardcoded ids were never checked against the account, so it could
# offer models the account cannot run and hide models it can.
#
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

echo "--- the tools/ contract this launcher is built on (Agent 2, harness/swarm-222-a) ---"
for v in DEFAULT_STRONG_MODEL DEFAULT_CHEAP_MODEL; do
  val=$(bash -c "source '$REPO/tools/launcher-common.sh'; printf '%s' \"\${$v:-}\"" 2>/dev/null)
  [ -n "$val" ] && ok "launcher-common.sh exports $v=$val" \
                || bad "launcher-common.sh does not define $v, so both launchers resolve it to an empty model id"
done
is_bare_list() {
  local total notid
  total=$(printf '%s\n' "$1" | /usr/bin/grep -c .)
  notid=$(printf '%s\n' "$1" | /usr/bin/grep -cvE '^[A-Za-z0-9._-]+(\[1m\])?$')
  [ "$total" -gt 0 ] && [ "$notid" -eq 0 ]
}
is_bare_list $'claude-opus-5\nclaude-fable-5-1' \
  && ok "control: the contract detector accepts a bare id list" \
  || bad "control: the contract detector rejects a valid bare id list"
is_bare_list $'MODELS (modelAccessCache)\n  x claude-fable-5   ' \
  && bad "control: the contract detector accepts a human report, so it cannot tell the flag is unimplemented" \
  || ok "control: the contract detector rejects the human-report shape"
if ! elist=$("$REPO/tools/model-lookup.py" --list-entitled 2>/dev/null); then
  bad "model-lookup.py --list-entitled is missing or fails, so every launch refuses"
elif ! is_bare_list "$elist"; then
  bad "--list-entitled is not implemented: the tool ignored the flag and printed its human report"
elif ! printf 'MODEL_1=%s\nEFFORT_1=high\n' "$(printf '%s\n' "$elist" | head -1)" \
     | python3 "$REPO/tools/model-lookup.py" --check - >/dev/null 2>&1; then
  # Shape alone would accept a list of bare words like "ALIASES". Ask the validator
  # whether the first entry is really a model this account can run.
  bad "--list-entitled prints bare tokens that are not valid model ids"
else
  ok "--list-entitled prints $(printf '%s\n' "$elist" | /usr/bin/grep -c .) bare ids and the first one validates"
fi


STUB_LIST=$'claude-opus-5\nclaude-haiku-4-5-20251001\nclaude-fable-5-1\nclaude-sonnet-5\nclaude-opus-5'
# Defaults first, then the rest sorted and deduplicated:
#   1 claude-fable-5-1  2 claude-opus-5  3 claude-haiku-4-5-20251001  4 claude-sonnet-5
# The old hardcoded array put sonnet at 3, so picking 3 tells the two apart.
WIDE_LIST=$'m-a\nm-b\nm-c\nm-d\nm-e\nm-f\nm-g\nm-h\nm-i\nclaude-fable-5-1\nclaude-opus-5'

run_launcher() { # $1 = launcher basename, $2 = first pick, $3 = second pick; echoes temp dir
  local name=$1 pick1=${2:-} pick2=${3:-} tmp stdin
  tmp=$(mktemp -d)
  cp "$REPO/$name" "$tmp/$name"
  cp -R "$REPO/tools" "$tmp/tools"
  mkdir -p "$tmp/bin" "$tmp/projects/probeproj" "$tmp/.claude/hooks"
  cp "$REPO/.claude/settings.json" "$tmp/.claude/settings.json"
  cp "$REPO/.claude/hooks/startup.sh" "$REPO/.claude/hooks/startup.py" "$tmp/.claude/hooks/"
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
  # Pin the contract so this section tests the launcher, not Agent 2's chosen values.
  printf '\nDEFAULT_STRONG_MODEL="%s"\nDEFAULT_CHEAP_MODEL="%s"\n' \
    "${DEF_STRONG-claude-fable-5-1}" "${DEF_CHEAP-claude-opus-5}" >> "$tmp/tools/launcher-common.sh"
  printf '%s\n' "${LIST_TEXT:-$STUB_LIST}" > "$tmp/tools/entitled.txt"
  cat > "$tmp/tools/model-lookup.py" <<'EOS'
#!/usr/bin/env bash
case "${1:-}" in
  --list-entitled)
    if [ -n "${LIST_FAIL:-}" ]; then echo "stub: entitlement cache unreadable" >&2; exit 4; fi
    cat "$(dirname "$0")/entitled.txt" ;;
  *) cat >/dev/null 2>&1; exit 0 ;;
esac
EOS
  cat > "$tmp/bin/osascript" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PANE_REC"
printf 'AAA,BBB,CCC,DDD\n'
EOS
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/sleep"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/send-to-agent.sh"
  chmod +x "$tmp/bin/osascript" "$tmp/bin/sleep" "$tmp/send-to-agent.sh" "$tmp/tools/model-lookup.py"
  case "$name" in
    launch.sh)    stdin="n"$'\n'"1"$'\n'"$pick1"$'\n'"$pick2"$'\n1\n\n\nn\nprobeproj\n' ;;
    workspace.sh) stdin=$'1\nn\n' ;;
  esac
  ( cd "$tmp" && PANE_REC="$tmp/.panes" LIST_FAIL="${LIST_FAIL:-}" PATH="$tmp/bin:$PATH" \
      bash "$name" >"$tmp/.out" 2>"$tmp/.err" <<< "$stdin" )
  printf '%s' "$tmp"
}
pane_model() { /usr/bin/grep -m1 "AGENT_NUMBER=$2 " "$1/.panes" 2>/dev/null | sed -n "s/.*--model '\([^']*\)'.*/\1/p"; }
refused()    { [ ! -s "$1/.panes" ] && /usr/bin/grep -q 'LAUNCH REFUSED' "$1/.err"; }

echo "--- the menu is the entitled list, ordered defaults-first then sorted ---"
T=$(run_launcher launch.sh 3 2)
menu=$(/usr/bin/grep -oE '^ +[0-9]+\) .+' "$T/.err" | head -8)
if [ -z "$menu" ]; then bad "no menu was printed"; else
  for i in 1 2 3 4; do
    case $i in
      1) want=claude-fable-5-1 ; why="DEFAULT_STRONG_MODEL" ;;
      2) want=claude-opus-5 ; why="DEFAULT_CHEAP_MODEL" ;;
      3) want=claude-haiku-4-5-20251001 ; why="first remaining id in sort order" ;;
      4) want=claude-sonnet-5 ; why="last remaining id" ;;
    esac
    got=$(printf '%s\n' "$menu" | sed -n "s/^ *$i) *//p" | head -1)
    [ "$got" = "$want" ] && ok "$i) is the $why" || bad "$i) is '$got', expected $want"
  done
  [ -z "$(printf '%s\n' "$menu" | sed -n 's/^ *5) *//p')" ] && ok "the duplicate id was not offered twice" \
    || bad "the list was not deduplicated"
fi
[ "$(pane_model "$T" 1)" = claude-haiku-4-5-20251001 ] \
  && ok "picking 3 launches the 3rd menu entry, not the 3rd hardcoded id" \
  || bad "picking 3 launched '$(pane_model "$T" 1)'"
[ "$(pane_model "$T" 2)" = claude-opus-5 ] && ok "picking 2 launches the 2nd menu entry" \
  || bad "picking 2 launched '$(pane_model "$T" 2)'"
rm -rf "$T"

echo "--- empty input still takes the default, free text is still used verbatim ---"
T=$(run_launcher launch.sh "" my-custom-model-id)
[ "$(pane_model "$T" 1)" = claude-fable-5-1 ] && ok "empty input takes DEFAULT_STRONG_MODEL" \
  || bad "empty input gave '$(pane_model "$T" 1)'"
[ "$(pane_model "$T" 2)" = my-custom-model-id ] && ok "free text is passed through verbatim" \
  || bad "free text gave '$(pane_model "$T" 2)'"
rm -rf "$T"

# A two-digit menu is reachable: this account is entitled to 11 models. Bash reads a
# leading zero as octal in $(( )) but as decimal in [ -le ], so the bounds check and the
# index disagree: 010 selected the 8th entry and 08 aborted the launcher outright.
echo "--- a two-digit pick indexes the entry it displays, including with a leading zero ---"
T=$(LIST_TEXT="$WIDE_LIST" run_launcher launch.sh 10 010)
[ "$(pane_model "$T" 1)" = m-h ] && ok "picking 10 launches the 10th entry" \
  || bad "picking 10 launched '$(pane_model "$T" 1)'"
[ "$(pane_model "$T" 2)" = m-h ] && ok "picking 010 launches the 10th entry, not the 8th" \
  || bad "picking 010 launched '$(pane_model "$T" 2)'"
rm -rf "$T"
T=$(LIST_TEXT="$WIDE_LIST" run_launcher launch.sh 08 1)
[ -n "$(pane_model "$T" 1)" ] && ok "picking 08 does not abort the launcher" \
  || bad "picking 08 killed the launch: $(/usr/bin/grep -m1 'value too great' "$T/.err")"
rm -rf "$T"

echo "--- a failed list command refuses the launch, with no static fallback ---"
T=$(LIST_FAIL=1 run_launcher launch.sh 1 1)
refused "$T" && ok "refused, no panes created" || bad "launched despite an unreadable entitlement list"
/usr/bin/grep -q 'entitlement cache unreadable' "$T/.err" \
  && ok "the tool's own stderr is shown, so the cause is visible" \
  || bad "the tool's stderr was swallowed"
rm -rf "$T"

echo "--- a list that is not bare model ids is refused, not turned into menu entries ---"
T=$(LIST_TEXT=$'MODELS (modelAccessCache in /Users/x/.claude.json)\n  x claude-fable-5\n    claude-opus-5' \
    run_launcher launch.sh 1 1)
refused "$T" && ok "a human report is refused" || bad "built a menu out of '$(pane_model "$T" 1)'"
rm -rf "$T"

# D74: omitting an unentitled default would silently shift option 1 to a different model.
echo "--- a preset default the account is not entitled to refuses the launch ---"
T=$(LIST_TEXT=$'claude-opus-5\nclaude-sonnet-5' run_launcher launch.sh 1 1)
refused "$T" && ok "an unentitled DEFAULT_STRONG_MODEL is refused" \
  || bad "it was offered or omitted instead: pane 1 launched '$(pane_model "$T" 1)'"
/usr/bin/grep -q 'claude-fable-5-1 is not in' "$T/.err" && ok "the refusal names the offending default" \
  || bad "the refusal does not say which default is unentitled"
rm -rf "$T"
T=$(LIST_TEXT=$'claude-opus-5\nclaude-fable-5-1' run_launcher launch.sh 1 1)
[ "$(pane_model "$T" 1)" = claude-fable-5-1 ] \
  && ok "control: a launch whose defaults are both entitled still runs" \
  || bad "control: refused a launch whose defaults are both entitled"
rm -rf "$T"

echo "--- an empty default model refuses the launch instead of running claude --model '' ---"
T=$(DEF_STRONG= run_launcher launch.sh 1 1)
refused "$T" && ok "launch.sh refuses an empty default" \
  || bad "launch.sh launched pane 1 as '$(pane_model "$T" 1)'"
rm -rf "$T"
T=$(DEF_STRONG= run_launcher workspace.sh)
refused "$T" && ok "workspace.sh refuses an empty default" \
  || bad "workspace.sh launched pane 1 as '$(pane_model "$T" 1)'"
rm -rf "$T"

echo "--- the literals are gone, so there is nothing left to go stale ---"
/usr/bin/grep -q 'MODEL_CHOICES' "$REPO/launch.sh" \
  && bad "launch.sh still carries MODEL_CHOICES" || ok "launch.sh no longer hardcodes a model list"
for f in launch.sh workspace.sh; do
  if /usr/bin/grep -qE "^(DEFAULT_STRONG_MODEL|DEFAULT_CHEAP_MODEL)=" "$REPO/$f"; then
    bad "$f defines its own default model instead of sourcing it"
  else ok "$f does not define its own default model"; fi
done
if /usr/bin/grep -qE "^(ORCH_MODEL|WORKER_MODEL)=\"claude-" "$REPO/workspace.sh"; then
  bad "workspace.sh still assigns a hardcoded claude model id"
else ok "workspace.sh takes its models from the shared defaults"; fi

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
