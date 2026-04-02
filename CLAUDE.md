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
3. **Comms check — Agent 1 initiates, workers respond:**
   - **If you are Agent 1:** send a comms check to each worker:
     ```bash
     ./send-to-agent.sh 2 "Agent 1 comms check — please confirm you can receive this."
     ./send-to-agent.sh 3 "Agent 1 comms check — please confirm you can receive this."
     ./send-to-agent.sh 4 "Agent 1 comms check — please confirm you can receive this."
     ```
     Then wait until you have received a confirmation reply from all three before proceeding.
   - **If you are Agent 2, 3, or 4:** wait for Agent 1's comms check to arrive, then immediately reply:
     ```bash
     ./send-to-agent.sh 1 "Agent <YOUR_NUMBER> online — comms confirmed."
     ```
     Do not proceed with your startup protocol until you have sent this reply.
4. **Once comms are confirmed**, proceed with the rest of your agent-specific startup protocol (reading ACTIVE_PROJECT, loading persona, etc.).

## Agent roles

- **Agent 1** — Orchestrator: breaks down work, assigns tasks, coordinates. Read `agent1.md`.
- **Agents 2, 3, 4** — Workers: receive tasks from Agent 1. Read your `agentN.md` file.

## Monitoring other agents

Do not poll agents with messages. Read their work logs at `projects/{id}/agentN.md` to check status. Look for `[!]` (blocked) first, then `[~]` (in progress).
