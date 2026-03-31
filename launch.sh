#!/usr/bin/env bash
# launch.sh — Open iTerm2 with 4 agent panes and capture session IDs
#
# Usage: ./launch.sh
#
# Creates a new iTerm2 window split into 4 panes, starts Claude Code
# in each, and writes session UUIDs to pane-config.sh so that
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

# ── Thinking level configuration ───────────────────────────────────────────────
# 1 = light, 2 = medium, 3 = high
thinking_flag() {
  case "$1" in
    1)  echo "--append-system-prompt 'Be concise and direct. Give brief responses unless depth is truly necessary.'" ;;
    3)  echo "--append-system-prompt 'Think deeply and use extended reasoning. Explore edge cases and alternatives. Prefer thoroughness over brevity.'" ;;
    *)  echo "--append-system-prompt 'Think carefully through problems. Balance thoroughness with conciseness.'" ;;
  esac
}

thinking_label() {
  case "$1" in
    1) echo "1 (light)" ;;
    3) echo "3 (high)" ;;
    *) echo "2 (medium)" ;;
  esac
}

echo ""
echo "── Thinking Level ────────────────────────────────────────────────────────"
echo "  1 = light   2 = medium (default)   3 = high"
echo ""
read -p "  Agent 1 (Orchestrator) [1/2/3]: " RAW1
read -p "  Agent 2               [1/2/3]: " RAW2
read -p "  Agent 3               [1/2/3]: " RAW3
read -p "  Agent 4               [1/2/3]: " RAW4
echo "──────────────────────────────────────────────────────────────────────────"
echo ""

# Strip whitespace and default to 2
LEVEL1=$(echo "${RAW1:-2}" | tr -d '[:space:]')
LEVEL2=$(echo "${RAW2:-2}" | tr -d '[:space:]')
LEVEL3=$(echo "${RAW3:-2}" | tr -d '[:space:]')
LEVEL4=$(echo "${RAW4:-2}" | tr -d '[:space:]')

FLAG1=$(thinking_flag "$LEVEL1"); FLAG2=$(thinking_flag "$LEVEL2")
FLAG3=$(thinking_flag "$LEVEL3"); FLAG4=$(thinking_flag "$LEVEL4")

LABEL1=$(thinking_label "$LEVEL1"); LABEL2=$(thinking_label "$LEVEL2")
LABEL3=$(thinking_label "$LEVEL3"); LABEL4=$(thinking_label "$LEVEL4")

# ── Permissions ────────────────────────────────────────────────────────────────
echo "── Permissions ───────────────────────────────────────────────────────────"
read -p "  Dangerously skip permissions? [y/N]: " RAW_SKIP_PERMS
echo "──────────────────────────────────────────────────────────────────────────"
echo ""
SKIP_PERMS=$(echo "${RAW_SKIP_PERMS:-n}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
PERMS_FLAG=""
[[ "$SKIP_PERMS" == "y" ]] && PERMS_FLAG="--dangerously-skip-permissions"

# ── Skip agents ────────────────────────────────────────────────────────────────
echo "── Skip Agents ───────────────────────────────────────────────────────────"
echo "  Enter agent numbers to skip (e.g. 3,4) or leave blank to launch all"
echo ""
read -p "  Skip agents [blank = none]: " RAW_SKIP_AGENTS
echo "──────────────────────────────────────────────────────────────────────────"
echo ""
SKIP_AGENTS=$(echo "${RAW_SKIP_AGENTS}" | tr -d '[:space:]')

should_skip() {
  local n="$1"
  [[ ",$SKIP_AGENTS," == *",$n,"* ]]
}

CMD1="claude --model claude-opus-4-6 $PERMS_FLAG $FLAG1"; CMD2="claude --model claude-opus-4-6 $PERMS_FLAG $FLAG2"
CMD3="claude --model claude-opus-4-6 $PERMS_FLAG $FLAG3"; CMD4="claude --model claude-opus-4-6 $PERMS_FLAG $FLAG4"

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
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && echo '═══════════════════════════════════════' && echo '  AGENT 1 — ORCHESTRATOR  thinking: $LABEL1' && echo '═══════════════════════════════════════'$(should_skip 1 || echo " && $CMD1")\"
    end tell
    tell agent2Session
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && echo '═══════════════════════════════════════' && echo '  AGENT 2  thinking: $LABEL2' && echo '═══════════════════════════════════════'$(should_skip 2 || echo " && $CMD2")\"
    end tell
    tell agent3Session
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && echo '═══════════════════════════════════════' && echo '  AGENT 3  thinking: $LABEL3' && echo '═══════════════════════════════════════'$(should_skip 3 || echo " && $CMD3")\"
    end tell
    tell agent4Session
      write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && echo '═══════════════════════════════════════' && echo '  AGENT 4  thinking: $LABEL4' && echo '═══════════════════════════════════════'$(should_skip 4 || echo " && $CMD4")\"
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
SKIP_LABEL="${SKIP_AGENTS:-none}"

echo ""
echo "✓ iTerm2 workspace launched"
echo "✓ swarms/$SWARM_ID/pane-config.sh written"
echo ""
echo "  Swarm:               $SWARM_ID"
echo "  Permissions skipped: $PERMS_LABEL"
echo "  Agents skipped:      $SKIP_LABEL"
echo ""
echo "  Agent 1 (you): $ID1  [thinking: $LABEL1]$(should_skip 1 && echo "  [SKIPPED]")"
echo "  Agent 2:       $ID2  [thinking: $LABEL2]$(should_skip 2 && echo "  [SKIPPED]")"
echo "  Agent 3:       $ID3  [thinking: $LABEL3]$(should_skip 3 && echo "  [SKIPPED]")"
echo "  Agent 4:       $ID4  [thinking: $LABEL4]$(should_skip 4 && echo "  [SKIPPED]")"
echo ""
echo "Claude is starting in each active pane."
echo "You are Agent 1 — the orchestrator. Start by giving it a Jira ticket URL."
echo ""
echo "To send a message to another agent:"
echo "  ./send-to-agent.sh 2 \"Your message here\""
