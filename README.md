# multi-agent

A Claude Code workspace, launched by default as a single agent in one iTerm2 pane. It can also be launched as a 4-agent coordinated swarm (an orchestrator plus 3 workers, each in its own pane). Choose Custom, then the 4-agent launch mode, in `launch.sh`. Multiple independent **swarms** can run at the same time, each with its own isolated session state.

## Pane Layout

Default (single agent):

```
┌─────────────┐
│  Agent 1    │
└─────────────┘
```

Full swarm (opt-in):

```
┌─────────────┬─────────────┐
│  Agent 1    │  Agent 2    │
│(orchestrator)│             │
├─────────────┼─────────────┤
│  Agent 3    │  Agent 4    │
│             │             │
└─────────────┴─────────────┘
```

- **Agent 1**, the orchestrator: breaks down work, assigns personas, coordinates
- **Agents 2, 3, 4**, the workers: receive tasks and personas from Agent 1

## Prerequisites

- macOS with iTerm2 installed
- Claude Code CLI (`claude`) installed and authenticated
- Node.js/npm (for the Codex CLI, used by the `/codex-collab` skill)
- Optional, to route panes through the Bifrost gateway: the Bifrost CLI, `jq`, Codex CLI 0.165 or newer, and the setup in [BIFROST.md](BIFROST.md)

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
- `agent1.md` to `agent4.md`, the agent instruction files
- `COORDINATION.md`, the shared coordination protocol
- `registry.md`, the project registry
- `projects/`, per-project work logs
- `send-to-agent.sh`, message passing between agents
- `.mcp.json`, Codex MCP server config
- `.claude/settings.local.json`, pre-approved permissions

### 2. Authenticate Codex (one-time per team member)

```bash
codex login
```

## How to use

The core loop: launch a swarm, give Agent 1 the work, let the agents coordinate, and monitor their work logs. Refresh the swarm when context gets long.

### 1. Launch a swarm

```bash
./launch.sh
```

`launch.sh` first asks **Default or Custom**:

- **Default** (`1`, or Enter): one agent, Bifrost Claude, `claude-sonnet-5-5`, `medium` effort. It skips straight to the project prompt.
- **Custom** (`2`): walks through the prompts below.

Custom prompts:

1. **Launch mode.** `1` for a single agent (the default), or `4` for the full orchestrator/worker swarm.
2. **Provider.** Choose Claude, Bifrost Claude, Codex, or Bifrost Codex for each agent. Claude is the default. The Bifrost options route that pane through the gateway.
3. **Models.** Choose a model per agent from the active CLI's current catalog. Claude models come from its entitled model list; Codex models come from `codex debug models`. Press Enter for the default or type a model ID.
4. **Effort.** Single-agent mode asks for one effort level. Swarm mode offers orchestrator high / workers lower, all high, or all lower. Values are `xhigh`, `high`, `medium`, `low`; defaults are `xhigh` and `high`.

Both paths end with the **Project** prompt. Type `n` to start fresh (you will be asked for a project name; include the Jira ticket if there is one, e.g. `GBO-123: add-checkout-flow`), or `r` to pick an existing project from a numbered list.

The script then opens iTerm2 with the pane(s) for the mode you picked, starts the selected CLI with `SWARM_ID` and `AGENT_NUMBER` exported, writes session IDs to `swarms/<N>/pane-config.sh`, and records the launch mode plus per-agent engine, gateway, model, and effort choices in `swarms/<N>/launch.env`. Claude panes receive a startup kick; Codex panes begin from their startup prompt. In swarm mode, Agent 1 runs a comms check, pinging each worker and waiting for confirmations before proceeding; in single-agent mode, it skips the check.

### 2. Give Agent 1 the work

1. Give Agent 1 a ticket URL or project description (type it into its pane, or use `send-to-agent.sh`)
2. Agent 1 breaks down the work and assigns tasks + personas to Agents 2 to 4
3. Agents signal completion or blockers back to Agent 1
4. Agent 1 coordinates until the project is complete

