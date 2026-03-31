# Multi-Swarm Support Design

**Date:** 2026-03-31
**Status:** Approved

## Problem

The multi-agent app supports one swarm (4 agents in one iTerm2 window) at a time. `pane-config.sh` and `ACTIVE_PROJECT` are single root-level files — a second `launch.sh` invocation overwrites them, breaking the first swarm. Users have been cloning the repo to work around this, scattering project files across directories.

## Goal

Support 2–3 independent swarms from a single repo, each with its own agent sessions and active project, without changing how agents talk to each other.

---

## Design

### 1. Runtime State Structure

A new `swarms/` directory holds per-swarm ephemeral state. Each swarm gets a numbered subdirectory created at launch time:

```
swarms/
  1/
    pane-config.sh    ← 4 iTerm2 session UUIDs
    ACTIVE_PROJECT    ← current project ID for this swarm
  2/
    pane-config.sh
    ACTIVE_PROJECT
```

- `swarms/` is added to `.gitignore` — it is runtime state, not source code
- The root-level `pane-config.sh` and `ACTIVE_PROJECT` files are deleted

### 2. `launch.sh` changes

New behavior added after the existing thinking/permissions/skip-agents prompts:

1. **Auto-assign swarm number** — scan `swarms/` for existing numbered dirs, take `max + 1` (defaults to `1` if none exist)
2. **Project setup prompt:**
   ```
   ── Project Setup ──────────────────────────────────────────────────────────
     Swarm 2
     New project or resume an existing one? [n/r]:
   ```
   - If `r`: list subdirectories of `projects/` (excluding `inbox`), let user pick by number
   - If `n`: write blank `ACTIVE_PROJECT` — Agent 1 sets it when it initialises
3. **Create `swarms/N/`** and write `ACTIVE_PROJECT` with the chosen project ID (or blank)
4. **Set `SWARM_ID`** — each pane's launch command gets `export SWARM_ID=N &&` prepended before the `claude` invocation
5. **Write `swarms/N/pane-config.sh`** with the 4 session UUIDs (same format as the current root file)

Everything else in `launch.sh` (thinking levels, permissions, skip agents) is unchanged.

### 3. `send-to-agent.sh` changes

Replace the single `source` line:

```bash
# Before
source "$SCRIPT_DIR/pane-config.sh"

# After
if [ -z "$SWARM_ID" ]; then
  echo "Error: SWARM_ID not set. Are you running inside a launched swarm?"
  exit 1
fi
source "$SCRIPT_DIR/swarms/$SWARM_ID/pane-config.sh"
```

All other logic (agent number lookup, direct vs file-based message routing, AppleScript) is unchanged.

### 4. Agent instruction updates

**`CLAUDE.md`:**
- Add a note that `SWARM_ID` is set in the environment for each pane
- Update the `ACTIVE_PROJECT` path reference to `swarms/$SWARM_ID/ACTIVE_PROJECT`

**`agent1.md`:**
- Startup protocol: "Read `ACTIVE_PROJECT`" → "Read `swarms/$SWARM_ID/ACTIVE_PROJECT`"
- Switching projects section: same path update for the write step

**`agent2.md`, `agent3.md`, `agent4.md`:** No changes — they don't reference these files directly.

---

## Files Changed

| File | Change |
|------|--------|
| `launch.sh` | Add swarm numbering, project setup prompt, `SWARM_ID` env var, write to `swarms/N/` |
| `send-to-agent.sh` | Source `swarms/$SWARM_ID/pane-config.sh` instead of root `pane-config.sh` |
| `CLAUDE.md` | Add `SWARM_ID` note, update `ACTIVE_PROJECT` path |
| `agent1.md` | Update `ACTIVE_PROJECT` path in startup and switching protocols |
| `.gitignore` | Add `swarms/` |
| `pane-config.sh` | Delete (replaced by `swarms/N/pane-config.sh`) |
| `ACTIVE_PROJECT` | Delete (replaced by `swarms/N/ACTIVE_PROJECT`) |

---

## Out of Scope

- Cross-swarm project handoff
- Swarm-to-swarm messaging
- Persistent swarm names (swarms are numbered per session lifetime only)
