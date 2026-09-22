#!/bin/bash
# Tests for model-lookup.py. Run: ./test-model-lookup.sh
# Locate the validator from anywhere in the repo, so this file can live in
# tests/ or tools/ without edits. Override with LOOKUP=... to test a copy.
REPO_ROOT=$(cd "$(dirname "$0")" && git rev-parse --show-toplevel 2>/dev/null)
LOOKUP="${LOOKUP:-$REPO_ROOT/tools/model-lookup.py}"
if [ ! -x "$LOOKUP" ]; then
  echo "cannot find an executable validator at $LOOKUP" >&2; exit 1
fi
pass=0; fail=0
check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "  PASS  $name"; pass=$((pass+1))
  else echo "  FAIL  $name"; echo "        expected: $expected"; echo "        actual:   $actual"; fail=$((fail+1)); fi
}

FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT

# Help text with the wrapped --effort line, as `claude --help` really emits it.
cat > "$FIX/help_ok.txt" <<'HELP'
  --debug [filter]                      Enable debug mode
  --effort <level>                      Effort level for the current session
                                        (low, medium, high, xhigh, max)
  --fallback-model <model>              Enable automatic fallback
HELP

# Control: same help with the --effort option absent.
/usr/bin/grep -v 'effort' "$FIX/help_ok.txt" > "$FIX/help_missing.txt"

echo "test-model-lookup"

check "parses wrapped --effort line" \
  "low medium high xhigh max" \
  "$(HELP_FILE=$FIX/help_ok.txt $LOOKUP --efforts-only 2>&1)"

# Control: proves the parser reads the help text rather than printing a constant.
out=$(HELP_FILE=$FIX/help_missing.txt $LOOKUP --efforts-only 2>&1); rc=$?
check "errors when --effort is absent (exit)" "1" "$rc"
case "$out" in *"could not find"*) r=found ;; *) r="no error message: $out" ;; esac
check "errors when --effort is absent (message)" "found" "$r"

# Drift detector: goes red if this build's --help ever lists a different set.
check "live claude --help lists exactly the documented set" \
  "low medium high xhigh max" \
  "$($LOOKUP --efforts-only 2>&1)"


# --- --check, against launch.env shapes the launchers really accept ---

# `restart-swarm.sh:334` resolves MODEL_n with ${!mvar:-${MODEL:-$dm}}, so a bare
# MODEL=/EFFORT= is a live fallback and an empty MODEL_n= falls through to it.
cat > "$FIX/env_quotes.env" <<'ENV'
# a comment mentioning MODEL_1='bogus-should-be-ignored'
MODEL_1="claude-opus-5[1m]"
MODEL_2=claude-opus-5
EFFORT_1='xhigh'
ENV
printf 'MODEL_3="claude-sonnet-5"\r\n' >> "$FIX/env_quotes.env"
out=$($LOOKUP --check "$FIX/env_quotes.env" 2>&1)
case "$out" in *"0 problem"*) r=clean ;; *) r="flagged: $out" ;; esac
check "double-quoted, unquoted and [1m] values are accepted" "clean" "$r"

cat > "$FIX/env_empty.env" <<'ENV'
MODEL_1=''
EFFORT_1=''
ENV
out=$($LOOKUP --check "$FIX/env_empty.env" 2>&1)
case "$out" in *"0 problem"*) r=clean ;; *) r="flagged: $out" ;; esac
check "empty value falls through to the default, not an error" "clean" "$r"

cat > "$FIX/env_old.env" <<'ENV'
MODEL=not-a-real-model
EFFORT=bogus
ENV
out=$($LOOKUP --check "$FIX/env_old.env" 2>&1)
case "$out" in *"2 problem"*) r=caught ;; *) r="missed: $out" ;; esac
check "old-format bare MODEL=/EFFORT= are checked, not skipped" "caught" "$r"

# Control: a real bad value must still be caught, so the above are not just
# making --check permissive enough to pass everything.
printf 'MODEL_1=Opus5with1Mcontext\r\nEFFORT_1=xhigh\r\n' > "$FIX/env_bad.env"
out=$($LOOKUP --check "$FIX/env_bad.env" 2>&1)
case "$out" in *"1 problem"*) r=caught ;; *) r="missed: $out" ;; esac
check "the real bug is still caught, through CRLF" "caught" "$r"


# --- Codex review: the effort regex must not reach past the --effort option ---

# No list on --effort. The old regex ran forward and returned the NEXT flag's
# choices, a false success. It must error instead.
cat > "$FIX/help_steal.txt" <<'HELP'
  --effort <level>                      Effort level for the current session
  --input-format <format>               Input format (choices: "text", "stream-json")
HELP
out=$(HELP_FILE=$FIX/help_steal.txt $LOOKUP --efforts-only 2>&1); rc=$?
check "does not steal the next flag's choices (exit)" "1" "$rc"
case "$out" in *"could not"*) r=errored ;; *) r="returned: $out" ;; esac
check "does not steal the next flag's choices (message)" "errored" "$r"

# A parenthetical earlier in the same description must not win.
cat > "$FIX/help_paren.txt" <<'HELP'
  --effort <level>                      Effort level (reasoning budget) for current
                                        session (low, medium, high, xhigh, max)
  --fallback-model <model>              Enable automatic fallback
