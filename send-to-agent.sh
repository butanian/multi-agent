#!/bin/bash
# Usage: ./send-to-agent.sh <agent_number> "<message>"

AGENT=$1
MESSAGE=$2

if [ -z "$AGENT" ] || [ -z "$MESSAGE" ]; then
  echo "Usage: $0 <agent_number> \"<message>\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/pane-config.sh"

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

echo "Message sent to Agent $AGENT (session $SESSION_ID)"
