# multi-agent

A multi-agent Claude Code workspace with 4 coordinated agents running in iTerm2.

## Pane Layout

```
┌─────────────┬─────────────┐
│  Agent 1    │  Agent 2    │
│  (top-left) │ (top-right) │
├─────────────┼─────────────┤
│  Agent 3    │  Agent 4    │
│(bottom-left)│(bottom-right)│
└─────────────┴─────────────┘
```

- **Agent 1** — Orchestrator: breaks down work, assigns tasks, coordinates
- **Agents 2, 3, 4** — Workers: receive personas and tasks from Agent 1

## Prerequisites

- macOS with iTerm2 installed
- Claude Code CLI (`claude`) installed and authenticated
- Node.js/npm (for Codex CLI)

## Setup

### 1. Run the setup script

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
- `ACTIVE_PROJECT` — Tracks the current project
- `registry.md` — Project registry
- `projects/` — Per-project work logs
- `send-to-agent.sh` — Message passing between agents
- `pane-config.sh` — iTerm2 session ID map
- `.mcp.json` — Codex MCP server config
- `.claude/settings.local.json` — Pre-approved permissions

### 2. Authenticate Codex (one-time)

```bash
codex login
```

This opens a browser flow for authentication. Each team member must do this once.

### 3. Launch the workspace

```bash
./launch.sh
```

This opens iTerm2 with 4 panes, starts Claude in each, and configures message routing. Each agent will display a banner announcing its number and position.

## Usage

### Sending messages between agents

```bash
./send-to-agent.sh <agent_number> "<message>"
```

Example:
```bash
./send-to-agent.sh 2 "Your task: implement the login API. Persona: core/backend-agent/SKILL.md"
```

### Starting a project

1. Give Agent 1 a Jira ticket URL or project description
2. Agent 1 breaks down work and assigns tasks to Agents 2-4
3. Agents signal completion/blockers back to Agent 1
4. Agent 1 coordinates until the project is complete

### Task status markers

| Marker | Meaning |
|--------|---------|
| `[ ]` | Todo — not started |
| `[~]` | In progress |
| `[x]` | Done |
| `[!]` | Blocked — needs Agent 1 |

## Files

| File | Purpose |
|------|---------|
| `ACTIVE_PROJECT` | Current project ID (or `NONE`) |
| `registry.md` | List of all projects and their status |
| `projects/{id}/index.md` | Project overview, work breakdown, decisions |
| `projects/{id}/agent1.md` | Agent 1's work log for this project |
| `projects/{id}/agent2.md` | Agent 2's work log for this project |
| `projects/{id}/agent3.md` | Agent 3's work log for this project |
| `projects/{id}/agent4.md` | Agent 4's work log for this project |
