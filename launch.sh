#!/usr/bin/env bash
# launch.sh — Open iTerm2 with agent pane(s) and capture session IDs
#
# Usage: ./launch.sh
#
# Defaults to a single pane running one Claude Code agent. The original 4-pane
# orchestrator/worker swarm is still available as an explicit choice at the
# "Launch Mode" prompt, and writes session UUIDs to swarms/N/pane-config.sh so
# that send-to-agent.sh can target the right pane(s).
#
# Full swarm layout (opt-in):
#   ┌─────────────┬─────────────┐
#   │  Agent 1    │  Agent 2    │
#   │ (you/orch.) │             │
#   ├─────────────┼─────────────┤
#   │  Agent 3    │  Agent 4    │
#   │             │             │
#   └─────────────┴─────────────┘

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Sourced here rather than beside the preflight because the model picker below needs
# DEFAULT_STRONG_MODEL and DEFAULT_CHEAP_MODEL.
source "$SCRIPT_DIR/tools/launcher-common.sh"

# ── Swarm number ───────────────────────────────────────────────────────────────
# Find the next available swarm number by scanning swarms/ for existing dirs
SWARM_ID=1
if [ -d "$SCRIPT_DIR/swarms" ]; then
  for d in "$SCRIPT_DIR/swarms"/*/; do
    [ -d "$d" ] || continue
    num=$(basename "$d")
    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge "$SWARM_ID" ]; then
      SWARM_ID=$((num + 1))
    fi
  done
fi

# ── Thinking: always level 3 (high) ───────────────────────────────────────────
THINK_FLAG="--append-system-prompt 'Think deeply and use extended reasoning. Explore edge cases and alternatives. Prefer thoroughness over brevity.'"

# ── Launch mode ────────────────────────────────────────────────────────────────
# Default is a single pane. The 4-pane orchestrator/worker split still exists below and
# stays selectable, so it is available the day a "grow this swarm" feature reads it — it
# is just no longer what a bare launch does.
echo "── Launch Mode ───────────────────────────────────────────────────────────"
echo "  1) Single agent (default)"
echo "  4) Full 4-agent swarm (orchestrator + 3 workers)"
read -p "  Pick [1/4] (default 1): " RAW_AGENT_COUNT
echo "──────────────────────────────────────────────────────────────────────────"
echo ""
AGENT_COUNT=$(echo "${RAW_AGENT_COUNT:-1}" | tr -d '[:space:]')
[[ "$AGENT_COUNT" =~ ^(1|4)$ ]] || AGENT_COUNT=1

# ── Engines ────────────────────────────────────────────────────────────────────
pick_engine() {
  local agent="$1" raw
  echo "  Agent $agent engine:" >&2
  echo "    1) Claude (default)   2) Codex" >&2
  read -p "  Pick [1/2] (default 1): " raw
  case "$(echo "${raw:-1}" | tr -d '[:space:]')" in
    2) echo codex ;;
    *) echo claude ;;
  esac
}

ENGINE_1=$(pick_engine 1)
if [ "$AGENT_COUNT" = "4" ]; then
  ENGINE_2=$(pick_engine 2)
  ENGINE_3=$(pick_engine 3)
  ENGINE_4=$(pick_engine 4)
else
  ENGINE_2=claude ENGINE_3=claude ENGINE_4=claude
fi

# One question. Answer "all", blank for none, or pane numbers such as "2 4". launch.env
# records GATEWAY_n per pane, so a later edit there changes one pane.
read -p "  Panes to route through the Bifrost gateway [all / numbers like '2 4' / blank = none]: " _gw
GATEWAY_1=direct GATEWAY_2=direct GATEWAY_3=direct GATEWAY_4=direct
case "$(echo "${_gw:-}" | tr 'A-Z' 'a-z')" in
  *all*) GATEWAY_1=bifrost GATEWAY_2=bifrost GATEWAY_3=bifrost GATEWAY_4=bifrost ;;
  *) for _n in $_gw; do case "$_n" in [1-4]) printf -v "GATEWAY_$_n" bifrost ;; esac; done ;;
esac
[ "$AGENT_COUNT" = "4" ] || GATEWAY_2=direct GATEWAY_3=direct GATEWAY_4=direct

# ── Models ─────────────────────────────────────────────────────────────────────
MODEL_MENU=()
build_model_menu() {
  local engine="$1" default="$2" err list m rc=0
  if [ "$engine" = "codex" ]; then
    err=$(mktemp)
    list=$(python3 "$SCRIPT_DIR/tools/codex-model-lookup.py" 2>"$err") || rc=$?
    if [ "$rc" -ne 0 ] || [ -z "${list//[[:space:]]/}" ]; then
      printf 'LAUNCH REFUSED: Codex model catalog could not be loaded\n%s\n' "$(sed 's/^/  /' "$err")" >&2
      rm -f "$err"
      return 1
    fi
    rm -f "$err"
  else
    if [ -z "$default" ]; then
      printf 'LAUNCH REFUSED: %s\n  assertion: DEFAULT_STRONG_MODEL is set\n  it is empty, so panes would start as: claude --model %s\n  Fix: define it in tools/launcher-common.sh\n' \
        "$SCRIPT_DIR/tools/launcher-common.sh" "''" >&2
      return 1
    fi
    err=$(mktemp)
    list=$("$SCRIPT_DIR/tools/model-lookup.py" --list-entitled 2>"$err") || rc=$?
    if [ "$rc" -ne 0 ] || [ -z "${list//[[:space:]]/}" ]; then
      printf 'LAUNCH REFUSED: %s --list-entitled\n  assertion: the entitled model list is readable\n%s\n' \
        "$SCRIPT_DIR/tools/model-lookup.py" "$(sed 's/^/  /' "$err")" >&2
      rm -f "$err"
      return 1
    fi
    rm -f "$err"
    if ! printf '%s\n' "$list" | /usr/bin/grep -qxF "$default"; then
      printf 'LAUNCH REFUSED: %s\n  assertion: the default model is in the entitled list\n  %s is not in --list-entitled\n' \
        "$SCRIPT_DIR/tools/launcher-common.sh" "$default" >&2
      return 1
    fi
  fi
  # rc 0 is not enough on its own. This output becomes the menu verbatim, so anything
  # that is not a bare id would be offered to the user as a selectable model.
  if printf '%s\n' "$list" | /usr/bin/grep -qvE '^[A-Za-z0-9._-]+(\[1m\])?$|^$'; then
    printf 'LAUNCH REFUSED: invalid %s model catalog\n  assertion: it contains bare model ids, one per line\n  first offending line: %s\n' \
      "$engine" \
      "$(printf '%s\n' "$list" | /usr/bin/grep -m1 -vE '^[A-Za-z0-9._-]+(\[1m\])?$|^$')" >&2
    return 1
  fi
  MODEL_MENU=()
  [ -z "$default" ] || MODEL_MENU+=("$default")
  if [ "$engine" = "codex" ]; then
    while IFS= read -r m; do
      [ -n "$m" ] && [ "$m" != "$default" ] && MODEL_MENU+=("$m")
    done <<< "$list"
  else
    while IFS= read -r m; do
      [ -n "$m" ] && [ "$m" != "$default" ] && MODEL_MENU+=("$m")
    done < <(printf '%s\n' "$list" | sort -u)
  fi
}

# pick_model <label> <default> — prints the chosen model id on stdout.
pick_model() {
  local label="$1" default="$2" raw i
  echo "  $label model:" >&2
  for i in "${!MODEL_MENU[@]}"; do
    printf '    %2d) %s\n' "$((i+1))" "${MODEL_MENU[$i]}" >&2
  done
  echo "    or type a model id" >&2
  read -p "  [default: $default] > " raw
  raw=$(echo "$raw" | tr -d '[:space:]')
  if [ -z "$raw" ]; then
    echo "$default"
  elif [[ "$raw" =~ ^[0-9]{1,3}$ ]] && [ "$((10#$raw))" -ge 1 ] && [ "$((10#$raw))" -le "${#MODEL_MENU[@]}" ]; then
    # 10# because $(( )) reads a leading zero as octal while [ -le ] reads it as decimal,
    # so 010 passed the bounds check and then indexed the 8th entry.
    echo "${MODEL_MENU[$((10#$raw - 1))]}"
  else
    echo "$raw"
  fi
}

echo "── Models ────────────────────────────────────────────────────────────────"
_i=1
while [ "$_i" -le "$AGENT_COUNT" ]; do
  _engine_var="ENGINE_$_i"
  _model_var="MODEL_$_i"
  _engine="${!_engine_var}"
  _default="$DEFAULT_STRONG_MODEL"
  if [ "$_engine" = "codex" ]; then
    build_model_menu codex "" || exit 1
    _default="${MODEL_MENU[0]}"
  else
    build_model_menu claude "$DEFAULT_STRONG_MODEL" || exit 1
  fi
  printf -v "$_model_var" '%s' "$(pick_model "Agent $_i" "$_default")"
  _i=$((_i+1))
done
MODEL_2=${MODEL_2:-$DEFAULT_STRONG_MODEL}; MODEL_3=${MODEL_3:-$DEFAULT_STRONG_MODEL}; MODEL_4=${MODEL_4:-$DEFAULT_STRONG_MODEL}
ORCH_MODEL="$MODEL_1"; WORKER_MODEL="$MODEL_2"
echo "──────────────────────────────────────────────────────────────────────────"
echo ""

# ── Effort ─────────────────────────────────────────────────────────────────────
EFFORT_CHOICES=("xhigh" "high" "medium" "low")
DEFAULT_HIGH_EFFORT="xhigh"
DEFAULT_LOW_EFFORT="high"

# pick_effort <label> <default> — prints the chosen effort on stdout.
# Input: 1-4 selects from EFFORT_CHOICES, empty takes the default, anything
# else is used verbatim.
pick_effort() {
  local label="$1" default="$2" raw
  echo "  $label effort:" >&2
  echo "    1) xhigh   2) high   3) medium   4) low" >&2
  read -p "  [default: $default] > " raw
  raw=$(echo "$raw" | tr -d '[:space:]')
  case "$raw" in
    "")      echo "$default" ;;
    1|2|3|4) echo "${EFFORT_CHOICES[$((raw-1))]}" ;;
    *)       echo "$raw" ;;
  esac
}

echo "── Effort ────────────────────────────────────────────────────────────────"
if [ "$AGENT_COUNT" = "1" ]; then
  ORCH_EFFORT=$(pick_effort "Agent" "$DEFAULT_HIGH_EFFORT")
  WORKER_EFFORT="$ORCH_EFFORT"
else
  echo "  1) Orchestrator high, workers lower"
  echo "  2) All four high"
  echo "  3) All four lower"
  read -p "  Pick [1/2/3] (default 1): " RAW_EFFORT_PRESET
  EFFORT_PRESET=$(echo "${RAW_EFFORT_PRESET:-1}" | tr -d '[:space:]')
  [[ "$EFFORT_PRESET" =~ ^[123]$ ]] || EFFORT_PRESET=1
  echo ""

  case "$EFFORT_PRESET" in
    1)
      ORCH_EFFORT=$(pick_effort "High" "$DEFAULT_HIGH_EFFORT")
      WORKER_EFFORT=$(pick_effort "Lower" "$DEFAULT_LOW_EFFORT")
      ;;
    2)
      ORCH_EFFORT=$(pick_effort "High" "$DEFAULT_HIGH_EFFORT")
      WORKER_EFFORT="$ORCH_EFFORT"
      ;;
    3)
      ORCH_EFFORT=$(pick_effort "Lower" "$DEFAULT_LOW_EFFORT")
      WORKER_EFFORT="$ORCH_EFFORT"
      ;;
  esac
fi
echo "──────────────────────────────────────────────────────────────────────────"
echo ""

EFFORT_1="$ORCH_EFFORT"
EFFORT_2="$WORKER_EFFORT"
EFFORT_3="$WORKER_EFFORT"
EFFORT_4="$WORKER_EFFORT"

# ── Project Setup ──────────────────────────────────────────────────────────────
echo "── Project Setup ─────────────────────────────────────────────────────────"
echo "  Swarm $SWARM_ID"
echo ""
read -p "  New project or resume existing? [n/r]: " RAW_PROJECT_MODE
echo "──────────────────────────────────────────────────────────────────────────"
echo ""
PROJECT_MODE=$(echo "${RAW_PROJECT_MODE:-n}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

ACTIVE_PROJECT_VALUE=""
if [ "$PROJECT_MODE" = "n" ]; then
  echo "  Project name (e.g. GBO-123: add-checkout-flow):"
  read -p "  > " RAW_PROJECT_NAME
  ACTIVE_PROJECT_VALUE=$(echo "${RAW_PROJECT_NAME}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9:_-]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')
  if [ -z "$ACTIVE_PROJECT_VALUE" ]; then
    ACTIVE_PROJECT_VALUE="project-$(date +%Y%m%d-%H%M%S)"
  fi
  echo "  Project ID: $ACTIVE_PROJECT_VALUE"
  echo ""
elif [ "$PROJECT_MODE" = "r" ]; then
  # List projects/ subdirs excluding inbox
  PROJECT_LIST=()
  if [ -d "$SCRIPT_DIR/projects" ]; then
    while IFS= read -r d; do
      name=$(basename "$d")
      [ "$name" = "inbox" ] && continue
      PROJECT_LIST+=("$name")
    done < <(find "$SCRIPT_DIR/projects" -mindepth 1 -maxdepth 1 -type d | sort)
  fi

  if [ ${#PROJECT_LIST[@]} -eq 0 ]; then
    echo "  No existing projects found. Starting as new."
  else
    echo "  Existing projects:"
    for i in "${!PROJECT_LIST[@]}"; do
      echo "    $((i+1))) ${PROJECT_LIST[$i]}"
    done
    echo ""
    read -p "  Pick a project number: " RAW_PROJECT_NUM
    PROJECT_NUM=$(echo "${RAW_PROJECT_NUM}" | tr -d '[:space:]')
    if [[ "$PROJECT_NUM" =~ ^[0-9]+$ ]] && [ "$PROJECT_NUM" -ge 1 ] && [ "$PROJECT_NUM" -le "${#PROJECT_LIST[@]}" ]; then
      ACTIVE_PROJECT_VALUE="${PROJECT_LIST[$((PROJECT_NUM-1))]}"
      echo "  Resuming: $ACTIVE_PROJECT_VALUE"
    else
      echo "  Invalid selection. Starting as new."
    fi
  fi
  echo ""
fi

# Each pane's SessionStart hook reads ACTIVE_PROJECT, so it must exist before any pane
# starts. Writing it after the panes launched made the protocol load a race.
SWARM_DIR="$SCRIPT_DIR/swarms/$SWARM_ID"
mkdir -p "$SWARM_DIR"
printf '%s' "$ACTIVE_PROJECT_VALUE" > "$SWARM_DIR/ACTIVE_PROJECT"
# Read by the startup protocol so Agent 1 knows whether to run the comms check —
# in solo mode there are no workers to check in with.
printf '%s' "$AGENT_COUNT" > "$SWARM_DIR/AGENT_COUNT"

# Refuse to start panes whose startup protocol would not load. The hook fails open at
# runtime, so this is the last point where a broken one can still stop a launch.
source "$SCRIPT_DIR/tools/preflight-hook.sh"
ENGINES_ALL="${ENGINE_1:-claude} ${ENGINE_2:-claude} ${ENGINE_3:-claude} ${ENGINE_4:-claude}"
CLAUDE_AGENTS=""
_i=0
for _e in $ENGINES_ALL; do
  _i=$((_i+1))
  [ "$_i" -le "$AGENT_COUNT" ] || continue
  case "$_e" in ""|claude) CLAUDE_AGENTS="$CLAUDE_AGENTS $_i" ;; esac
done

report_engine_gating "$ENGINES_ALL"
check_bifrost "$ENGINES_ALL" "$GATEWAY_1 $GATEWAY_2 $GATEWAY_3 $GATEWAY_4" || exit 1

if ! validate_models "MODEL_1=$MODEL_1
EFFORT_1=$EFFORT_1
MODEL_2=$MODEL_2
EFFORT_2=$EFFORT_2
MODEL_3=$MODEL_3
EFFORT_3=$EFFORT_3
MODEL_4=$MODEL_4
EFFORT_4=$EFFORT_4" "$ENGINES_ALL"; then
  exit 1
fi
if [ -n "${SWARM_SKIP_PREFLIGHT:-}" ]; then
  echo "  WARNING: SWARM_SKIP_PREFLIGHT is set. Launching WITHOUT verifying the startup hook." >&2
elif [ -z "$CLAUDE_AGENTS" ]; then
  echo "  No claude panes in this swarm; skipping the SessionStart hook preflight." >&2
elif ! preflight_hook "$SCRIPT_DIR/.claude/settings.json" "$SCRIPT_DIR" "$SWARM_ID" $CLAUDE_AGENTS; then
  echo "  Launch aborted. Set SWARM_SKIP_PREFLIGHT=1 to override deliberately." >&2
  exit 1
fi

# Per-pane engine. Default claude, so a launch with nothing set behaves exactly as it
# did before this existed. Setting ENGINE_n=codex builds a Codex pane; no pane is set
# to codex by this repo.
CMD1=$(engine_cmd 1 "$ENGINE_1" "$MODEL_1" "$EFFORT_1" "" "$ORCH_TOOL_FLAGS" "$GATEWAY_1") || exit 1
CMD2=$(engine_cmd 2 "$ENGINE_2" "$MODEL_2" "$EFFORT_2" "" "$THINK_FLAG" "$GATEWAY_2") || exit 1
CMD3=$(engine_cmd 3 "$ENGINE_3" "$MODEL_3" "$EFFORT_3" "" "$THINK_FLAG" "$GATEWAY_3") || exit 1
CMD4=$(engine_cmd 4 "$ENGINE_4" "$MODEL_4" "$EFFORT_4" "" "$THINK_FLAG" "$GATEWAY_4") || exit 1

# The commands are embedded in AppleScript double-quoted strings below.
CMD1=$(applescript_escape "$CMD1"); CMD2=$(applescript_escape "$CMD2")
CMD3=$(applescript_escape "$CMD3"); CMD4=$(applescript_escape "$CMD4")

echo "Launching agent workspace in iTerm2..."

if [ "$AGENT_COUNT" = "1" ]; then
  SESSION_IDS=$(osascript -e "
tell application \"iTerm2\"
  activate

  -- Create a new window
  set newWindow to (create window with default profile)

  tell newWindow
    set agent1Session to current session of current tab

    -- Label and start Claude (AGENT_NUMBER exported so startup hook knows which agent this is)
    tell agent1Session
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && export AGENT_NUMBER=1 && echo '═══════════════════════════════════════' && echo '  AGENT 1  $MODEL_1 · effort: $EFFORT_1' && echo '═══════════════════════════════════════' && $CMD1\"
    end tell

    return unique id of agent1Session
  end tell
end tell
")
  ID1="$SESSION_IDS"; ID2=""; ID3=""; ID4=""
else
  SESSION_IDS=$(osascript -e "
tell application \"iTerm2\"
  activate

  -- Create a new window
  set newWindow to (create window with default profile)

  tell newWindow
    set agent1Session to current session of current tab

    -- Split right -> Agent 2
    tell agent1Session
      set agent2Session to (split vertically with default profile)
    end tell

    -- Split Agent 1 down -> Agent 3
    tell agent1Session
      set agent3Session to (split horizontally with default profile)
    end tell

    -- Split Agent 2 down -> Agent 4
    tell agent2Session
      set agent4Session to (split horizontally with default profile)
    end tell

    -- Label and start Claude in each pane (AGENT_NUMBER exported so startup hook knows which agent this is)
    tell agent1Session
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && export AGENT_NUMBER=1 && echo '═══════════════════════════════════════' && echo '  AGENT 1 — ORCHESTRATOR  $MODEL_1 · effort: $EFFORT_1' && echo '═══════════════════════════════════════' && $CMD1\"
    end tell
    tell agent2Session
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && export AGENT_NUMBER=2 && echo '═══════════════════════════════════════' && echo '  AGENT 2  $MODEL_2 · effort: $EFFORT_2' && echo '═══════════════════════════════════════' && $CMD2\"
    end tell
    tell agent3Session
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && export AGENT_NUMBER=3 && echo '═══════════════════════════════════════' && echo '  AGENT 3  $MODEL_3 · effort: $EFFORT_3' && echo '═══════════════════════════════════════' && $CMD3\"
    end tell
    tell agent4Session
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && export AGENT_NUMBER=4 && echo '═══════════════════════════════════════' && echo '  AGENT 4  $MODEL_4 · effort: $EFFORT_4' && echo '═══════════════════════════════════════' && $CMD4\"
    end tell

    -- Return session IDs
    set id1 to unique id of agent1Session
    set id2 to unique id of agent2Session
    set id3 to unique id of agent3Session
    set id4 to unique id of agent4Session

    return id1 & \",\" & id2 & \",\" & id3 & \",\" & id4
  end tell
end tell
")
  IFS=',' read -r ID1 ID2 ID3 ID4 <<< "$SESSION_IDS"
fi

# Write swarms/N/pane-config.sh
cat > "$SWARM_DIR/pane-config.sh" << EOF
# iTerm2 pane session IDs — generated by launch.sh on $(date)
# Swarm $SWARM_ID — Re-run ./launch.sh to regenerate after restarting iTerm2
AGENT_1_SESSION="$ID1"
AGENT_2_SESSION="$ID2"
AGENT_3_SESSION="$ID3"
AGENT_4_SESSION="$ID4"
EOF

# Record launch parameters so restart-swarm.sh can relaunch faithfully.
cat > "$SWARM_DIR/launch.env" << EOF
# Launch parameters — consumed by restart-swarm.sh
AGENT_COUNT='$AGENT_COUNT'
MODEL_1='$MODEL_1'
MODEL_2='$MODEL_2'
MODEL_3='$MODEL_3'
MODEL_4='$MODEL_4'
EFFORT_1='$EFFORT_1'
EFFORT_2='$EFFORT_2'
EFFORT_3='$EFFORT_3'
EFFORT_4='$EFFORT_4'
ENGINE_1='$ENGINE_1'
ENGINE_2='$ENGINE_2'
ENGINE_3='$ENGINE_3'
ENGINE_4='$ENGINE_4'
GATEWAY_1='$GATEWAY_1'
GATEWAY_2='$GATEWAY_2'
GATEWAY_3='$GATEWAY_3'
GATEWAY_4='$GATEWAY_4'
THINK_PROMPT='Think deeply and use extended reasoning. Explore edge cases and alternatives. Prefer thoroughness over brevity.'
EOF

echo ""
echo "✓ iTerm2 workspace launched"
echo "✓ swarms/$SWARM_ID/pane-config.sh written"
echo ""
echo "  Swarm:               $SWARM_ID"
echo "  Active project:      ${ACTIVE_PROJECT_VALUE:-<new — Agent 1 will set>}"
echo ""
echo "  Agent 1 (you): $ID1  ·  $MODEL_1 · effort $EFFORT_1"
if [ "$AGENT_COUNT" = "4" ]; then
  echo "  Agent 2:       $ID2  ·  $MODEL_2 · effort $EFFORT_2"
  echo "  Agent 3:       $ID3  ·  $MODEL_3 · effort $EFFORT_3"
  echo "  Agent 4:       $ID4  ·  $MODEL_4 · effort $EFFORT_4"
fi
echo ""
if [ "$AGENT_COUNT" = "1" ]; then
  echo "Engine starting: ${ENGINE_1:-claude}"
else
  echo "Engines starting: $ENGINES_ALL"
fi
echo ""

# ── Startup kick ───────────────────────────────────────────────────────────────
# The SessionStart hook injects startup instructions into each agent's context,
# but the model still needs a user message to begin acting on them.
# We wait for Claude to fully initialize (MCP servers, plugins, etc.) then send
# a kick message to each pane so they immediately execute the startup protocol.
echo "Waiting 10s for Claude to initialize..."
sleep 10

echo "Sending startup kick..."
export SWARM_ID
# A codex pane already received its bootstrap as engine_cmd's positional prompt, so a
# kick here would be a second, racing start.
for _a in $(seq 1 "$AGENT_COUNT"); do
  _ev="ENGINE_$_a"
  case "${!_ev:-claude}" in
    ""|claude) ./send-to-agent.sh "$_a" "Execute your startup protocol now." ;;
    *) echo "  pane $_a: ${!_ev}, bootstrapped at launch, no kick sent." ;;
  esac
done

echo ""
if [ "$AGENT_COUNT" = "1" ]; then
  echo "✓ Startup kick sent — the agent is now executing its startup protocol."
  echo ""
  echo "To send it a message later:"
  echo "  ./send-to-agent.sh 1 \"Your message here\""
else
  echo "✓ Startup kicks sent — agents are now executing their protocols."
  echo "  Watch all 4 panes to see them read files and send confirmations to each other."
  echo ""
  echo "To send a message to an agent later:"
  echo "  ./send-to-agent.sh 2 \"Your message here\""
fi
