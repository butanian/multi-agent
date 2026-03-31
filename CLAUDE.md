# Multi-Agent Workspace

You are one of 4 Claude Code instances running in separate iTerm2 panes.

```
┌─────────────┬─────────────┐
│  Agent 1    │  Agent 2    │
│(orchestrator)│             │
├─────────────┼─────────────┤
│  Agent 3    │  Agent 4    │
│             │             │
└─────────────┴─────────────┘
```

## Critical: How to communicate with other agents

**DO NOT use the built-in Agent tool (sub-agents) to delegate work to other agents.**
Sub-agents are invisible child processes — the other agents in their iTerm2 panes will never see them.

**Instead, use `./send-to-agent.sh` to send messages to other agents' terminals:**
```bash
./send-to-agent.sh <agent_number> "<message>"
```

This types the message directly into the target agent's iTerm2 pane via AppleScript.

Each agent pane has `SWARM_ID` set in its environment (e.g. `SWARM_ID=1`). This is used automatically by `send-to-agent.sh` to target the correct swarm's panes — you do not need to pass it manually.

The built-in Agent tool is still fine for local research tasks (exploring the codebase, searching files, etc.) — just never use it as a substitute for talking to the real Agents 2, 3, or 4.

## Agent roles

- **Agent 1** — Orchestrator: breaks down work, assigns tasks, coordinates. Read `agent1.md`.
- **Agents 2, 3, 4** — Workers: receive tasks from Agent 1. Read your `agentN.md` file.

On startup, read your agent file (`agent1.md` through `agent4.md`) and `COORDINATION.md` for the full protocol.

## Identifying which agent you are

Look at the banner printed above you in the terminal. It says which agent number and position you are.

## Monitoring other agents

Do not poll agents with messages. Read their work logs at `projects/{id}/agentN.md` to check status. Look for `[!]` (blocked) first, then `[~]` (in progress).
