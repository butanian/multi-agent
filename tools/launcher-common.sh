#!/usr/bin/env bash
# Shared launcher constants and gates. Sourced by launch.sh, restart-swarm.sh and
# workspace.sh so each value exists once. THINK_PROMPT is already duplicated across five
# literals in this repo; do not add a sixth of anything here.

LAUNCHER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"

DEFAULT_STRONG_MODEL="claude-fable-5-1"
DEFAULT_CHEAP_MODEL="claude-opus-5"

# Pane 1 only. Narrows the tool set and adds a path-scoped Read deny. The deny is a
# speed bump, not containment: Bash stays available so writes are unrestricted, and any
# extension not listed in the file stays readable. tools/pane1-settings.json states its
# own limits, and the preflight refuses to launch if it does not parse, because a
# malformed settings file silently disables every deny rule.
ORCH_TOOL_FLAGS="--tools Read,Write,Edit,Bash,Skill --strict-mcp-config --settings $LAUNCHER_ROOT/tools/pane1-settings.json"

# engine_cmd <agent> <engine> <model> <effort> <perms_flag> <extra_flags>
# Prints the command that starts one pane. Default engine is claude, and the claude
# branch reproduces exactly what the launchers built before this existed.
#
# The codex branch uses the invocation verified in R2, not a guess. It must run outside
# the Codex sandbox because send-to-agent.sh drives iTerm2 through AppleScript, and
# Apple Events are severed inside the sandbox with no seatbelt denial to widen. A Codex
# pane also cannot read the launcher's banner from scrollback, so its identity is baked
# into the bootstrap prompt as well as exported in AGENT_NUMBER.
engine_cmd() {
  local agent=$1 engine=${2:-claude} model=$3 effort=$4 perms=${5:-} extra=${6:-}
  local effort_flag=""
  case "$engine" in
    ""|claude)
      [ -n "$effort" ] && effort_flag="--effort $effort"
      printf "claude --model '%s'%s%s%s" "$model" \
        "${effort_flag:+ $effort_flag}" "${perms:+ $perms}" "${extra:+ $extra}"
      ;;
    codex)
      printf "codex --no-alt-screen -s danger-full-access -a never -m '%s'" "$model"
      [ -n "$effort" ] && printf " -c 'model_reasoning_effort=\"%s\"'" "$effort"
      printf " 'You are Agent %s in this swarm. Read AGENTS.md, then run your startup protocol.'" "$agent"
      ;;
    *)
      printf 'LAUNCH REFUSED: unknown engine %s for agent %s\n  Fix: set ENGINE_%s to claude or codex\n' \
        "$engine" "$agent" "$agent" >&2
      return 1
      ;;
  esac
}

# report_engine_gating "<engine per pane, space separated>"
# A pane the gates skip must say so. An unannounced exclusion reads as a gated pane,
# which is the failure this whole swarm has been removing.
report_engine_gating() {
  local engines=$1 i=0 e excluded=""
  for e in $engines; do
    i=$((i+1))
    case "$e" in
      ""|claude) ;;
      *) excluded="$excluded $i"
         echo "  pane $i: $e, NOT preflighted, NOT model-validated (AGENTS.md is its startup contract)" >&2 ;;
    esac
  done
  if [ -z "$excluded" ]; then
    echo "  all $i panes: claude, preflighted and model-validated." >&2
  fi
}

# validate_models "<LABEL=value newline-separated>"
# An unknown --effort does not fail the CLI, it warns and silently uses the default, and
# an effort above a model's cap is silently downgraded. Both are invisible at runtime,
# which is why they are checked before any pane starts. SWARM_SKIP_PREFLIGHT deliberately
# does not reach here: it exists to get past a broken startup hook, not a bad model id.
validate_models() {
  local pairs=$1 engines=${2:-}
  local here out
  here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || here=""
  if [ -n "$engines" ]; then
    local i=0 e keep=""
    for e in $engines; do
      i=$((i+1))
      case "$e" in ""|claude) keep="$keep $i" ;; esac
    done
    local filtered="" line n
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      n=$(printf '%s' "$line" | sed -n 's/^[A-Z]*_\([0-9]*\)=.*/\1/p')
      [ -n "$n" ] || continue
      case " $keep " in *" $n "*) filtered="$filtered$line
" ;; esac
    done <<< "$pairs"
    pairs=$filtered
  fi
  [ -n "$(printf '%s' "$pairs" | tr -d '[:space:]')" ] || return 0
  local empties="" line
  while IFS= read -r line; do
    case "$line" in
      MODEL_[0-9]*=*|EFFORT_[0-9]*=*)
        [ -n "$(printf '%s' "${line#*=}" | tr -d '[:space:]')" ] || empties="$empties ${line%%=*}"
        ;;
    esac
  done <<< "$pairs"
  if [ -n "$empties" ]; then
    printf 'LAUNCH REFUSED: empty value for%s\n  assertion: every Claude pane has both a model and an effort\n  an empty model id reaches the CLI as an empty --model argument, and an empty effort silently takes the CLI default\n  Fix: set a value for each, or set ENGINE_n=codex for a pane that is not Claude\n' \
      "$empties" >&2
    return 1
  fi
  if [ ! -x "$here/model-lookup.py" ]; then
    printf 'LAUNCH REFUSED: %s\n  assertion: the model validator is present\n  the launcher cannot verify models, so it must not guess\n  Fix: restore tools/model-lookup.py\n' \
      "${here:-<unresolved>}/model-lookup.py" >&2
    return 1
  fi
  out=$(printf '%s\n' "$pairs" | "$here/model-lookup.py" --check -)
  if [ $? -ne 0 ]; then
    printf 'LAUNCH REFUSED: %s\n  assertion: every model id and effort is valid for this account\n%s\n  Fix: correct the flagged value\n' \
      "$here/model-lookup.py" "$out" >&2
    return 1
  fi
  return 0
}
