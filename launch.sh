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

# ── Project Setup ──────────────────────────────────────────────────────────────
echo "── Project Setup ─────────────────────────────────────────────────────────"
echo "  Swarm $SWARM_ID"
echo ""
read -p "  New project or resume existing? [n/r]: " RAW_PROJECT_MODE
echo "──────────────────────────────────────────────────────────────────────────"
echo ""
PROJECT_MODE=$(echo "${RAW_PROJECT_MODE:-n}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

ACTIVE_PROJECT_VALUE=""
if [ "$PROJECT_MODE" = "r" ]; then
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

CMD="claude --model claude-opus-4-6 $PERMS_FLAG $THINK_FLAG"

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

    -- Label and start Claude in each pane
    tell agent1Session
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && echo '═══════════════════════════════════════' && echo '  AGENT 1 — ORCHESTRATOR  thinking: 3 (high)' && echo '═══════════════════════════════════════' && $CMD\"
    end tell
    tell agent2Session
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && echo '═══════════════════════════════════════' && echo '  AGENT 2  thinking: 3 (high)' && echo '═══════════════════════════════════════' && $CMD\"
    end tell
    tell agent3Session
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && echo '═══════════════════════════════════════' && echo '  AGENT 3  thinking: 3 (high)' && echo '═══════════════════════════════════════' && $CMD\"
    end tell
    tell agent4Session
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && echo '═══════════════════════════════════════' && echo '  AGENT 4  thinking: 3 (high)' && echo '═══════════════════════════════════════' && $CMD\"
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

PERMS_LABEL="no"
[[ "$SKIP_PERMS" == "y" ]] && PERMS_LABEL="YES (--dangerously-skip-permissions)"

echo ""
echo "✓ iTerm2 workspace launched"
echo "✓ swarms/$SWARM_ID/pane-config.sh written"
echo ""
echo "  Swarm:               $SWARM_ID"
echo "  Active project:      ${ACTIVE_PROJECT_VALUE:-<new — Agent 1 will set>}"
echo "  Permissions skipped: $PERMS_LABEL"
echo "  Thinking:            3 (high)"
echo ""
echo "  Agent 1 (you): $ID1"
echo "  Agent 2:       $ID2"
echo "  Agent 3:       $ID3"
echo "  Agent 4:       $ID4"
echo ""
echo "Claude is starting in all 4 panes."
echo "You are Agent 1 — the orchestrator. Start by giving it a Jira ticket URL."
echo ""
echo "To send a message to another agent:"
echo "  ./send-to-agent.sh 2 \"Your message here\""
