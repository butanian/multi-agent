#!/bin/bash
# Usage: ./send-to-agent.sh <agent_number> "<message>"
# Example: ./send-to-agent.sh 2 "Please run your tests and update agent2.md"

AGENT=$1
MESSAGE=$2

if [ -z "$AGENT" ] || [ -z "$MESSAGE" ]; then
  echo "Usage: $0 <agent_number> \"<message>\""
  exit 1
fi

# Load session UUIDs
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/pane-config.sh"

# Pick the right session ID
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

# Escape message for AppleScript
ESCAPED_MESSAGE=$(echo "$MESSAGE" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

osascript <<EOF
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
EOF

echo "Message sent to Agent $AGENT (session $SESSION_ID)"