### 3. Message agents

```bash
./send-to-agent.sh <agent_number> "<message>"
```

`SWARM_ID` must be set in your environment (it is set automatically in each agent pane by the launch scripts). Short messages (up to 1000 chars) are typed directly into the target pane. Longer messages are written to a temp file and the agent is sent a pointer to read it.

Example:
```bash
./send-to-agent.sh 2 "Your task: implement the login API. Persona: core/backend-agent/SKILL.md. Work breakdown in projects/auth-v2/index.md."
```

### 4. Monitor progress

Do not poll agents with messages. Read their work logs at `projects/{id}/agentN.md`. Look for `[!]` (blocked) first, then `[~]` (in progress).

| Marker | Meaning |
|--------|---------|
| `[ ]` | Todo, not started |
| `[~]` | In progress |
| `[x]` | Done |
| `[!]` | Blocked, needs Agent 1 |

### 5. Refresh a swarm when context gets long

```bash
./restart-swarm.sh [swarm_id] [flags]
```

Agents get slow and expensive as their conversations grow. `restart-swarm.sh` checkpoints every agent's working state to its work log (plus a timestamped snapshot under `swarms/<N>/checkpoints/`), then clears each pane and re-primes the agents from their on-disk files. No work is lost.

- Default (soft): sends `/clear` to each pane. Same claude process, empty context.
- `--hard`: kills and relaunches claude in each pane, replaying the per-agent model/effort from `swarms/<N>/launch.env`. Use it for a crash, a wedged agent, or a model change.
- `--save-only`: checkpoint and snapshot without clearing anything.
- `--dry-run`: print every action without touching the panes.
- `--force`: proceed even if some agents never confirm their checkpoint.

It works both from a plain shell and from inside one of the agent panes (the calling agent's own pane is refreshed last by a detached finisher).

### 6. Open several projects at once

```bash
./workspace.sh
```

Scans `projects/` and lets you pick one or more existing projects (or `all`). Each selected project gets its own tab in the frontmost iTerm2 window, with 4 agent panes, a named tab title, and its own swarm ID.

## Bifrost gateway

Any pane can run through PlayOn's Bifrost gateway. The Default launch uses it. Setup and refusal rules: [BIFROST.md](BIFROST.md).

## Swarms

Each `./launch.sh` run creates a new **swarm** with its own directory: 1 agent by default, or 4 if you pick the full swarm. `./workspace.sh` always opens full 4-agent swarms. Swarm numbers are auto-assigned, and several swarms can run at once on different projects. `SWARM_ID` is exported in every pane, and `send-to-agent.sh` reads it.

`swarms/<N>/AGENT_COUNT` holds `1` or `4`. A solo swarm has no orchestrator/worker split and skips the comms check.

## File Structure

```
swarms/<N>/
  pane-config.sh          iTerm2 session IDs for this swarm
  ACTIVE_PROJECT          Current project ID for this swarm
  AGENT_COUNT             1 or 4
  launch.env              Launch parameters, replayed by restart-swarm.sh --hard
  checkpoints/            Snapshots taken by restart-swarm.sh

projects/
  inbox/                  Legacy message drop-box (ignored by the project pickers)
  {id}/
    index.md              Project overview, work breakdown, decisions
    agent1.md             Agent 1's work log
    agent2.md             Agent 2's work log
    agent3.md             Agent 3's work log
    agent4.md             Agent 4's work log

personas/                 Persona library Agent 1 assigns to workers
agent1.md - agent4.md     Agent instruction files (workspace-level)
COORDINATION.md           Shared coordination protocol
registry.md               All projects and their status
send-to-agent.sh          Message passing script
launch.sh                 Opens iTerm2 and starts a new swarm
workspace.sh              Opens one tab per existing project, each a swarm
restart-swarm.sh          Checkpoint + context refresh (soft /clear or hard relaunch)
setup.sh                  One-time workspace setup
tests/run.sh              Harness test suite: bash tests/run.sh
BIFROST.md           Bifrost gateway setup
```
