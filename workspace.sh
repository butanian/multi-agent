#!/usr/bin/env bash
# workspace.sh — Launch multiple project tabs in the current iTerm2 window
#
# Usage: ./workspace.sh
#
# Scans projects/ for existing projects, lets you pick which to open,
# then creates one tab per project in the frontmost iTerm2 window.
# Each tab gets 4 agent panes, a named title, and its own swarm ID.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Helpers ────────────────────────────────────────────────────────────────────

next_swarm_id() {
  local id=1
  if [ -d "$SCRIPT_DIR/swarms" ]; then
    for d in "$SCRIPT_DIR/swarms"/*/; do
      [ -d "$d" ] || continue
      local num
      num=$(basename "$d")
      if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge "$id" ]; then
        id=$((num + 1))
      fi
    done
  fi
  echo "$id"
}

# ── Project list ───────────────────────────────────────────────────────────────

PROJECT_LIST=()
if [ -d "$SCRIPT_DIR/projects" ]; then
  while IFS= read -r d; do
    local_name=$(basename "$d")
    [ "$local_name" = "inbox" ] && continue
    PROJECT_LIST+=("$local_name")
  done < <(find "$SCRIPT_DIR/projects" -mindepth 1 -maxdepth 1 -type d | sort)
fi

if [ ${#PROJECT_LIST[@]} -eq 0 ]; then
  echo "No projects found in projects/. Create a subdirectory there first."
  exit 1
fi

# ── Project selection ──────────────────────────────────────────────────────────

echo "── Workspace Launcher ────────────────────────────────────────────────────"
echo ""
echo "  Which projects to open? (space-separated numbers, or 'all')"
echo ""
for i in "${!PROJECT_LIST[@]}"; do
  printf "    %2d) %s\n" "$((i+1))" "${PROJECT_LIST[$i]}"
done
echo ""
read -p "  > " RAW_SELECTION
echo ""

SELECTED=()
if [[ "$RAW_SELECTION" =~ ^[[:space:]]*all[[:space:]]*$ ]]; then
  SELECTED=("${PROJECT_LIST[@]}")
else
  for num in $RAW_SELECTION; do
    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#PROJECT_LIST[@]}" ]; then
      SELECTED+=("${PROJECT_LIST[$((num-1))]}")
    fi
  done
fi

if [ ${#SELECTED[@]} -eq 0 ]; then
  echo "No valid projects selected. Exiting."
  exit 1
fi

# ── Permissions ────────────────────────────────────────────────────────────────

echo "── Settings ──────────────────────────────────────────────────────────────"
read -p "  Dangerously skip permissions? [y/N]: " RAW_SKIP_PERMS
echo "──────────────────────────────────────────────────────────────────────────"
echo ""

SKIP_PERMS=$(echo "${RAW_SKIP_PERMS:-n}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
PERMS_FLAG=""
[[ "$SKIP_PERMS" == "y" ]] && PERMS_FLAG="--dangerously-skip-permissions"

source "$SCRIPT_DIR/tools/launcher-common.sh"

# Orchestrator gets the best model at xhigh effort; workers get the 2nd model at high.
ORCH_MODEL="$DEFAULT_STRONG_MODEL";  ORCH_EFFORT="xhigh"
WORKER_MODEL="$DEFAULT_CHEAP_MODEL"; WORKER_EFFORT="high"

if ! validate_models "MODEL_1=$ORCH_MODEL
EFFORT_1=$ORCH_EFFORT
MODEL_2=$WORKER_MODEL
EFFORT_2=$WORKER_EFFORT"; then
  exit 1
fi

THINK_FLAG="--append-system-prompt 'Think deeply and use extended reasoning. Explore edge cases and alternatives. Prefer thoroughness over brevity.'"
CMD_ORCH="claude --model '$ORCH_MODEL' --effort $ORCH_EFFORT $PERMS_FLAG $ORCH_TOOL_FLAGS"
CMD_WORKER="claude --model '$WORKER_MODEL' --effort $WORKER_EFFORT $PERMS_FLAG $THINK_FLAG"

# ── Launch tabs ────────────────────────────────────────────────────────────────

SWARM_CONFIGS=()

for PROJECT_ID in "${SELECTED[@]}"; do
  SWARM_ID=$(next_swarm_id)

  # Each pane's SessionStart hook reads ACTIVE_PROJECT, so it must exist before any pane starts.
  SWARM_DIR="$SCRIPT_DIR/swarms/$SWARM_ID"
  mkdir -p "$SWARM_DIR"
  printf '%s' "$PROJECT_ID" > "$SWARM_DIR/ACTIVE_PROJECT"

  # Refuse to start panes whose startup protocol would not load. The hook fails open at
  # runtime, so this is the last point where a broken one can still stop a launch.
  source "$SCRIPT_DIR/tools/preflight-hook.sh"
  if [ -n "${SWARM_SKIP_PREFLIGHT:-}" ]; then
    echo "  WARNING: SWARM_SKIP_PREFLIGHT is set. Launching WITHOUT verifying the startup hook." >&2
  elif ! preflight_hook "$SCRIPT_DIR/.claude/settings.json" "$SCRIPT_DIR" "$SWARM_ID" 1 2 3 4; then
    echo "  Launch aborted. Set SWARM_SKIP_PREFLIGHT=1 to override deliberately." >&2
    exit 1
  fi

  echo "  Opening tab: $PROJECT_ID (swarm $SWARM_ID)..."

  SESSION_IDS=$(osascript -e "
  tell application \"iTerm2\"
    activate

    set targetWindow to current window

    tell targetWindow
      set newTab to (create tab with default profile)

      set agent1Session to current session of newTab

      tell agent1Session
        set agent2Session to (split vertically with default profile)
      end tell
      tell agent1Session
        set agent3Session to (split horizontally with default profile)
      end tell
      tell agent2Session
        set agent4Session to (split horizontally with default profile)
      end tell

      -- Set tab title via escape code in agent 1
      tell agent1Session
        write text \"printf '\\\\033]0;$PROJECT_ID\\\\007' && cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && export AGENT_NUMBER=1 && echo '═══════════════════════════════════════' && echo '  AGENT 1 — ORCHESTRATOR  $ORCH_MODEL · effort: $ORCH_EFFORT' && echo '═══════════════════════════════════════' && $CMD_ORCH\"
      end tell
      tell agent2Session
        write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && export AGENT_NUMBER=2 && echo '═══════════════════════════════════════' && echo '  AGENT 2  $WORKER_MODEL · effort: $WORKER_EFFORT' && echo '═══════════════════════════════════════' && $CMD_WORKER\"
      end tell
      tell agent3Session
        write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && export AGENT_NUMBER=3 && echo '═══════════════════════════════════════' && echo '  AGENT 3  $WORKER_MODEL · effort: $WORKER_EFFORT' && echo '═══════════════════════════════════════' && $CMD_WORKER\"
      end tell
      tell agent4Session
        write text \"cd '$SCRIPT_DIR' && export SWARM_ID=$SWARM_ID && export AGENT_NUMBER=4 && echo '═══════════════════════════════════════' && echo '  AGENT 4  $WORKER_MODEL · effort: $WORKER_EFFORT' && echo '═══════════════════════════════════════' && $CMD_WORKER\"
      end tell

      set id1 to unique id of agent1Session
      set id2 to unique id of agent2Session
      set id3 to unique id of agent3Session
      set id4 to unique id of agent4Session

      return id1 & \",\" & id2 & \",\" & id3 & \",\" & id4
    end tell
  end tell
  ")

  IFS=',' read -r ID1 ID2 ID3 ID4 <<< "$SESSION_IDS"

  cat > "$SWARM_DIR/pane-config.sh" << EOF
# iTerm2 pane session IDs — generated by workspace.sh on $(date)
# Swarm $SWARM_ID — Project: $PROJECT_ID
AGENT_1_SESSION="$ID1"
AGENT_2_SESSION="$ID2"
AGENT_3_SESSION="$ID3"
AGENT_4_SESSION="$ID4"
EOF

  # Record launch parameters so restart-swarm.sh can relaunch faithfully.
  cat > "$SWARM_DIR/launch.env" << EOF
# Launch parameters — consumed by restart-swarm.sh
MODEL_1='$ORCH_MODEL'
MODEL_2='$WORKER_MODEL'
MODEL_3='$WORKER_MODEL'
MODEL_4='$WORKER_MODEL'
EFFORT_1='$ORCH_EFFORT'
EFFORT_2='$WORKER_EFFORT'
EFFORT_3='$WORKER_EFFORT'
EFFORT_4='$WORKER_EFFORT'
SKIP_PERMS='$SKIP_PERMS'
THINK_PROMPT='Think deeply and use extended reasoning. Explore edge cases and alternatives. Prefer thoroughness over brevity.'
EOF

  SWARM_CONFIGS+=("$PROJECT_ID:$SWARM_ID")
  echo "    swarms/$SWARM_ID/pane-config.sh written"

  # Brief pause between tabs to avoid iTerm2 race conditions
  sleep 1
done

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo "── Launched ──────────────────────────────────────────────────────────────"
for config in "${SWARM_CONFIGS[@]}"; do
  IFS=':' read -r proj swarm <<< "$config"
  printf "  %-30s swarm %s\n" "$proj" "$swarm"
done
echo ""

echo "Waiting 10s for Claude to initialize in all panes..."
sleep 10

echo "Sending startup kicks..."
for config in "${SWARM_CONFIGS[@]}"; do
  IFS=':' read -r proj swarm <<< "$config"
  export SWARM_ID=$swarm
  ./send-to-agent.sh 1 "Execute your startup protocol now."
  ./send-to-agent.sh 2 "Execute your startup protocol now."
  ./send-to-agent.sh 3 "Execute your startup protocol now."
  ./send-to-agent.sh 4 "Execute your startup protocol now."
done

echo ""
echo "All agents started. Use ./send-to-agent.sh <N> to message an agent."
echo "Monitor status at projects/{id}/agentN.md."
