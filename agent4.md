---
agent: 4
role: assigned-at-runtime
---

# Agent 4

## Persona

Your persona and specialization are assigned by Agent 1 at the start of each project. On startup, read the `SKILL.md` file at the path Agent 1 specifies. That file defines your role, responsibilities, and domain context for this project.

Persona library: `/path/to/your/persona/library`

## Coordination

Read `COORDINATION.md` for the full protocol. Summary:
- Keep task status current in your work log using `[ ]` `[~]` `[x]` `[!]`
- Signal Agent 1 via `./send-to-agent.sh 1 "..."` when done or blocked — always update your log first
- Do not communicate directly with other agents — all sequencing goes through Agent 1

## Codex Review — Required for All Work

You must use `/codex-collab` heavily throughout your work — not just for major design decisions. Treat Codex as a mandatory reviewer at every meaningful step.

**When to invoke `/codex-collab`:**
- Before finalising any design, schema, API contract, or implementation plan
- After producing a draft of any artifact — have Codex stress-test it before marking the task done
- Whenever you face a decision with more than one viable approach
- After writing code — have Codex review it for correctness, edge cases, and risks
- When you are unsure about anything — do not guess, ask Codex first

**How to use it:**
1. Frame the review clearly: share what you built/decided, the constraints, and your reasoning
2. Let the debate run — update your work honestly if Codex surfaces real issues
3. Log the outcome (what changed, what was validated) in your work log before signalling Agent 1

**Minimum bar:** No task should be marked `[x]` unless at least one `/codex-collab` review has been completed on the core output of that task.

## Startup Protocol
1. Read `ACTIVE_PROJECT` to get the current project ID
2. Read `projects/{id}/index.md` — ticket summary, architecture, work breakdown
3. Read `projects/{id}/agent1.md` — find your assigned persona path and task
4. Read the assigned `SKILL.md` to load your persona for this project
5. Read `projects/{id}/agent4.md` — your own work log

## TDD Ground Rules

All code changes must follow this sequence — no exceptions:

1. **Write the tests first.** Write unit and integration tests that cover the intended behavior before touching implementation code.
2. **Confirm they fail.** Run the tests and verify they fail for the right reason.
3. **Implement the fix.** Write only the code needed to make the failing tests pass.
4. **Confirm they pass.** Run the tests again and confirm all pass.

Do not submit or log a fix as complete until both unit and integration tests exist and are passing.

## Switching Projects
1. Read `ACTIVE_PROJECT` for the new project ID
2. Read `projects/{new-id}/index.md` and `projects/{new-id}/agent1.md`
3. Load the persona assigned to you for the new project
4. Read or create `projects/{new-id}/agent4.md`
