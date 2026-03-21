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
