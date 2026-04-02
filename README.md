# multi-agent

A multi-agent Claude Code workspace where 4 coordinated agents run simultaneously in iTerm2 panes. Multiple independent **swarms** can run at the same time, each with its own isolated session state.

## Pane Layout

```
┌─────────────┬─────────────┐
│  Agent 1    │  Agent 2    │
│(orchestrator)│             │
├─────────────┼─────────────┤
│  Agent 3    │  Agent 4    │
│             │             │
└─────────────┴─────────────┘
```

- **Agent 1** — Orchestrator: breaks down work, assigns personas, coordinates
- **Agents 2, 3, 4** — Workers: receive tasks and personas from Agent 1

## Prerequisites

- macOS with iTerm2 installed
- Claude Code CLI (`claude`) installed and authenticated
- Node.js/npm (for Codex CLI — used by the `/codex-collab` skill)

## Setup

### 1. Run the setup script (one-time)

```bash
./setup.sh [workspace-dir] [persona-library-path]
```

Examples:
```bash
./setup.sh                                    # sets up in current directory
./setup.sh ~/my-team/agents ~/personas        # custom paths
```

This creates:
- `agent1.md` – `agent4.md` — Agent instruction files
- `COORDINATION.md` — Shared coordination protocol
- `registry.md` — Project registry
- `projects/` — Per-project work logs
- `send-to-agent.sh` — Message passing between agents
- `.mcp.json` — Codex MCP server config
- `.claude/settings.local.json` — Pre-approved permissions

### 2. Authenticate Codex (one-time per team member)

```bash
codex login
```

### 3. Launch a swarm

```bash
./launch.sh
```

`launch.sh` will prompt you for:

1. **Skip permissions?** — type `y` to pass `--dangerously-skip-permissions` to all agents
2. **New or resume?** — type `n` to start fresh, or `r` to pick an existing project from a numbered list
   - If `n`: prompted for a project name. Include the Jira ticket if there is one — e.g. `GBO-123: add-checkout-flow`. The name is normalized into a safe project ID automatically.

It then opens iTerm2 with 4 panes, starts Claude in each pane with `SWARM_ID` and `AGENT_NUMBER` set, and writes session IDs to `swarms/<N>/pane-config.sh`. After 10 seconds it sends a startup kick to all agents. Agent 1 then runs a comms check — sending a ping to each worker and waiting for all three to confirm before proceeding.

## Swarms

Each `./launch.sh` run creates a new **swarm** — an independent group of 4 agents with its own directory:

```
swarms/
  1/
    pane-config.sh    # iTerm2 session UUIDs for this swarm's 4 panes
    ACTIVE_PROJECT    # Current project ID (or empty = new)
  2/
    pane-config.sh
    ACTIVE_PROJECT
  ...
```

Swarm numbers are auto-assigned (next available integer). Multiple swarms can be active simultaneously, each working on a different project.

`SWARM_ID` is exported as an environment variable in every agent pane. `send-to-agent.sh` reads it automatically — you don't pass it manually.

## Usage

### Sending messages between agents

```bash
./send-to-agent.sh <agent_number> "<message>"
```

`SWARM_ID` must be set in your environment (it is automatically set in each agent pane by `launch.sh`). Short messages (≤500 chars) are typed directly into the target pane. Longer messages are written to `projects/inbox/` and the agent is told to read the file.

Example:
```bash
./send-to-agent.sh 2 "Your task: implement the login API. Persona: core/backend-agent/SKILL.md. Work breakdown in projects/auth-v2/index.md."
```

### Starting a project

1. Give Agent 1 a ticket URL or project description
2. Agent 1 breaks down work and assigns tasks + personas to Agents 2–4
3. Agents signal completion or blockers back to Agent 1
4. Agent 1 coordinates until the project is complete

### Task status markers

| Marker | Meaning |
|--------|---------|
| `[ ]` | Todo — not started |
| `[~]` | In progress |
| `[x]` | Done |
| `[!]` | Blocked — needs Agent 1 |

## File Structure

```
swarms/<N>/
  pane-config.sh          iTerm2 session IDs for this swarm
  ACTIVE_PROJECT          Current project ID for this swarm

projects/
  inbox/                  Long messages routed via file (auto-created)
  {id}/
    index.md              Project overview, work breakdown, decisions
    agent1.md             Agent 1's work log
    agent2.md             Agent 2's work log
    agent3.md             Agent 3's work log
    agent4.md             Agent 4's work log

agent1.md – agent4.md     Agent instruction files (workspace-level)
COORDINATION.md           Shared coordination protocol
registry.md               All projects and their status
send-to-agent.sh          Message passing script
launch.sh                 Opens iTerm2 and starts a new swarm
setup.sh                  One-time workspace setup
```
