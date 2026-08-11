#!/usr/bin/env bash
# restart-swarm.sh — Gracefully checkpoint a swarm's context, then clear it.
#
# Each agent flushes its working state to disk (durable work logs + a kept
# timestamped snapshot). The script then sends /clear to each pane, which wipes
# the conversation/context window so the agents are fast and cheap again WITHOUT
# killing the running claude process. A startup kick re-primes each agent from
# its on-disk files, so no work is lost.
#
# Two modes:
#   soft (default)  Send /clear to each pane. Same process, empty context.
#   --hard          Actually kill claude (Ctrl-C + /exit) and relaunch a fresh
#                   instance in each pane. For a crash, a wedged agent, or a
#                   model change. Replays swarms/N/launch.env (falls back to
#                   launch.sh defaults).
#
# Usage:
#   ./restart-swarm.sh [swarm_id] [flags]
#
#   swarm_id        Which swarm. Defaults to $SWARM_ID, else you are prompted.
#
# Flags:
#   --hard          Kill + relaunch instead of soft /clear.
#   --save-only     Checkpoint + snapshot only. Do not clear or restart.
#   --force         Proceed even if some agents never confirm their checkpoint
#                   (you accept that their unflushed state is lost).
#   --dry-run       Print every action without sending keystrokes. Safe on a
#                   live swarm.
#   --skip-perms    (--hard only) relaunch with --dangerously-skip-permissions
#                   when launch.env is absent.
#   --timeout N     Seconds to wait for checkpoint sentinels (default 180).
#   --self-delay N  Seconds the detached finisher waits before refreshing the
#                   calling agent's own pane (default 8). In-swarm runs only.
#
# Run it EITHER from a plain shell (refreshes all four agents) OR from inside
# one of the agent panes. When run from inside, that agent flushes its own log,
# the three peers are handled synchronously, and the caller's own pane is
# refreshed by a detached finisher so the script does not /clear itself mid-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Capture the *calling* environment before we reassign SWARM_ID for child calls.
CALLER_SWARM="${SWARM_ID:-}"
CALLER_AGENT_ENV="${AGENT_NUMBER:-}"

# ── Defaults (used by --hard when swarms/N/launch.env is missing) ────────────
DEFAULT_MODEL='claude-opus-4-8[1m]'
DEFAULT_EFFORT='xhigh'
DEFAULT_THINK_PROMPT='Think deeply and use extended reasoning. Explore edge cases and alternatives. Prefer thoroughness over brevity.'

# Tunables
TIMEOUT=180          # seconds to wait for all sentinels
SELF_DELAY=8         # seconds the detached finisher waits before self-refresh
SETTLE=2             # seconds to let agents settle after the last sentinel
INIT_WAIT=12         # (--hard) seconds to let a fresh claude boot before the kick
POLL_INTERVAL=3      # seconds between sentinel checks

# ── Arg parsing ──────────────────────────────────────────────────────────────
TARGET_SWARM=""
MODE="soft"
SAVE_ONLY=0
FORCE=0
DRY_RUN=0
SKIP_PERMS_FLAG=0

while [ $# -gt 0 ]; do
  case "$1" in
    --hard)        MODE="hard" ;;
    --soft)        MODE="soft" ;;
    --save-only)   SAVE_ONLY=1 ;;
    --force)       FORCE=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    --skip-perms)  SKIP_PERMS_FLAG=1 ;;
    --timeout)     TIMEOUT="$2"; shift ;;
    --self-delay)  SELF_DELAY="$2"; shift ;;
    -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -48; exit 0 ;;
    -*)            echo "Unknown flag: $1" >&2; exit 1 ;;
    *)             TARGET_SWARM="$1" ;;
  esac
  shift
done

