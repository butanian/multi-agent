#!/bin/bash
# Usage: ./send-to-agent.sh <agent_number> "<message>"

AGENT=$1
MESSAGE=$2
# Claude Code's TUI treats a long write as a PASTE and absorbs the trailing
# newline as text instead of Enter, so the message sits unsubmitted. Measured
# orphans at 813 chars inline. Spilling above 300 keeps every typed string
# short; the pointer that replaces it is ~110 chars and delivers reliably.
LARGE_MSG_THRESHOLD=300

if [ -z "$AGENT" ] || [ -z "$MESSAGE" ]; then
  echo "Usage: $0 <agent_number> \"<message>\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$SWARM_ID" ]; then
  echo "Error: SWARM_ID not set. Export SWARM_ID before calling this script."
  exit 1
fi

# SWARM_ID is interpolated into a path that gets sourced below and, for large
# payloads, into one that gets `find -delete`d. Neither may be steerable outside
# swarms/, so require a plain positive integer.
if ! [[ "$SWARM_ID" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: SWARM_ID must be a positive integer, got '$SWARM_ID'." >&2
  exit 1
fi

source "$SCRIPT_DIR/swarms/$SWARM_ID/pane-config.sh"

case $AGENT in
  1) SESSION_ID="$AGENT_1_SESSION" ;;
  2) SESSION_ID="$AGENT_2_SESSION" ;;
  3) SESSION_ID="$AGENT_3_SESSION" ;;
  4) SESSION_ID="$AGENT_4_SESSION" ;;
  *)
    echo "Unknown agent: $AGENT"
    exit 1
    ;;
esac

if [ -z "$SESSION_ID" ]; then
  echo "Error: No session ID for Agent $AGENT. Run ./launch.sh first."
  exit 1
fi

# For large messages, write to a persistent file and send a reference instead
if [ ${#MESSAGE} -gt $LARGE_MSG_THRESHOLD ]; then
  # Payloads live under the swarm that sent them, never in a namespace shared
  # with other swarms. macOS mktemp only substitutes TRAILING X's.
  SPILL_DIR="$SCRIPT_DIR/swarms/$SWARM_ID/outbox"
  mkdir -p "$SPILL_DIR"
  # Confined to this swarm's own outbox, so a peer swarm's payloads are
  # unreachable. 7 days, because an orphan has been seen sitting unread for 16h.
  find "$SPILL_DIR" -type f -mtime +7 -delete 2>/dev/null
  CONTENT_FILE=$(mktemp "$SPILL_DIR/to-agent${AGENT}-XXXXXX")
  printf '%s' "$MESSAGE" > "$CONTENT_FILE"
  SEND_MSG="[Message too large for inline send — read your full instructions from: $CONTENT_FILE]"
  echo "Content saved to $CONTENT_FILE (${#MESSAGE} chars)"
else
  SEND_MSG="$MESSAGE"
fi

# Write message to a temp file to avoid AppleScript string escaping issues
# (special chars like $, \, ", backticks in the message would break heredoc interpolation)
TMPFILE=$(mktemp)
printf '%s' "$SEND_MSG" > "$TMPFILE"

osascript << APPLESCRIPT
set msgFile to "$TMPFILE"
set fileRef to open for access (POSIX file msgFile)
set msgContent to read fileRef as «class utf8»
close access fileRef

tell application "iTerm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if unique id of s is "$SESSION_ID" then
          tell s
            write text msgContent without newline
          end tell
          delay 0.3
          tell s
            write text ""
          end tell
          return
        end if
      end repeat
    end repeat
  end repeat
end tell
error "no live iTerm2 session with unique id $SESSION_ID"
APPLESCRIPT
OSA_STATUS=$?

rm -f "$TMPFILE"

# Append-only delivery ledger. A pointer that turns up in the wrong pane is only
# traceable if every send is recorded somewhere /tmp cannot evaporate.
mkdir -p "$SCRIPT_DIR/logs"
printf '%s\tswarm=%s\tfrom=%s\tto=%s\tsession=%s\tbytes=%s\tfile=%s\toutcome=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SWARM_ID" "${AGENT_NUMBER:-external}" "$AGENT" \
  "$SESSION_ID" "${#MESSAGE}" "${CONTENT_FILE:-none}" \
  "$([ "$OSA_STATUS" -eq 0 ] && echo written || echo FAILED)" >> "$SCRIPT_DIR/logs/send.log"

if [ "$OSA_STATUS" -ne 0 ]; then
  echo "Error: message NOT delivered to Agent $AGENT (osascript exit $OSA_STATUS)." >&2
  exit 1
fi

echo "Message sent to Agent $AGENT (session $SESSION_ID)"
