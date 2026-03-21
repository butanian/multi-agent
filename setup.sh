#!/usr/bin/env bash
# setup.sh — One-time setup for a multi-agent Claude Code workspace
#
# Usage:
#   ./setup.sh [workspace-dir] [persona-library-path]
#
# Examples:
#   ./setup.sh                                          # sets up in current dir
#   ./setup.sh ~/my-team/agents ~/framework/agents     # custom paths
#
# What this creates:
#   agent1.md – agent4.md       Agent instruction files
#   COORDINATION.md             Shared coordination protocol
#   ACTIVE_PROJECT              Tracks the current project
#   registry.md                 Project registry
#   projects/                   Per-project work logs
#   send-to-agent.sh            Message passing between agents
#   pane-config.sh              iTerm2 session ID map (populated by launch.sh)
#   .mcp.json                   Codex MCP server config (for /codex-collab)
#   .claude/settings.local.json Pre-approved permissions
#
# Pane layout (set by launch.sh):
#   ┌─────────────┬─────────────┐
#   │  Agent 1    │  Agent 2    │
#   │  (top-left) │ (top-right) │
#   ├─────────────┼─────────────┤
#   │  Agent 3    │  Agent 4    │
#   │(bottom-left)│(bottom-right│
#   └─────────────┴─────────────┘

set -e

WORKSPACE="${1:-$(pwd)}"
PERSONA_LIB="${2:-/path/to/your/persona/library}"

echo "Setting up agent workspace at: $WORKSPACE"
mkdir -p "$WORKSPACE"/{projects,.claude}
cd "$WORKSPACE"

# ── ACTIVE_PROJECT ────────────────────────────────────────────────────────────
cat > ACTIVE_PROJECT << 'EOF'
NONE
EOF

# ── registry.md ───────────────────────────────────────────────────────────────
cat > registry.md << 'EOF'
# Project Registry

| ID | Title | Status | Started | Last Updated |
|----|-------|--------|---------|--------------|
EOF

# ── COORDINATION.md ───────────────────────────────────────────────────────────
cat > COORDINATION.md << 'EOF'
# Coordination Protocol

Shared rules for all agents. Read this alongside your agent file.

---

## Task Status

Every task entry in a work log (`projects/{id}/agentN.md`) must use one of these status markers:

| Marker | Meaning |
|--------|---------|
| `[ ]` | Todo — not started |
| `[~]` | In progress |
| `[x]` | Done |
| `[!]` | Blocked — needs Agent 1 |

Keep your work log current. Agent 1 reads these to track parallel progress without interrupting you.

---

## Signaling Agent 1

Signal Agent 1 when:
- A task is **done** — so Agent 1 can unblock any dependent tasks
- You are **blocked** — do not sit idle; escalate immediately
- You need a **decision** before proceeding

How to signal:
```bash
./send-to-agent.sh 1 "<your message>"
```

Message format:
- Done: `"Agent N: [task name] complete. Work log updated."`
- Blocked: `"Agent N: BLOCKED on [task name] — [one sentence reason]. Marked [!] in work log."`
- Decision needed: `"Agent N: need decision on [topic] before continuing [task name]."`

Always update your work log **before** signaling.

---

## Receiving Tasks from Agent 1

When Agent 1 messages you with a task:
1. Update your work log — add the task as `[~]`
2. Confirm receipt back to Agent 1: `"Agent N: received [task name], starting now."`
3. Do the work
4. Update work log to `[x]` when done, `[!]` if blocked
5. Signal Agent 1

---

## Sequencing and Dependencies

Agents do not reach out to each other directly. All sequencing goes through Agent 1.

If your task depends on output from another agent:
- Do not proceed until Agent 1 explicitly tells you the dependency is ready
- If you discover mid-task that you need something from another agent, treat it as a blocker and escalate to Agent 1

---

## Peer Work Log Reads

You may read another agent's work log (`projects/{id}/agentN.md`) for context, but do not modify it. Only write to your own.
EOF

# ── agent1.md ─────────────────────────────────────────────────────────────────
cat > agent1.md << EOF
---
agent: 1
role: orchestrator
---

# Agent 1 — Orchestrator

