#!/usr/bin/env bash
# restart-swarm.sh types into panes with AppleScript. Two defects this covers:
#   1. reading the payload file without the utf8 class mangles non-ASCII, and the
#      launch line it reads contains box-drawing characters, a middle dot and an em
#      dash. Same defect Agent 4 fixed in send-to-agent.sh.
#   2. when no session matches the uuid the scripts fall off the end of the loop and
#      report success, so a --hard refresh silently skips a pane whose window closed.
set -uo pipefail
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
F=restart-swarm.sh

echo "--- every AppleScript file read declares the utf8 class ---"
opens=$(/usr/bin/grep -c 'open for access' "$F")
utf8=$(/usr/bin/grep -c 'as «class utf8»' "$F")
[ "$opens" -gt 0 ] && ok "found $opens AppleScript file reads" || bad "found no file reads, has the file changed shape?"
[ "$utf8" -eq "$opens" ] && ok "all $opens reads declare utf8" || bad "$opens reads but only $utf8 declare utf8"

echo "--- the payload really does contain non-ASCII, so the utf8 class matters ---"
nb=$(python3 - <<'PJ'
s=open('restart-swarm.sh').read()
i=s.index('launch_line_for()')
print(len([c for c in s[i:i+1400] if ord(c)>127]))
PJ
)
[ "$nb" -gt 0 ] && ok "launch_line_for emits $nb non-ASCII characters" || bad "no non-ASCII found; the utf8 requirement needs re-justifying"

echo "--- control: a read without the utf8 class DOES mangle that payload ---"
tf=$(mktemp); printf 'AGENT 1 ═══ · effort: high\n' > "$tf"
plain=$(osascript -e "set r to open for access (POSIX file \"$tf\")
set t to read r
close access r
return t" 2>/dev/null)
utf=$(osascript -e "set r to open for access (POSIX file \"$tf\")
set t to read r as «class utf8»
close access r
return t" 2>/dev/null)
rm -f "$tf"
[ "$plain" != "$utf" ] && ok "the two read forms differ, so this is a real defect not a style point" \
  || bad "both reads agree; the premise for this fix is wrong"
[ "$utf" = "AGENT 1 ═══ · effort: high" ] && ok "the utf8 form round-trips exactly" || bad "utf8 form did not round-trip: $utf"

echo "--- no pane-typing script may report success when no session matches ---"
# Run the REAL heredocs, extracted from the file at test time so they cannot drift.
# Compilation is asserted SEPARATELY: a syntax error also exits non-zero, and would
# otherwise masquerade as the no-match failure this is meant to prove.
extract() { # $1=function name (or "" for a top-level block) $2=heredoc marker
  local fn=$1 marker=$2 src
  src=$(mktemp)
  if [ -n "$fn" ]; then
    sed -n "/^$fn()/,/^}/p" "$F" | awk "/<<'$marker'\$/{f=1;next} /^$marker\$/{f=0} f" > "$src"
  else
    awk "/<<'$marker'\$/{f=1;next} /^$marker\$/{f=0} f" "$F" > "$src"
  fi
  printf '%s' "$src"
}
BOGUS="00000000-0000-4000-8000-000000000000"
pf=$(mktemp); printf "echo 'probe'\n" > "$pf"

check_block() { # $1=label $2=fn $3=marker $4...=argv
  local label=$1 fn=$2 marker=$3; shift 3
  local scr; scr=$(extract "$fn" "$marker")
  if [ ! -s "$scr" ]; then bad "$label: could not extract the script"; rm -f "$scr"; return; fi
  if osascript -e "1" >/dev/null 2>&1 && ! osascript "$scr" 2>&1 | /usr/bin/grep -q 'run handler is specified more than once'; then
    ok "$label: extracted exactly one script (compiles as one run handler)"
  else
    bad "$label: extraction produced more than one script, so any failure below proves nothing"
    rm -f "$scr"; return
  fi
  local err rc
  err=$(osascript "$scr" "$@" 2>&1); rc=$?
  case "$err" in
    *"script error"*) bad "$label: failed to COMPILE, not on the no-match path: $err" ;;
    *) if [ "$rc" -ne 0 ]; then ok "$label: fails on an unmatched uuid (rc=$rc)"
       else bad "$label: reported SUCCESS for a uuid that does not exist"; fi ;;
  esac
  rm -f "$scr"
}

check_block "type_in_pane" type_in_pane APPLESCRIPT "$BOGUS" "some text"
check_block "write_line_to_pane" write_line_to_pane APPLESCRIPT "$BOGUS" "$pf"
check_block "detached relaunch" "" A2 "$BOGUS" "$pf"
rm -f "$pf"

echo "--- every pane-typing helper carries an explicit error ---"
for fn in type_in_pane write_line_to_pane interrupt_pane; do
  blk=$(sed -n "/^$fn()/,/^}/p" "$F")
  [ -n "$blk" ] || { bad "$fn not found"; continue; }
  printf '%s\n' "$blk" | /usr/bin/grep -q 'error ' && ok "$fn errors when nothing matches" \
    || bad "$fn silently succeeds when nothing matches"
done

echo "--- a failed pane write is recorded, not just warned past ---"
blk=$(sed -n '/^refresh_peer()/,/^}/p' "$F")
printf '%s\n' "$blk" | /usr/bin/grep -q 'record_send' && ok "refresh_peer records unreached panes for the delivery summary" \
  || bad "refresh_peer does not feed the delivery summary, so a half-failed refresh stays skimmable"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
