#!/usr/bin/env bash
# The launcher preflight: refuses to start panes when the SessionStart hook is not
# demonstrably healthy. Exit status alone is NOT health (JSON injects on a non-zero
# exit), so the gate asserts the output contract AND rc==0.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

[ -f tools/preflight-hook.sh ] || { bad "tools/preflight-hook.sh does not exist"; echo; echo "  0 passed, 1 failed"; exit 1; }
# shellcheck disable=SC1091
source tools/preflight-hook.sh
source tests/preflight_test.fixtures.sh

# run the gate against a fixture; echoes "rc|stderr"
gate() {
  local root=$1 err out rc
  err=$(mktemp)
  preflight_hook "$root/settings.json" "$root" 220 1 2 3 4 >/dev/null 2>"$err"; rc=$?
  out=$(cat "$err"); rm -f "$err"
  printf '%s|%s' "$rc" "$out"
}

echo "--- the healthy case passes (without this, every RED below is meaningless) ---"
r=$(mkfix good); res=$(gate "$r"); rc=${res%%|*}
[ "$rc" -eq 0 ] && ok "good hook: gate passes" || bad "good hook REJECTED: ${res#*|}"
rm -rf "$r"

echo "--- the gate must accept THIS REPO'S OWN settings.json (production form) ---"
# Uses the real .claude/ verbatim, but in a sandbox root carrying the runtime state a
# launcher would have created. swarms/ is gitignored, so pointing at $REPO directly
# would pass here and fail on a fresh clone.
rs=$(mktemp -d); mkdir -p "$rs/swarms/220" "$rs/tools"
cp -R "$REPO/.claude" "$rs/.claude"
cp "$REPO/tools/pane1-settings.json" "$rs/tools/"
printf 'demo' > "$rs/swarms/220/ACTIVE_PROJECT"
errf=$(mktemp)
if ( source tools/preflight-hook.sh; preflight_hook "$rs/.claude/settings.json" "$rs" 220 1 2 3 4 ) >/dev/null 2>"$errf"; then
  ok "the repo's real settings.json passes the gate, so a real launch is not blocked"
else
  bad "THE GATE REFUSES THIS REPO'S OWN SETTINGS, every launch would be blocked: $(cat "$errf")"
fi
rm -f "$errf"; rm -rf "$rs"

echo "--- the \$CLAUDE_PROJECT_DIR registration form resolves like the runtime does ---"
r=$(mkfix projdir); res=$(gate "$r")
[ "${res%%|*}" -eq 0 ] && ok "\$CLAUDE_PROJECT_DIR form accepted" || bad "\$CLAUDE_PROJECT_DIR form refused: ${res#*|}"
rm -rf "$r"

