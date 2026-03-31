#!/bin/bash
# Usage: ./send-to-agent.sh <agent_number> "<message>"
#
# Short messages (<=500 chars) are typed directly into the agent's pane.
# Long messages are written to a file and the agent is told to read it.

AGENT=$1
MESSAGE=$2
MAX_DIRECT_LEN=500

if [ -z "$AGENT" ] || [ -z "$MESSAGE" ]; then
  echo "Usage: $0 <agent_number> \"<message>\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$SWARM_ID" ]; then
  echo "Error: SWARM_ID not set. Are you running inside a launched swarm?"
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

MSG_LEN=${#MESSAGE}

if [ "$MSG_LEN" -le "$MAX_DIRECT_LEN" ]; then
  # Short message — type directly
  ESCAPED_MESSAGE=$(echo "$MESSAGE" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

  osascript << APPLESCRIPT
tell application "iTerm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if unique id of s is "$SESSION_ID" then
          tell s
            write text "$ESCAPED_MESSAGE"
          end tell
          return
        end if
      end repeat
    end repeat
  end repeat
end tell
APPLESCRIPT

  echo "Message sent to Agent $AGENT (direct, ${MSG_LEN} chars)"
else
  # Long message — write to file, send short pointer
  INBOX_DIR="$SCRIPT_DIR/projects/inbox"
  mkdir -p "$INBOX_DIR"

  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  MSG_FILE="$INBOX_DIR/agent${AGENT}-${TIMESTAMP}.md"

  echo "$MESSAGE" > "$MSG_FILE"

  POINTER="Read your instructions from Agent 1 at: $MSG_FILE — read that file and follow the instructions inside."
  ESCAPED_POINTER=$(echo "$POINTER" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

  osascript << APPLESCRIPT
tell application "iTerm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if unique id of s is "$SESSION_ID" then
          tell s
            write text "$ESCAPED_POINTER"
          end tell
          return
        end if
      end repeat
    end repeat
  end repeat
end tell
APPLESCRIPT

  echo "Message sent to Agent $AGENT (via file, ${MSG_LEN} chars -> $MSG_FILE)"
fi
