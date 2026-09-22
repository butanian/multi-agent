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

# ── Permissions ────────────────────────────────────────────────────────────────
echo "── Permissions ───────────────────────────────────────────────────────────"
read -p "  Dangerously skip permissions? [y/N]: " RAW_SKIP_PERMS
echo "──────────────────────────────────────────────────────────────────────────"
echo ""
SKIP_PERMS=$(echo "${RAW_SKIP_PERMS:-n}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
PERMS_FLAG=""
[[ "$SKIP_PERMS" == "y" ]] && PERMS_FLAG="--dangerously-skip-permissions"

# ── Models ─────────────────────────────────────────────────────────────────────
# The menu is the account's entitled list, never a literal. A hardcoded list goes stale
# silently: it offers models the account cannot run and hides ones it can.
MODEL_MENU=()
build_model_menu() {
  local err list m rc=0
  if [ -z "${DEFAULT_STRONG_MODEL:-}" ] || [ -z "${DEFAULT_CHEAP_MODEL:-}" ]; then
    printf 'LAUNCH REFUSED: %s\n  assertion: DEFAULT_STRONG_MODEL and DEFAULT_CHEAP_MODEL are both set\n  one is empty, so panes would start as: claude --model %s\n  Fix: define both in tools/launcher-common.sh\n' \
      "$SCRIPT_DIR/tools/launcher-common.sh" "''" >&2
    return 1
  fi
  err=$(mktemp)
  list=$("$SCRIPT_DIR/tools/model-lookup.py" --list-entitled 2>"$err") || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "${list//[[:space:]]/}" ]; then
    printf 'LAUNCH REFUSED: %s --list-entitled\n  assertion: the entitled model list is readable\n%s\n  Fix: run it by hand to see why. There is no hardcoded fallback, because a stale list is the defect this replaced.\n' \
      "$SCRIPT_DIR/tools/model-lookup.py" "$(sed 's/^/  /' "$err")" >&2
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  # rc 0 with the wrong shape is the same failure in disguise: model-lookup.py ignores an
  # unrecognised flag and prints its human report, which would become the menu.
  if printf '%s\n' "$list" | /usr/bin/grep -qvE '^[A-Za-z0-9._-]+(\[1m\])?$|^$'; then
    printf 'LAUNCH REFUSED: %s --list-entitled\n  assertion: it prints bare model ids, one per line\n  first offending line: %s\n  Fix: the flag is unimplemented or the output format changed.\n' \
      "$SCRIPT_DIR/tools/model-lookup.py" \
      "$(printf '%s\n' "$list" | /usr/bin/grep -m1 -vE '^[A-Za-z0-9._-]+(\[1m\])?$|^$')" >&2
    return 1
  fi
  # Refused rather than omitted: dropping an unentitled default would silently shift
  # option 1 onto a different model.
  for m in "$DEFAULT_STRONG_MODEL" "$DEFAULT_CHEAP_MODEL"; do
    if ! printf '%s\n' "$list" | /usr/bin/grep -qxF "$m"; then
      printf 'LAUNCH REFUSED: %s\n  assertion: every preset default is entitled for this account\n  %s is not in --list-entitled\n  Fix: change the default, or type the id as free text if you believe the list is wrong.\n' \
        "$SCRIPT_DIR/tools/launcher-common.sh" "$m" >&2
      return 1
    fi
  done
  MODEL_MENU=("$DEFAULT_STRONG_MODEL")
  if [ "$DEFAULT_CHEAP_MODEL" != "$DEFAULT_STRONG_MODEL" ]; then
    MODEL_MENU+=("$DEFAULT_CHEAP_MODEL")
  fi
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    case "$m" in "$DEFAULT_STRONG_MODEL"|"$DEFAULT_CHEAP_MODEL") continue ;; esac
    MODEL_MENU+=("$m")
  done < <(printf '%s\n' "$list" | sort -u)
}

# pick_model <label> <default> — prints the chosen model id on stdout.
# A number selects from MODEL_MENU, empty takes the default, anything else is used
# verbatim and validated with the rest before any pane starts.
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

build_model_menu || exit 1

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

# Each pane's SessionStart hook reads ACTIVE_PROJECT, so it must exist before any pane
# starts. Writing it after the panes launched made the protocol load a race.
SWARM_DIR="$SCRIPT_DIR/swarms/$SWARM_ID"
mkdir -p "$SWARM_DIR"
printf '%s' "$ACTIVE_PROJECT_VALUE" > "$SWARM_DIR/ACTIVE_PROJECT"

# Refuse to start panes whose startup protocol would not load. The hook fails open at
# runtime, so this is the last point where a broken one can still stop a launch.
source "$SCRIPT_DIR/tools/preflight-hook.sh"
ENGINES_ALL="${ENGINE_1:-claude} ${ENGINE_2:-claude} ${ENGINE_3:-claude} ${ENGINE_4:-claude}"
CLAUDE_AGENTS=""
_i=0
for _e in $ENGINES_ALL; do
  _i=$((_i+1))
  case "$_e" in ""|claude) CLAUDE_AGENTS="$CLAUDE_AGENTS $_i" ;; esac
done

report_engine_gating "$ENGINES_ALL"

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
ENGINE_1="${ENGINE_1:-claude}"
ENGINE_2="${ENGINE_2:-claude}"
ENGINE_3="${ENGINE_3:-claude}"
ENGINE_4="${ENGINE_4:-claude}"

CMD1=$(engine_cmd 1 "$ENGINE_1" "$MODEL_1" "$EFFORT_1" "$PERMS_FLAG" "$ORCH_TOOL_FLAGS") || exit 1
CMD2=$(engine_cmd 2 "$ENGINE_2" "$MODEL_2" "$EFFORT_2" "$PERMS_FLAG" "$THINK_FLAG") || exit 1
CMD3=$(engine_cmd 3 "$ENGINE_3" "$MODEL_3" "$EFFORT_3" "$PERMS_FLAG" "$THINK_FLAG") || exit 1
CMD4=$(engine_cmd 4 "$ENGINE_4" "$MODEL_4" "$EFFORT_4" "$PERMS_FLAG" "$THINK_FLAG") || exit 1

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
ENGINE_1='$ENGINE_1'
ENGINE_2='$ENGINE_2'
ENGINE_3='$ENGINE_3'
ENGINE_4='$ENGINE_4'
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
echo "Engines starting: $ENGINES_ALL"
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
# A codex pane already received its bootstrap as engine_cmd's positional prompt, so a
# kick here would be a second, racing start.
for _a in 1 2 3 4; do
  _ev="ENGINE_$_a"
  case "${!_ev:-claude}" in
    ""|claude) ./send-to-agent.sh "$_a" "Execute your startup protocol now." ;;
    *) echo "  pane $_a: ${!_ev}, bootstrapped at launch, no kick sent." ;;
  esac
done

echo ""
echo "✓ Startup kicks sent — agents are now executing their protocols."
echo "  Watch all 4 panes to see them read files and send confirmations to each other."
echo ""
echo "To send a message to an agent later:"
echo "  ./send-to-agent.sh 2 \"Your message here\""
