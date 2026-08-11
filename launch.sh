#!/usr/bin/env bash
# launch.sh — Open iTerm2 with 4 agent panes and capture session IDs
#
# Usage: ./launch.sh
#
# Creates a new iTerm2 window split into 4 panes, starts Claude Code
# in each, and writes session UUIDs to swarms/N/pane-config.sh so that
# send-to-agent.sh can target the right pane.
#
# Layout:
#   ┌─────────────┬─────────────┐
#   │  Agent 1    │  Agent 2    │
#   │ (you/orch.) │             │
#   ├─────────────┼─────────────┤
#   │  Agent 3    │  Agent 4    │
#   │             │             │
#   └─────────────┴─────────────┘

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# ── Permissions ────────────────────────────────────────────────────────────────
echo "── Permissions ───────────────────────────────────────────────────────────"
read -p "  Dangerously skip permissions? [y/N]: " RAW_SKIP_PERMS
echo "──────────────────────────────────────────────────────────────────────────"
echo ""
SKIP_PERMS=$(echo "${RAW_SKIP_PERMS:-n}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
PERMS_FLAG=""
[[ "$SKIP_PERMS" == "y" ]] && PERMS_FLAG="--dangerously-skip-permissions"

# ── Models ─────────────────────────────────────────────────────────────────────
MODEL_CHOICES=("claude-fable-5" "claude-opus-5" "claude-sonnet-5" "claude-haiku-4-5")
DEFAULT_STRONG_MODEL="claude-fable-5"
DEFAULT_CHEAP_MODEL="claude-opus-5"

# pick_model <label> <default> — prints the chosen model id on stdout.
# Input: 1-4 selects from MODEL_CHOICES, empty takes the default, anything
# else is used verbatim as a model id.
pick_model() {
  local label="$1" default="$2" raw
  echo "  $label model:" >&2
  echo "    1) ${MODEL_CHOICES[0]}   2) ${MODEL_CHOICES[1]}   3) ${MODEL_CHOICES[2]}   4) ${MODEL_CHOICES[3]}" >&2
  echo "    or type a model id" >&2
  read -p "  [default: $default] > " raw
  raw=$(echo "$raw" | tr -d '[:space:]')
  case "$raw" in
    "")      echo "$default" ;;
    1|2|3|4) echo "${MODEL_CHOICES[$((raw-1))]}" ;;
    *)       echo "$raw" ;;
  esac
}

echo "── Models ────────────────────────────────────────────────────────────────"
echo "  1) Orchestrator strong, workers cheaper"
echo "  2) All four strong"
echo "  3) All four cheaper"
read -p "  Pick [1/2/3] (default 1): " RAW_MODEL_PRESET
MODEL_PRESET=$(echo "${RAW_MODEL_PRESET:-1}" | tr -d '[:space:]')
[[ "$MODEL_PRESET" =~ ^[123]$ ]] || MODEL_PRESET=1
echo ""

case "$MODEL_PRESET" in
  1)
    ORCH_MODEL=$(pick_model "Strong" "$DEFAULT_STRONG_MODEL")
    WORKER_MODEL=$(pick_model "Cheaper" "$DEFAULT_CHEAP_MODEL")
    ;;
  2)
    ORCH_MODEL=$(pick_model "Strong" "$DEFAULT_STRONG_MODEL")
    WORKER_MODEL="$ORCH_MODEL"
    ;;
  3)
    ORCH_MODEL=$(pick_model "Cheaper" "$DEFAULT_CHEAP_MODEL")
    WORKER_MODEL="$ORCH_MODEL"
    ;;
esac
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
echo "──────────────────────────────────────────────────────────────────────────"
echo ""

MODEL_1="$ORCH_MODEL";  EFFORT_1="$ORCH_EFFORT"
MODEL_2="$WORKER_MODEL"; EFFORT_2="$WORKER_EFFORT"
MODEL_3="$WORKER_MODEL"; EFFORT_3="$WORKER_EFFORT"
MODEL_4="$WORKER_MODEL"; EFFORT_4="$WORKER_EFFORT"

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

CMD1="claude --model '$MODEL_1' --effort $EFFORT_1 $PERMS_FLAG $THINK_FLAG"
CMD2="claude --model '$MODEL_2' --effort $EFFORT_2 $PERMS_FLAG $THINK_FLAG"
CMD3="claude --model '$MODEL_3' --effort $EFFORT_3 $PERMS_FLAG $THINK_FLAG"
CMD4="claude --model '$MODEL_4' --effort $EFFORT_4 $PERMS_FLAG $THINK_FLAG"

echo "Launching agent workspace in iTerm2..."

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

# Parse the four UUIDs
IFS=',' read -r ID1 ID2 ID3 ID4 <<< "$SESSION_IDS"

# Write swarms/N/pane-config.sh
SWARM_DIR="$SCRIPT_DIR/swarms/$SWARM_ID"
mkdir -p "$SWARM_DIR"
printf '%s' "$ACTIVE_PROJECT_VALUE" > "$SWARM_DIR/ACTIVE_PROJECT"
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
MODEL_1='$MODEL_1'
MODEL_2='$MODEL_2'
MODEL_3='$MODEL_3'
MODEL_4='$MODEL_4'
EFFORT_1='$EFFORT_1'
EFFORT_2='$EFFORT_2'
EFFORT_3='$EFFORT_3'
EFFORT_4='$EFFORT_4'
SKIP_PERMS='$SKIP_PERMS'
THINK_PROMPT='Think deeply and use extended reasoning. Explore edge cases and alternatives. Prefer thoroughness over brevity.'
EOF

PERMS_LABEL="no"
[[ "$SKIP_PERMS" == "y" ]] && PERMS_LABEL="YES (--dangerously-skip-permissions)"

echo ""
echo "✓ iTerm2 workspace launched"
echo "✓ swarms/$SWARM_ID/pane-config.sh written"
echo ""
echo "  Swarm:               $SWARM_ID"
echo "  Active project:      ${ACTIVE_PROJECT_VALUE:-<new — Agent 1 will set>}"
echo "  Permissions skipped: $PERMS_LABEL"
echo ""
echo "  Agent 1 (you): $ID1  ·  $MODEL_1 · effort $EFFORT_1"
echo "  Agent 2:       $ID2  ·  $MODEL_2 · effort $EFFORT_2"
echo "  Agent 3:       $ID3  ·  $MODEL_3 · effort $EFFORT_3"
echo "  Agent 4:       $ID4  ·  $MODEL_4 · effort $EFFORT_4"
echo ""
echo "Claude is starting in all 4 panes."
echo ""

# ── Startup kick ───────────────────────────────────────────────────────────────
# The SessionStart hook injects startup instructions into each agent's context,
# but the model still needs a user message to begin acting on them.
# We wait for Claude to fully initialize (MCP servers, plugins, etc.) then send
# a kick message to each pane so they immediately execute the startup protocol.
echo "Waiting 10s for Claude to initialize in all panes..."
sleep 10

echo "Sending startup kick to all agents..."
export SWARM_ID
./send-to-agent.sh 1 "Execute your startup protocol now."
./send-to-agent.sh 2 "Execute your startup protocol now."
./send-to-agent.sh 3 "Execute your startup protocol now."
./send-to-agent.sh 4 "Execute your startup protocol now."

echo ""
echo "✓ Startup kicks sent — agents are now executing their protocols."
echo "  Watch all 4 panes to see them read files and send confirmations to each other."
echo ""
echo "To send a message to an agent later:"
echo "  ./send-to-agent.sh 2 \"Your message here\""
