# Multi-Agent Workspace

There are exactly **4 Claude Code instances** running right now in separate iTerm2 panes. You are one of them. The other 3 are real, live agents — not sub-processes, not abstractions. They are running in their own terminal panes and can receive messages from you.

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

**NEVER use the built-in Agent tool (sub-agents) to delegate work to or communicate with other agents.** Sub-agents are invisible child processes that spawn inside your own session — the other agents in their iTerm2 panes will never see them. Using sub-agents to "talk to Agent 2" does nothing. The real Agent 2 is in another pane and will never receive that message.

**The ONLY way to communicate with another agent is `./send-to-agent.sh`:**
```bash
./send-to-agent.sh <agent_number> "<message>"
```

This types the message directly into the target agent's iTerm2 pane via AppleScript. It is the only mechanism that reaches the real agents.

Each agent pane has `SWARM_ID` set in its environment (e.g. `SWARM_ID=1`). This is used automatically by `send-to-agent.sh` to target the correct swarm's panes — you do not need to pass it manually.

The built-in Agent tool is fine for **local research only** (exploring the codebase, searching files, etc.) — never use it as a substitute for talking to the real Agents 1, 2, 3, or 4.

## Startup Protocol — All Agents

On startup, every agent must:

1. **Identify yourself.** Read the banner printed above you in the terminal — it says your agent number.
2. **Read your agent file** (`agent1.md` through `agent4.md`) and `COORDINATION.md`.
3. **Send a startup confirmation to every other agent.** Use `./send-to-agent.sh` to message each of the other 3 agents:
   ```bash
   ./send-to-agent.sh <N> "Agent <YOUR_NUMBER> online and ready."
   ```
   For example, if you are Agent 2, send:
   ```bash
   ./send-to-agent.sh 1 "Agent 2 online and ready."
   ./send-to-agent.sh 3 "Agent 2 online and ready."
   ./send-to-agent.sh 4 "Agent 2 online and ready."
   ```
4. **Wait for the other agents' confirmations to arrive.** You should receive 3 "online and ready" messages. Once you see them, you know the swarm is fully connected.
5. **Then proceed** with the rest of your agent-specific startup protocol (reading ACTIVE_PROJECT, loading persona, etc.).

## Agent roles

- **Agent 1** — Orchestrator: breaks down work, assigns tasks, coordinates. Read `agent1.md`.
- **Agents 2, 3, 4** — Workers: receive tasks from Agent 1. Read your `agentN.md` file.

## Monitoring other agents

Do not poll agents with messages. Read their work logs at `projects/{id}/agentN.md` to check status. Look for `[!]` (blocked) first, then `[~]` (in progress).
