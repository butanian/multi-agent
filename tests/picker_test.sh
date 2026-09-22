#!/usr/bin/env bash
# The model menu must come from the entitlement layer, not a literal. Swarm 220 shipped
# a picker whose four hardcoded ids were never checked against the account, so it could
# offer models the account cannot run and hide models it can.
#
# Section 1 asserts the tools/ contract this launcher depends on. It is RED until
# harness/swarm-222-a lands, and that is the point: a launcher wired to a helper that
# does not exist yet must be loud, not silently broken.
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
# model-lookup.py ignores an unknown flag and prints its human report with rc=0, so
# "exits 0" proves nothing. Every line must be a bare id or the flag is not implemented.
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
elif is_bare_list "$elist"; then
  ok "--list-entitled prints $(printf '%s\n' "$elist" | /usr/bin/grep -c .) bare model ids"
else
  bad "--list-entitled is not implemented: the tool ignored the flag and printed its human report"
fi

# ── Behavioural section: stubbed tools/, so the launcher logic is proven either way ──

STUB_LIST=$'claude-opus-5\nclaude-haiku-4-5-20251001\nclaude-fable-5-1\nclaude-sonnet-5\nclaude-opus-5'
# Defaults first, then the rest sorted and deduplicated:
#   1 claude-fable-5-1  2 claude-opus-5  3 claude-haiku-4-5-20251001  4 claude-sonnet-5
# The old hardcoded array put sonnet at 3, so picking 3 tells the two apart.

run_launch() { # $1 = first pick, $2 = second pick; echoes the temp dir
  local pick1=$1 pick2=$2 tmp
  tmp=$(mktemp -d)
  cp "$REPO/launch.sh" "$tmp/launch.sh"
  cp -R "$REPO/tools" "$tmp/tools"
  mkdir -p "$tmp/bin" "$tmp/.claude/hooks"
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
  cat >> "$tmp/tools/launcher-common.sh" <<'EOS'

DEFAULT_STRONG_MODEL="claude-fable-5-1"
DEFAULT_CHEAP_MODEL="claude-opus-5"
EOS
  printf '%s\n' "$STUB_LIST" > "$tmp/tools/entitled.txt"
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
  ( cd "$tmp" && PANE_REC="$tmp/.panes" LIST_FAIL="${LIST_FAIL:-}" PATH="$tmp/bin:$PATH" \
      bash launch.sh >"$tmp/.out" 2>"$tmp/.err" <<< "n"$'\n'"1"$'\n'"$pick1"$'\n'"$pick2"$'\n1\n\n\nn\nprobeproj\n' )
  printf '%s' "$tmp"
}
pane_model() { /usr/bin/grep -m1 "AGENT_NUMBER=$2 " "$1/.panes" 2>/dev/null | sed -n "s/.*--model '\([^']*\)'.*/\1/p"; }

echo "--- the menu is the entitled list, ordered defaults-first then sorted ---"
T=$(run_launch 3 2)
menu=$(/usr/bin/grep -oE '^ +[0-9]+\) .+' "$T/.err" | head -8)
if [ -z "$menu" ]; then bad "no menu was printed"; else
  n1=$(printf '%s\n' "$menu" | sed -n 's/^ *1) *//p' | head -1)
  n2=$(printf '%s\n' "$menu" | sed -n 's/^ *2) *//p' | head -1)
  n3=$(printf '%s\n' "$menu" | sed -n 's/^ *3) *//p' | head -1)
  n4=$(printf '%s\n' "$menu" | sed -n 's/^ *4) *//p' | head -1)
  [ "$n1" = claude-fable-5-1 ] && ok "1) is DEFAULT_STRONG_MODEL" || bad "1) is '$n1', expected the strong default"
  [ "$n2" = claude-opus-5 ]    && ok "2) is DEFAULT_CHEAP_MODEL"  || bad "2) is '$n2', expected the cheap default"
  [ "$n3" = claude-haiku-4-5-20251001 ] && ok "3) is the first remaining id in sort order" || bad "3) is '$n3'"
  [ "$n4" = claude-sonnet-5 ]  && ok "4) is the last remaining id" || bad "4) is '$n4'"
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
T=$(run_launch "" my-custom-model-id)
[ "$(pane_model "$T" 1)" = claude-fable-5-1 ] && ok "empty input takes DEFAULT_STRONG_MODEL" \
  || bad "empty input gave '$(pane_model "$T" 1)'"
[ "$(pane_model "$T" 2)" = my-custom-model-id ] && ok "free text is passed through verbatim" \
  || bad "free text gave '$(pane_model "$T" 2)'"
rm -rf "$T"

echo "--- a failed list command refuses the launch, with no static fallback ---"
T=$(LIST_FAIL=1 run_launch 1 1)
if [ -s "$T/.panes" ]; then bad "the launcher created panes despite an unreadable entitlement list"
else ok "no panes were created"; fi
/usr/bin/grep -q 'LAUNCH REFUSED' "$T/.err" && ok "refusal uses the LAUNCH REFUSED shape" \
  || bad "refused without the LAUNCH REFUSED shape: $(head -c 200 "$T/.err")"
/usr/bin/grep -q 'entitlement cache unreadable' "$T/.err" \
  && ok "the tool's own stderr is shown, so the cause is visible" \
  || bad "the tool's stderr was swallowed"
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