echo "--- each assertion can fail, and says enough to fix it in ten seconds ---"
cause_for() {
  case $1 in
    unregistered) echo "no SessionStart command hook" ;;
    missing)      echo "registers this path and nothing is there" ;;
    notexec)      echo "not executable" ;;
    notjson)      echo "not JSON" ;;
    wrongevent)   echo "hookEventName is" ;;
    emptyctx)     echo "additionalContext is empty" ;;
    nobranch)     echo "never names Agent" ;;
    allagents)    echo "also names Agent" ;;
    slow)         echo "budget" ;;
    exit1)        echo "exit status is 0" ;;
    noproject)    echo "active project is resolved" ;;
    clearonly)    echo "source clear" ;;
  esac
}
for v in unregistered missing notexec notjson wrongevent emptyctx nobranch allagents slow exit1 noproject clearonly; do
  r=$(mkfix "$v"); res=$(gate "$r"); rc=${res%%|*}; msg=${res#*|}
  if [ "$rc" -eq 0 ]; then bad "$v: gate PASSED a broken hook"
  else
    want=$(cause_for "$v")
    case "$msg" in *"$want"*) ok "$v: rejected for its own reason ($want)" ;;
      *) bad "$v: rejected but NOT for '$want', so this fixture proves nothing: $msg" ;; esac
    case "$msg" in */*) : ;; *) bad "$v: message names no file path: $msg" ;; esac
    case "$msg" in *"assertion:"*) : ;; *) bad "$v: message names no assertion: $msg" ;; esac
    case "$msg" in *[Ff]ix:*) : ;; *) bad "$v: message states no remediation: $msg" ;; esac
  fi
  rm -rf "$r"
done

echo "--- exit status is not health, but it IS asserted (the R5 correction) ---"
r=$(mkfix exit1); res=$(gate "$r")
case "${res#*|}" in *"exit status"*|*"exit 0"*) ok "exit1: rejection names the exit-status assertion" ;; *) bad "exit1: rejected for the wrong reason: ${res#*|}" ;; esac
rm -rf "$r"

echo "--- both sources are exercised, not just startup ---"
r=$(mkfix clearonly); res=$(gate "$r")
case "${res#*|}" in *clear*) ok "clearonly: rejection names source=clear" ;; *) bad "clearonly: did not identify the clear branch: ${res#*|}" ;; esac
rm -rf "$r"

echo "--- clone safety: a missing SESSION.md must NOT block a launch ---"
r=$(mkfix good); mkdir -p "$r/projects/demo"
res=$(gate "$r"); [ "${res%%|*}" -eq 0 ] && ok "no SESSION.md: still passes" || bad "no SESSION.md wrongly blocked: ${res#*|}"
printf 'RESUME\n' > "$r/projects/demo/SESSION.md"
res=$(gate "$r"); [ "${res%%|*}" -eq 0 ] && ok "with SESSION.md: still passes" || bad "SESSION.md present broke it: ${res#*|}"
rm -rf "$r"

echo "--- a preflight that cannot run must refuse, not pass ---"
d=$(mktemp -d); cp tools/preflight-hook.sh "$d/"   # deliberately WITHOUT preflight-check.py
r=$(mkfix good)
( set +u; source "$d/preflight-hook.sh"; preflight_hook "$r/settings.json" "$r" 220 1 ) >/dev/null 2>"$d/err"; rc=$?
[ "$rc" -ne 0 ] && ok "missing checker: gate refuses (rc=$rc)" || bad "gate PASSED with its own checker missing"
m=$(cat "$d/err")
case "$m" in *preflight-check.py*) ok "missing checker: names the missing helper" ;; *) bad "missing checker: message does not name it: $m" ;; esac
case "$m" in *"PREFLIGHT REFUSED: /"*) ok "missing checker: refusal names a real path, not an empty one" ;; *) bad "missing checker: refusal has no path: $m" ;; esac
rm -rf "$d" "$r"

echo "--- records the hook digest (detection, not a gate) ---"
r=$(mkfix good); preflight_hook "$r/settings.json" "$r" 220 1 2 3 4 >/dev/null 2>&1
d="$r/swarms/220/hook.sha256"
[ -s "$d" ] && ok "digest recorded at swarms/220/hook.sha256" || bad "no digest recorded"
if [ -s "$d" ]; then
  want=$(shasum -a 256 "$r/hooks/startup.sh" | cut -d' ' -f1)
  case "$(cat "$d")" in *"$want"*) ok "digest matches the hook that was verified" ;; *) bad "digest does not match the verified hook" ;; esac
fi
rm -rf "$r"

echo "--- a malformed pane-1 deny file is refused for its own reason ---"
r=$(mkfix good); printf '{ "permissions": { "deny": [ ,, ] }\n' > "$r/tools/pane1-settings.json"
res=$(gate "$r")
case "${res#*|}" in
  *"valid JSON"*) ok "malformed deny file refused, citing the JSON assertion" ;;
  *) bad "malformed deny file: wrong reason or accepted: ${res#*|}" ;;
esac
rm -rf "$r"

echo "--- records the claude build for later correlation (record only, no assertion) ---"
r=$(mkfix good); preflight_hook "$r/settings.json" "$r" 220 1 2 3 4 >/dev/null 2>&1
b="$r/swarms/220/claude-build.txt"
[ -s "$b" ] && ok "claude build recorded at swarms/220/claude-build.txt" || bad "no build record written"
if [ -s "$b" ]; then
  for k in recorded_at claude_path claude_realpath claude_version; do
    /usr/bin/grep -q "^$k=" "$b" && ok "build record has $k" || bad "build record missing $k"
  done
  /usr/bin/grep -q "^claude_version=.*Claude Code" "$b" && ok "version string looks real" || bad "version string not captured: $(/usr/bin/grep '^claude_version=' "$b")"
fi
rm -rf "$r"

echo "--- a rejected launch records no digest ---"
r=$(mkfix notjson); preflight_hook "$r/settings.json" "$r" 220 1 2 3 4 >/dev/null 2>&1
[ ! -e "$r/swarms/220/hook.sha256" ] && ok "no digest written when the gate refused" || bad "wrote a digest for a hook it rejected"
rm -rf "$r"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
