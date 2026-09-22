---
agent: 2
role: assigned-at-runtime
---

# Agent 2

## Persona

Your persona and specialization are assigned by Agent 1 at the start of each project. On startup, read the `SKILL.md` file at the path Agent 1 specifies. That file defines your role, responsibilities, and domain context for this project.

Persona library: `/path/to/your/persona/library`

## Coordination

Read `COORDINATION.md` for the full protocol. Summary:
- Keep task status current in your work log using `[ ]` `[~]` `[x]` `[!]`
- Signal Agent 1 via `./send-to-agent.sh 1 "..."` when done or blocked — always update your log first
- Do not communicate directly with other agents — all sequencing goes through Agent 1

## Cross-Engine Review — Required for All Work

Every recorded decision must be reviewed by an agent running a **different engine family** than the one that produced it. Claude work is reviewed by Codex, Codex work is reviewed by Claude. The requirement is an independent second engine, not a particular vendor, so a Codex worker satisfies it by having a Claude pane review its work, never by invoking `/codex-collab` on itself.

From a Claude pane that means `/codex-collab`:
- Before finalising any design, schema, API contract, or implementation plan
- After producing a draft of any artifact, before you mark the task done
- After writing code, for correctness, edge cases, and risks
- When choosing between two or more viable approaches
- When you are unsure. Do not guess.

**How to use it:**
1. Frame the review clearly: share what you built or decided, the constraints, and your reasoning
2. Let the debate run. Update your work honestly if the reviewer surfaces real issues
3. Log the outcome, what changed and what was validated, in your work log before signalling Agent 1

**Minimum bar:** no task is marked `[x]` until a cross-engine review has completed on the core output of that task.

If you overturn a reviewer's finding, check your own instrument before you record the reviewer as wrong. A malformed probe that returns all-clear does not just miss the defect, it certifies it absent and discredits whoever found it.

## Startup Protocol
1. Read `swarms/$SWARM_ID/ACTIVE_PROJECT` to get the current project ID
2. Read `projects/{id}/index.md` — ticket summary, architecture, work breakdown
3. Read `projects/{id}/agent1.md` — find your assigned persona path and task
4. Read the assigned `SKILL.md` to load your persona for this project
5. Read `projects/{id}/agent2.md` — your own work log

## TDD Ground Rules

All code changes must follow this sequence — no exceptions:

1. **Write the tests first.** Write unit and integration tests that cover the intended behavior before touching implementation code.
2. **Confirm they fail.** Run the tests and verify they fail for the right reason.
3. **Implement the fix.** Write only the code needed to make the failing tests pass.
4. **Confirm they pass.** Run the tests again and confirm all pass.

Do not submit or log a fix as complete until both unit and integration tests exist and are passing.

## Switching Projects
1. Read `swarms/$SWARM_ID/ACTIVE_PROJECT` for the new project ID
2. Read `projects/{new-id}/index.md` and `projects/{new-id}/agent1.md`
3. Load the persona assigned to you for the new project
4. Read or create `projects/{new-id}/agent2.md`
