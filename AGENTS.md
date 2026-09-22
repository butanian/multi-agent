# AGENTS.md

Startup contract for a **Codex** pane in this swarm. Claude panes read `CLAUDE.md` and
get the same protocol injected by the `SessionStart` hook; Codex reads this file
instead, because it does not read `CLAUDE.md` and has no hook mechanism here.

This file is deliberately thin. `CLAUDE.md` and `COORDINATION.md` are the protocol.
Anything restated here would drift from them.

## 1. Who you are

**Your identity comes from the `AGENT_NUMBER` environment variable**, which the
launcher exports in your pane before starting you. Read it and believe it.

**Do not look for a banner.** `CLAUDE.md` used to say to read the banner printed above
you. That instruction was never executable: the launcher echoes the banner *before* the
engine starts, so it is in the terminal's scrollback and not in your context, and a
Codex pane cannot read prior scrollback at all. `AGENT_NUMBER` is the only identity
source.

`SWARM_ID` is exported the same way and identifies your swarm.

## 2. What to read, in this order

1. `CLAUDE.md`: the workspace protocol. Read it as your protocol, not as another
   engine's file.
2. `COORDINATION.md`: status markers and the signalling rules.
3. `agent$AGENT_NUMBER.md`: your role.
4. `swarms/$SWARM_ID/ACTIVE_PROJECT`: the current project id, then
   `projects/<id>/index.md` and `projects/<id>/agent$AGENT_NUMBER.md`.

## 3. How to talk to the other agents

```bash
./send-to-agent.sh <agent_number> "<message>"
```

That script is the only channel that reaches a real pane. It requires `SWARM_ID` to be
exported, and it drives iTerm2 through AppleScript.

**This is why your pane is launched outside the Codex sandbox.** Apple Events are
severed inside it: the same command returns `3` unsandboxed and
`Can't get application "iTerm2". (-1728)` under `codex sandbox`, with no seatbelt file
denial, so widening writable roots or `--add-dir` does not help. Your pane is started
with `-s danger-full-access -a never` for that reason. It is the same posture the Claude
panes already run with, not a wider one.

## 4. The review gate

**Every recorded decision needs review by an agent running a different engine family
than the one that produced it.** Claude work is reviewed by Codex; Codex work is
reviewed by Claude. That is decision D7.

The older rule in `agentN.md` requiring `/codex-collab` on every task **does not apply
to you**. It is a Claude-side skill, and a Codex pane reviewing its own output is not a
second engine, so satisfying it literally would defeat its purpose. Engine diversity is
the property that matters; the vendor name is not.

## 5. Before you resume anything

**Do not touch pre-existing state until `swarms/$SWARM_ID/RESUME_APPROVED` exists.**
Only Agent 1 creates that file, and only after Aneesh says go. If it is absent, report
what you would resume and then wait. This mirrors `CLAUDE.md` step 5, and it is spelled
out here because no hook will remind a Codex pane of it.

*Resuming* means acting on an existing `[ ]` or `[~]` task, an open decision in
`index.md`, or a queued `registry.md` row. The comms check, scaffolding a project that
does not exist yet, and answering a question Aneesh asked you directly are **not**
resuming.

That sentinel is a canary, not a gate. Nothing stops a pane proceeding without it. The
launcher preflight is the only real gate, and it gates startup only.

## 6. Writing style

Never use em dashes. Use a period or a comma instead. This applies to every artifact,
including commit messages.

## 7. Two things that will bite you

- **`codex exec` is not a pane worker.** It is one-shot and cannot receive a second
  message. The interactive TUI is what lives in a pane. `exec` stays useful for
  one-shot reviews.
- **`~/.codex/AGENTS.md` also loads**, before this file, and here it is a symlink to
  the user's global `CLAUDE.md`. This file is appended after it under a
  `--- project-doc ---` separator, so where the two differ, this one is more specific.
  Precedence is by position only. Nothing enforces it.
