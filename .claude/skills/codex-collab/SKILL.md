---
name: codex-collab
description: Collaborative review with Codex. Use this to stress-test decisions, validate designs, review code, and debate approaches before finalizing. Invoke when you need a second opinion, are uncertain, or before marking important work complete.
argument-hint: <topic or question to discuss>
allowed-tools: mcp__codex__codex, mcp__codex__codex-reply, Read, Grep, Glob
---

# Codex Collaboration Skill

Use this skill to engage Codex as a collaborative reviewer. Codex will challenge your thinking, surface edge cases, and help validate decisions before you commit to them.

## When to Use

- **Before finalizing decisions** — Have Codex stress-test your position
- **After drafting designs/plans** — Get feedback before implementation
- **When facing multiple approaches** — Debate trade-offs
- **After writing code** — Review for correctness, edge cases, risks
- **When uncertain** — Ask Codex before guessing

## How It Works

1. Frame your review clearly: share the decision, constraints, and your reasoning
2. Let the debate run — update your position if Codex surfaces real issues
3. Log the outcome before proceeding

## Usage

Invoke with a clear description of what you want to review:

```
/codex-collab Review my API design for the user authentication endpoint
/codex-collab Should I use Redis or in-memory caching for this use case?
/codex-collab Stress-test this error handling approach
```

## Instructions

When this skill is invoked:

1. Use the `mcp__codex__codex` tool to send the user's query/topic to Codex
2. Present Codex's response clearly
3. If the user wants to continue the discussion, use `mcp__codex__codex-reply` for follow-ups
4. Summarize key takeaways and any changes to the original position

## Arguments

$ARGUMENTS