log()  { printf '%s\n' "$*"; }
step() { printf '\n── %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }

# ── Resolve target swarm ─────────────────────────────────────────────────────
if [ -z "$TARGET_SWARM" ]; then
  if [ -n "$CALLER_SWARM" ]; then
    TARGET_SWARM="$CALLER_SWARM"
  else
    log "Active swarms:"
    found=0
    for d in "$SCRIPT_DIR"/swarms/*/; do
      [ -f "$d/pane-config.sh" ] || continue
      id=$(basename "$d")
      proj=$(cat "$d/ACTIVE_PROJECT" 2>/dev/null || echo "?")
      printf "    swarm %-4s  project: %s\n" "$id" "$proj"
      found=1
    done
    [ "$found" = 1 ] || die "No swarms with a pane-config.sh found."
    read -r -p "  Swarm id to refresh: " TARGET_SWARM
  fi
fi

SWARM_DIR="$SCRIPT_DIR/swarms/$TARGET_SWARM"
[ -d "$SWARM_DIR" ] || die "No such swarm: $SWARM_DIR"
[ -f "$SWARM_DIR/pane-config.sh" ] || die "Missing $SWARM_DIR/pane-config.sh (run launch.sh first)."

# shellcheck disable=SC1090
source "$SWARM_DIR/pane-config.sh"
PROJECT_ID="$(cat "$SWARM_DIR/ACTIVE_PROJECT" 2>/dev/null || echo "")"
PROJECT_DIR="$SCRIPT_DIR/projects/$PROJECT_ID"

PANES=("$AGENT_1_SESSION" "$AGENT_2_SESSION" "$AGENT_3_SESSION" "$AGENT_4_SESSION")
uuid_for() { echo "${PANES[$(($1 - 1))]}"; }

# Are we running from inside this swarm? If so, which agent are we?
CALLER_AGENT=""
if [ -n "$CALLER_AGENT_ENV" ] && [ "$CALLER_SWARM" = "$TARGET_SWARM" ]; then
  CALLER_AGENT="$CALLER_AGENT_ENV"
fi

# Has the project been initialised with work-log files?
PROJECT_HAS_FILES=0
if [ -n "$PROJECT_ID" ] && [ -d "$PROJECT_DIR" ] && ls "$PROJECT_DIR"/*.md >/dev/null 2>&1; then
  PROJECT_HAS_FILES=1
fi

CHECKPOINT_DIR="$SWARM_DIR/checkpoint"

if [ -n "$CALLER_AGENT" ]; then
  INVOKED_FROM="Agent $CALLER_AGENT (in-swarm)"
else
  INVOKED_FROM="external shell"
fi
MODE_LABEL="$([ "$MODE" = hard ] && echo 'hard (kill + relaunch)' || echo 'soft (/clear context)')"
[ "$SAVE_ONLY" = 1 ] && MODE_LABEL="save-only"
log "──────────────────────────────────────────────────────────────"
log "  Refresh swarm $TARGET_SWARM"
log "  Project:        ${PROJECT_ID:-<uninitialised>}"
log "  Invoked from:   $INVOKED_FROM"
log "  Mode:           $MODE_LABEL$([ "$DRY_RUN" = 1 ] && echo '  [DRY RUN]')"
log "──────────────────────────────────────────────────────────────"

# ── osascript helpers ────────────────────────────────────────────────────────
# Type text into a pane (write text presses Enter automatically).
type_in_pane() {
  local uuid="$1" text="$2"
  if [ "$DRY_RUN" = 1 ]; then
    log "    [dry-run] would type into $uuid: $text"
    return 0
  fi
  osascript - "$uuid" "$text" <<'APPLESCRIPT'
on run argv
  set theUuid to item 1 of argv
  set theText to item 2 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if unique id of s is theUuid then
            tell s to write text theText
            return
          end if
        end repeat
      end repeat
    end repeat
  end tell
end run
APPLESCRIPT
}

# Send a single Ctrl-C to interrupt anything in flight (no trailing newline).
interrupt_pane() {
  local uuid="$1"
  [ "$DRY_RUN" = 1 ] && { log "    [dry-run] would Ctrl-C pane $uuid"; return 0; }
  osascript - "$uuid" <<'APPLESCRIPT'
on run argv
  set theUuid to item 1 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if unique id of s is theUuid then
            tell s to write text (character id 3) newline no
            return
          end if
        end repeat
      end repeat
    end repeat
  end tell
end run
APPLESCRIPT
}

# Type a full launch command line into a pane (--hard only; reads from a file to
# dodge quoting issues, same trick send-to-agent.sh uses).
write_line_to_pane() {
  local uuid="$1" file="$2"
  if [ "$DRY_RUN" = 1 ]; then
    log "    [dry-run] would type into $uuid: $(cat "$file")"
    return 0
  fi
  osascript - "$uuid" "$file" <<'APPLESCRIPT'
on run argv
  set theUuid to item 1 of argv
  set theFile to item 2 of argv
  set fileRef to open for access (POSIX file theFile)
  set theText to read fileRef
  close access fileRef
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if unique id of s is theUuid then
            tell s to write text theText
            return
          end if
        end repeat
      end repeat
    end repeat
  end tell
end run
APPLESCRIPT
}

# ── Phase 1: Save / checkpoint ───────────────────────────────────────────────
step "Phase 1 — checkpoint"
mkdir -p "$CHECKPOINT_DIR"
rm -f "$CHECKPOINT_DIR"/agent*.done

# Which agents do we ask to checkpoint? Everyone except the caller (the caller
# flushes its own log itself, since it knows its state and is running this).
CHECKPOINT_AGENTS=()
for a in 1 2 3 4; do
  [ "$a" = "$CALLER_AGENT" ] && continue
  CHECKPOINT_AGENTS+=("$a")
done

if [ "$PROJECT_HAS_FILES" = 0 ]; then
  warn "Project '${PROJECT_ID:-<none>}' has no work-log files. Nothing to flush; skipping checkpoint wait."
else
  for a in "${CHECKPOINT_AGENTS[@]}"; do
    msg="CHECKPOINT before a context refresh (your conversation is about to be /cleared). Write everything you would need to resume cold into projects/$PROJECT_ID/agent$a.md: current state, what is done, decisions, open questions, and exact next steps."
    [ "$a" = 1 ] && msg="$msg Also bring projects/$PROJECT_ID/index.md current (work breakdown statuses, decisions, broadcast log)."
    msg="$msg When fully flushed, as your FINAL action run: touch $CHECKPOINT_DIR/agent$a.done  — then stop and wait."
    if [ "$DRY_RUN" = 1 ]; then
      log "    [dry-run] would send checkpoint message to Agent $a"
    else
      SWARM_ID="$TARGET_SWARM" "$SCRIPT_DIR/send-to-agent.sh" "$a" "$msg" >/dev/null
      log "    checkpoint requested: Agent $a"
    fi
  done
  [ -n "$CALLER_AGENT" ] && log "    Agent $CALLER_AGENT (you) — flush your own work log before this finishes."

  if [ "$DRY_RUN" = 1 ]; then
    log "    [dry-run] would wait up to ${TIMEOUT}s for: ${CHECKPOINT_AGENTS[*]}"
  else
    log "    waiting up to ${TIMEOUT}s for checkpoint confirmations..."
    elapsed=0; missing=("${CHECKPOINT_AGENTS[@]}")
    while [ "$elapsed" -lt "$TIMEOUT" ]; do
      missing=()
      for a in "${CHECKPOINT_AGENTS[@]}"; do
        [ -f "$CHECKPOINT_DIR/agent$a.done" ] || missing+=("$a")
      done
      [ ${#missing[@]} -eq 0 ] && break
      sleep "$POLL_INTERVAL"; elapsed=$((elapsed + POLL_INTERVAL))
    done
    if [ ${#missing[@]} -ne 0 ]; then
      warn "No checkpoint confirmation from agent(s): ${missing[*]}"
      if [ "$FORCE" = 1 ]; then
        warn "--force set: continuing; unflushed state for those agents may be lost."
      elif [ "$SAVE_ONLY" = 1 ]; then
        warn "Save-only: proceeding to snapshot anyway."
      else
        die "Aborting to avoid losing context. Re-run with --force to refresh anyway."
      fi
    else
      log "    all checkpoints confirmed."
      sleep "$SETTLE"
    fi
  fi
fi

# ── Phase 2: Snapshot (insurance, kept forever) ──────────────────────────────
step "Phase 2 — snapshot"
if [ "$PROJECT_HAS_FILES" = 1 ]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  SNAP_DIR="$SWARM_DIR/checkpoints/$TS"
  if [ "$DRY_RUN" = 1 ]; then
    log "    [dry-run] would snapshot projects/$PROJECT_ID/*.md -> swarms/$TARGET_SWARM/checkpoints/$TS/"
  else
    mkdir -p "$SNAP_DIR"
    cp "$PROJECT_DIR"/*.md "$SNAP_DIR"/ 2>/dev/null || true
    cp "$SWARM_DIR/ACTIVE_PROJECT" "$SNAP_DIR"/ 2>/dev/null || true
    log "    snapshot saved: swarms/$TARGET_SWARM/checkpoints/$TS/"
  fi
else
  log "    nothing to snapshot."
fi

if [ "$SAVE_ONLY" = 1 ]; then
  step "Done (save-only). Swarm left running, context untouched."
  exit 0
fi

# ── --hard only: build the relaunch commands (mirrors launch.sh) ─────────────
if [ "$MODE" = "hard" ]; then
  MODEL="$DEFAULT_MODEL"; EFFORT="$DEFAULT_EFFORT"; THINK_PROMPT="$DEFAULT_THINK_PROMPT"
  SKIP_PERMS="n"; [ "$SKIP_PERMS_FLAG" = 1 ] && SKIP_PERMS="y"
  if [ -f "$SWARM_DIR/launch.env" ]; then
    # shellcheck disable=SC1090
    source "$SWARM_DIR/launch.env"
  else
    warn "No launch.env; using launch.sh defaults (model=$MODEL effort=$EFFORT skip_perms=$SKIP_PERMS)."
  fi
  PERMS_FLAG=""; [ "$SKIP_PERMS" = "y" ] && PERMS_FLAG="--dangerously-skip-permissions"
  # Per-agent model/effort: MODEL_n/EFFORT_n from launch.env, else the plain
  # MODEL/EFFORT an old-format launch.env sets, else the defaults above.
  AGENT_MODELS=(); AGENT_EFFORTS=()
  for a in 1 2 3 4; do
    mvar="MODEL_$a"; evar="EFFORT_$a"
    AGENT_MODELS[$a]="${!mvar:-$MODEL}"
    AGENT_EFFORTS[$a]="${!evar:-$EFFORT}"
  done
fi

# Full shell line that relaunches a given agent in its pane (--hard).
launch_line_for() {
  local a="$1" role="" model effort effort_flag="" effort_label="" claude_cmd
  [ "$a" = 1 ] && role=" — ORCHESTRATOR"
  model="${AGENT_MODELS[$a]}"
  effort="${AGENT_EFFORTS[$a]}"
  if [ -n "$effort" ]; then
    effort_flag="--effort $effort"
    effort_label=" · effort: $effort"
  fi
  claude_cmd="claude --model '$model' $effort_flag $PERMS_FLAG --append-system-prompt '$THINK_PROMPT'"
  printf "cd '%s' && export SWARM_ID=%s && export AGENT_NUMBER=%s && echo '═══════════════════════════════════════' && echo '  AGENT %s%s  %s%s  (refreshed)' && echo '═══════════════════════════════════════' && %s" \
    "$SCRIPT_DIR" "$TARGET_SWARM" "$a" "$a" "$role" "$model" "$effort_label" "$claude_cmd"
}

# Refresh one peer pane in place (soft = /clear, hard = exit + relaunch).
refresh_peer() {
  local a="$1" uuid; uuid="$(uuid_for "$a")"
  [ -n "$uuid" ] || { warn "No session id for Agent $a; skipping."; return; }
  if [ "$MODE" = "hard" ]; then
    log "    Agent $a: kill + relaunch ..."
    interrupt_pane "$uuid"; sleep 0.7
    type_in_pane "$uuid" "/exit"; [ "$DRY_RUN" = 1 ] || sleep 2.5
    local line_file="$TMP_LINES/agent$a.line"
    launch_line_for "$a" > "$line_file"
    write_line_to_pane "$uuid" "$line_file"
  else
    log "    Agent $a: /clear ..."
    [ "$FORCE" = 1 ] && { interrupt_pane "$uuid"; sleep 0.5; }
    type_in_pane "$uuid" "/clear"
  fi
}

# ── Phase 3: Refresh panes ───────────────────────────────────────────────────
step "Phase 3 — refresh ($MODE)"
TMP_LINES="$(mktemp -d)"; trap 'rm -rf "$TMP_LINES"' EXIT

for a in 1 2 3 4; do
  [ "$a" = "$CALLER_AGENT" ] && continue
  refresh_peer "$a"
done

# Detached finisher for the caller's own pane (avoids self-clear race).
if [ -n "$CALLER_AGENT" ]; then
  uuid="$(uuid_for "$CALLER_AGENT")"
  finisher="$CHECKPOINT_DIR/finish-self-agent$CALLER_AGENT.sh"
  if [ "$MODE" = "hard" ]; then
    self_line_file="$CHECKPOINT_DIR/launch-self-agent$CALLER_AGENT.line"
    launch_line_for "$CALLER_AGENT" > "$self_line_file"
    REFRESH_SNIPPET=$(cat <<OSA
osascript - "$uuid" <<'A1'
on run argv
  set u to item 1 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if unique id of s is u then
            tell s
              write text (character id 3) newline no
              delay 0.7
              write text "/exit"
            end tell
            return
          end if
        end repeat
      end repeat
    end repeat
  end tell
end run
A1
sleep 2.5
osascript - "$uuid" "$self_line_file" <<'A2'
on run argv
  set u to item 1 of argv
  set f to item 2 of argv
  set fr to open for access (POSIX file f)
  set txt to read fr
  close access fr
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if unique id of s is u then
            tell s to write text txt
            return
          end if
        end repeat
      end repeat
    end repeat
  end tell
end run
A2
sleep $INIT_WAIT
OSA
)
  else
    REFRESH_SNIPPET=$(cat <<OSA
osascript - "$uuid" <<'A1'
on run argv
  set u to item 1 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if unique id of s is u then
            tell s to write text "/clear"
            return
          end if
        end repeat
      end repeat
    end repeat
  end tell
end run
A1
sleep 2
OSA
)
  fi
  cat > "$finisher" <<FIN
#!/usr/bin/env bash
# Auto-generated detached finisher: refreshes Agent $CALLER_AGENT's own pane.
sleep $SELF_DELAY
$REFRESH_SNIPPET
SWARM_ID="$TARGET_SWARM" "$SCRIPT_DIR/send-to-agent.sh" "$CALLER_AGENT" "Execute your startup protocol now."
FIN
  chmod +x "$finisher"
  if [ "$DRY_RUN" = 1 ]; then
    log "    [dry-run] would launch detached finisher for caller Agent $CALLER_AGENT (delay ${SELF_DELAY}s): $finisher"
  else
    log "    handing caller Agent $CALLER_AGENT to detached finisher (refreshes in ~${SELF_DELAY}s)..."
    nohup bash "$finisher" >"$CHECKPOINT_DIR/finish-self-agent$CALLER_AGENT.log" 2>&1 &
    disown
  fi
fi

# ── Phase 4: Startup kick for the synchronously-refreshed panes ──────────────
step "Phase 4 — startup kick"
KICK_WAIT=3; [ "$MODE" = "hard" ] && KICK_WAIT="$INIT_WAIT"
if [ "$DRY_RUN" = 1 ]; then
  log "    [dry-run] would wait ${KICK_WAIT}s then kick agents: ${CHECKPOINT_AGENTS[*]}"
else
  log "    waiting ${KICK_WAIT}s before kick..."
  sleep "$KICK_WAIT"
  for a in 1 2 3 4; do
    [ "$a" = "$CALLER_AGENT" ] && continue
    SWARM_ID="$TARGET_SWARM" "$SCRIPT_DIR/send-to-agent.sh" "$a" "Execute your startup protocol now." >/dev/null
    log "    kicked Agent $a"
  done
fi

[ "$DRY_RUN" = 0 ] && rm -f "$CHECKPOINT_DIR"/agent*.done

step "Done."
log "  Swarm $TARGET_SWARM refreshed ($MODE). Snapshots kept under swarms/$TARGET_SWARM/checkpoints/."
[ -n "$CALLER_AGENT" ] && log "  Your own pane (Agent $CALLER_AGENT) refreshes in ~${SELF_DELAY}s via the detached finisher."