HELP
check "picks the value list, not an earlier parenthetical" \
  "low medium high xhigh max" \
  "$(HELP_FILE=$FIX/help_paren.txt $LOOKUP --efforts-only 2>&1)"

# --- Codex review: an API/auth failure is not a model rejection ---

cat > "$FIX/claude_authfail" <<'STUB'
#!/bin/bash
echo '{"modelUsage":{},"is_error":true,"terminal_reason":"api_error","result":"Not logged in"}'
STUB
chmod +x "$FIX/claude_authfail"
out=$(CLAUDE_BIN="$FIX/claude_authfail" HELP_FILE=$FIX/help_ok.txt $LOOKUP --probe-aliases 2>&1)
case "$out" in
  *REJECTED*) r="wrongly says REJECTED" ;;
  *api_error*) r=reported ;;
  *) r="neither: $out" ;;
esac
check "auth/API failure is reported as such, not as REJECTED" "reported" "$r"

# Control: a genuinely unrecognized model must still read REJECTED.
cat > "$FIX/claude_badmodel" <<'STUB'
#!/bin/bash
echo 'not json, unrecognized_model' >&2
echo 'not json'
STUB
chmod +x "$FIX/claude_badmodel"
out=$(CLAUDE_BIN="$FIX/claude_badmodel" HELP_FILE=$FIX/help_ok.txt $LOOKUP --probe-aliases 2>&1)
case "$out" in *REJECTED*) r=rejected ;; *) r="missed: $out" ;; esac
check "a real rejection still reads REJECTED" "rejected" "$r"


# --- R1d: launcher-facing validation ---

cat > "$FIX/fake_claude.json" <<'J'
{"modelAccessCache":[{"apiName":"claude-opus-5","entitled":true},
                     {"apiName":"claude-fable-5-1","entitled":true,"maxEffortLevel":"xhigh"}]}
J
export CLAUDE_JSON="$FIX/fake_claude.json"

# The launcher validates values it holds in memory, before any launch.env exists.
out=$(printf 'MODEL_1=claude-opus-5\nEFFORT_1=xhigh\n' | $LOOKUP --check - 2>&1); rc=$?
case "$out" in *"0 problem"*) r=clean ;; *) r="flagged: $out" ;; esac
check "reads a launch.env from stdin with --check -" "clean" "$r"
check "exit 0 when stdin values are valid" "0" "$rc"

out=$(printf 'MODEL_1=Opus5with1Mcontext\nEFFORT_1=xhigh\n' | $LOOKUP --check - 2>&1); rc=$?
check "exit 1 on a bad model from stdin" "1" "$rc"

# `claude --effort max --model claude-fable-5-1` does not fail: it prints
# "Effort 'max' exceeds the cap for claude-fable-5-1 ...; using 'xhigh'" and downgrades.
out=$(printf 'MODEL_1=claude-fable-5-1\nEFFORT_1=max\n' | $LOOKUP --check - 2>&1)
case "$out" in *"exceeds"*) r=caught ;; *) r="missed: $out" ;; esac
check "flags an effort above that model's cap" "caught" "$r"

out=$(printf 'MODEL_1=claude-fable-5-1\nEFFORT_1=xhigh\n' | $LOOKUP --check - 2>&1)
case "$out" in *"0 problem"*) r=clean ;; *) r="flagged: $out" ;; esac
check "effort exactly at the cap is fine" "clean" "$r"

# Control: a model with no cap must not inherit another model's cap.
out=$(printf 'MODEL_1=claude-opus-5\nEFFORT_1=max\n' | $LOOKUP --check - 2>&1)
case "$out" in *"0 problem"*) r=clean ;; *) r="flagged: $out" ;; esac
check "uncapped model accepts max" "clean" "$r"

unset CLAUDE_JSON


# --- Codex review of the spec: two validator defects ---

export CLAUDE_JSON="$FIX/fake_claude.json"

# An alias resolves at runtime, so the cap cannot be looked up from the literal.
# It must say so rather than pass silently.
out=$(printf 'MODEL_1=fable\nEFFORT_1=max\n' | $LOOKUP --check - 2>&1)
case "$out" in
  *"cap not checked"*) r=noted ;;
  *"0 problem"*)       r="silently passed" ;;
  *)                   r="other: $out" ;;
esac
check "alias + capped effort is not silently passed" "noted" "$r"

# Control: a concrete id must still be capped, so the fix is not just muting the check.
out=$(printf 'MODEL_1=claude-fable-5-1\nEFFORT_1=max\n' | $LOOKUP --check - 2>&1)
case "$out" in *"exceeds"*) r=caught ;; *) r="missed: $out" ;; esac
check "concrete capped model still flags max" "caught" "$r"

# `restart-swarm.sh` sources launch.env, so spaces inside quotes really do reach --model.
out=$(printf "MODEL_1=' claude-opus-5 '\n" | $LOOKUP --check - 2>&1)
case "$out" in *"<--"*) r=caught ;; *) r="missed: $out" ;; esac
check "spaces inside quotes are not silently trimmed away" "caught" "$r"

# Control: unquoted trailing whitespace is not part of the shell value, so it is fine.
out=$(printf 'MODEL_1=claude-opus-5   \n' | $LOOKUP --check - 2>&1)
case "$out" in *"0 problem"*) r=clean ;; *) r="flagged: $out" ;; esac
check "unquoted trailing whitespace is still accepted" "clean" "$r"

unset CLAUDE_JSON

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
