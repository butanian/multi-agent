#!/bin/bash
# Usage: ./send-to-agent.sh <agent_number> "<message>"

AGENT=$1
MESSAGE=$2
LARGE_MSG_THRESHOLD=1000

if [ -z "$AGENT" ] || [ -z "$MESSAGE" ]; then
  echo "Usage: $0 <agent_number> \"<message>\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$SWARM_ID" ]; then
  echo "Error: SWARM_ID not set. Export SWARM_ID before calling this script."
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
  CONTENT_FILE=$(mktemp /tmp/agent_content_XXXXXX.md)
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
set msgContent to read fileRef
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
APPLESCRIPT

rm -f "$TMPFILE"
echo "Message sent to Agent $AGENT (session $SESSION_ID)"