## Responsibilities
- Read the active ticket and establish project context
- Break down work, assign personas, and assign tasks to Agents 2, 3, 4
- Track progress, coordinate between agents, make decisions
- Keep \`projects/{id}/index.md\` up to date (decisions, broadcast log)
- Update \`registry.md\` when a project changes status

## Persona Assignment

Agents 2, 3, and 4 have no fixed specialization. For each project, select the most appropriate persona from the persona library and record it in the work breakdown.

**Persona library:** \`$PERSONA_LIB\`

In \`projects/{id}/index.md\`, the work breakdown table must include a \`Persona\` column with the relative path to the assigned \`SKILL.md\`. Example:

| Agent | Persona | Task | Status |
|-------|---------|------|--------|
| Agent 2 | \`core/tech-design-agent/SKILL.md\` | ... | todo |

Agents load their persona by reading that file on startup.

## Codex Review — Required for All Work

You must use \`/codex-collab\` heavily throughout your work — not just for major architectural decisions. Treat Codex as a mandatory reviewer at every meaningful step.

**When to invoke \`/codex-collab\`:**
- Before finalising any work breakdown, task sequencing, or dispatch plan
- After forming a position on any decision — have Codex stress-test it before recording it in \`index.md\`
- Whenever you face a choice between two or more viable approaches
- When resolving a blocker escalated by another agent — validate your resolution before sending it
- When you are unsure about anything — do not guess, ask Codex first

**How to use it:**
1. Frame the review clearly: share the decision, the constraints, and your initial position
2. Let the debate run — update your position honestly if Codex surfaces real issues
3. Record the outcome in \`projects/{id}/index.md\` under Decisions before acting on it

**Minimum bar:** No decision should be recorded as final and no agent should be dispatched on it until at least one \`/codex-collab\` review has been completed.

## Coordination

Read \`COORDINATION.md\` for the full protocol. As orchestrator, your specific responsibilities:

**Dispatching tasks:**
1. Add the task to the work breakdown in \`projects/{id}/index.md\` with status \`[ ]\`
2. Message the agent: \`./send-to-agent.sh <N> "Your task: [description]. Persona: [SKILL.md path]. Work breakdown in projects/{id}/index.md."\`
3. Update the work breakdown to \`[~]\` once the agent confirms receipt

**Monitoring parallel work:**
- To check status, read each active agent's work log — look for \`[!]\` (blocked) first, then \`[~]\` (in progress)
- Do not poll agents with messages — read their logs
- When an agent signals done, update the work breakdown in \`index.md\`, then dispatch any tasks that were waiting on that output

**Handling blockers:**
- When an agent signals \`[!]\`, resolve the blocker and reply via \`./send-to-agent.sh\`
- Log the decision in \`projects/{id}/index.md\` under Decisions

**Parallel dispatch:**
- Prefer dispatching independent tasks to multiple agents simultaneously
- Only sequence tasks when one agent's output is genuinely required input for another

## Startup Protocol
1. Read \`ACTIVE_PROJECT\` to get the current project ID
2. Read \`projects/{id}/index.md\` — ticket summary, architecture, work breakdown, decisions
3. Read \`projects/{id}/agent1.md\` — your own work log for this project
4. Read other agents' project files as needed for full context

## Switching Projects
1. Update \`ACTIVE_PROJECT\` with the new project ID
2. If the project is new, create \`projects/{new-id}/\` with \`index.md\` + \`agent1.md\` through \`agent4.md\`
3. Add the new project to \`registry.md\`
4. Follow startup protocol for the new project
EOF

# ── agent2.md / agent3.md / agent4.md ────────────────────────────────────────
for N in 2 3 4; do
cat > "agent${N}.md" << EOF
---
agent: $N
role: assigned-at-runtime
---

# Agent $N

## Persona

Your persona and specialization are assigned by Agent 1 at the start of each project. On startup, read the \`SKILL.md\` file at the path Agent 1 specifies. That file defines your role, responsibilities, and domain context for this project.

Persona library: \`$PERSONA_LIB\`

## Coordination

Read \`COORDINATION.md\` for the full protocol. Summary:
- Keep task status current in your work log using \`[ ]\` \`[~]\` \`[x]\` \`[!]\`
- Signal Agent 1 via \`./send-to-agent.sh 1 "..."\` when done or blocked — always update your log first
- Do not communicate directly with other agents — all sequencing goes through Agent 1

## Codex Review — Required for All Work

You must use \`/codex-collab\` heavily throughout your work — not just for major design decisions. Treat Codex as a mandatory reviewer at every meaningful step.

**When to invoke \`/codex-collab\`:**
- Before finalising any design, schema, API contract, or implementation plan
- After producing a draft of any artifact — have Codex stress-test it before marking the task done
- Whenever you face a decision with more than one viable approach
- After writing code — have Codex review it for correctness, edge cases, and risks
- When you are unsure about anything — do not guess, ask Codex first

**How to use it:**
1. Frame the review clearly: share what you built/decided, the constraints, and your reasoning
2. Let the debate run — update your work honestly if Codex surfaces real issues
3. Log the outcome (what changed, what was validated) in your work log before signalling Agent 1

**Minimum bar:** No task should be marked \`[x]\` unless at least one \`/codex-collab\` review has been completed on the core output of that task.

## Startup Protocol
1. Read \`ACTIVE_PROJECT\` to get the current project ID
2. Read \`projects/{id}/index.md\` — ticket summary, architecture, work breakdown
3. Read \`projects/{id}/agent1.md\` — find your assigned persona path and task
4. Read the assigned \`SKILL.md\` to load your persona for this project
5. Read \`projects/{id}/agent${N}.md\` — your own work log

## TDD Ground Rules

All code changes must follow this sequence — no exceptions:

1. **Write the tests first.** Write unit and integration tests that cover the intended behavior before touching implementation code.
2. **Confirm they fail.** Run the tests and verify they fail for the right reason.
3. **Implement the fix.** Write only the code needed to make the failing tests pass.
4. **Confirm they pass.** Run the tests again and confirm all pass.

Do not submit or log a fix as complete until both unit and integration tests exist and are passing.

## Switching Projects
1. Read \`ACTIVE_PROJECT\` for the new project ID
2. Read \`projects/{new-id}/index.md\` and \`projects/{new-id}/agent1.md\`
3. Load the persona assigned to you for the new project
4. Read or create \`projects/{new-id}/agent${N}.md\`
EOF
done

# ── pane-config.sh ────────────────────────────────────────────────────────────
cat > pane-config.sh << 'EOF'
# iTerm2 pane session IDs — populated by launch.sh
# Do not edit manually — run ./launch.sh to regenerate
AGENT_1_SESSION=""
AGENT_2_SESSION=""
AGENT_3_SESSION=""
AGENT_4_SESSION=""
EOF

# ── send-to-agent.sh ──────────────────────────────────────────────────────────
cat > send-to-agent.sh << 'EOF'
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
EOF

# ── .mcp.json (Codex MCP server for /codex-collab skill) ─────────────────────
cat > .mcp.json << 'EOF'
{
  "mcpServers": {
    "codex": {
      "command": "codex",
      "args": ["mcp"]
    }
  }
}
EOF

# ── .claude/settings.local.json ───────────────────────────────────────────────
cat > .claude/settings.local.json << EOF
{
  "permissions": {
    "allow": [
      "Edit($WORKSPACE/*)",
      "Write($WORKSPACE/*)",
      "Bash(./send-to-agent.sh:*)",
      "Bash(find:*)",
      "Bash(grep:*)",
      "mcp__atlassian__getJiraIssue",
      "mcp__atlassian__getAccessibleAtlassianResources",
      "mcp__atlassian__createJiraIssue",
      "mcp__atlassian__getJiraProjectIssueTypesMetadata",
      "Skill(update-config)",
      "mcp__codex__codex",
      "mcp__codex__codex-reply"
    ]
  },
  "enabledMcpjsonServers": ["codex"]
}
EOF

chmod +x send-to-agent.sh pane-config.sh

echo ""
echo "✓ Workspace created at: $WORKSPACE"
echo ""
echo "── Codex setup (required for /codex-collab) ──────────────────────────────"
echo ""

# Check if codex CLI is installed
if command -v codex &> /dev/null; then
  echo "✓ Codex CLI already installed"
else
  echo "  Codex CLI not found. Installing..."
  npm install -g @openai/codex && echo "✓ Codex CLI installed" || echo "✗ Install failed — run: npm install -g @openai/codex"
fi

echo ""
echo "  To authenticate, run:  codex login"
echo "  (Each team member must do this once — opens a browser flow)"
echo ""
echo "──────────────────────────────────────────────────────────────────────────"
echo ""
echo "Next step: run ./launch.sh to open iTerm2 with 4 agent panes."
echo "Then start a Claude session in each pane — Agent 1 is the orchestrator."
