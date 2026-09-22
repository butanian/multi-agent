#!/usr/bin/env bash
# Shared launcher constants and gates. Sourced by launch.sh, restart-swarm.sh and
# workspace.sh so each value exists once. THINK_PROMPT is already duplicated across five
# literals in this repo; do not add a sixth of anything here.

LAUNCHER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"

# Pane 1 only. Narrows the tool set and adds a path-scoped Read deny. The deny is a
# speed bump, not containment: Bash stays available so writes are unrestricted, and any
# extension not listed in the file stays readable. tools/pane1-settings.json states its
# own limits, and the preflight refuses to launch if it does not parse, because a
# malformed settings file silently disables every deny rule.
ORCH_TOOL_FLAGS="--tools Read,Write,Edit,Bash,Skill --strict-mcp-config --settings $LAUNCHER_ROOT/tools/pane1-settings.json"

# validate_models "<LABEL=value newline-separated>"
# An unknown --effort does not fail the CLI, it warns and silently uses the default, and
# an effort above a model's cap is silently downgraded. Both are invisible at runtime,
# which is why they are checked before any pane starts.
validate_models() {
  local here out
  here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || here=""
  if [ -n "${SWARM_SKIP_PREFLIGHT:-}" ]; then
    echo "  WARNING: SWARM_SKIP_PREFLIGHT is set. Not validating models or efforts." >&2
    return 0
  fi
  if [ ! -x "$here/model-lookup.py" ]; then
    printf 'LAUNCH REFUSED: %s\n  assertion: the model validator is present\n  the launcher cannot verify models, so it must not guess\n  Fix: restore tools/model-lookup.py\n' \
      "${here:-<unresolved>}/model-lookup.py" >&2
    return 1
  fi
  out=$(printf '%s\n' "$1" | "$here/model-lookup.py" --check -)
  if [ $? -ne 0 ]; then
    printf 'LAUNCH REFUSED: %s\n  assertion: every model id and effort is valid for this account\n%s\n  Fix: correct the flagged value, or set SWARM_SKIP_PREFLIGHT=1 to override deliberately\n' \
      "$here/model-lookup.py" "$out" >&2
    return 1
  fi
  return 0
}
