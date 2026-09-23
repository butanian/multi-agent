# context is king: Slack Capture App. Design

Date: 2026-08-14
Status: Approved in conversation (Aneesh + Agent 1), awaiting spec sign-off
Owner: Aneesh Butani (xFin)
Predecessors: contextisking design (2026-06-11), CIK plugin v0.5.x, July 2026 app kickoff (icon ready)

## Problem

A lot of durable knowledge is born in Slack: how a process changed, why something is determined the way it is, what a number means. Today the only path from a Slack thread to the playon-context card store is a person with Claude Code doing the capture by hand (example: the payout-vs-statement timing thread of 2026-08-13, captured manually as playon-context PR #48). Teammates without that setup have no path at all, so the knowledge evaporates.

## Goal

A Slack-native capture flow: trigger on a thread, distill it into a context card with the same discipline the CIK toolchain enforces locally, and open a PR in playon-context. The PR review on GitHub stays the quality gate. The capturer gets the PR link back in the thread.

## What we are building (exact deliverables)

**D1. Slack app `context is king`** (new repo `playon/cik-slack-capture`, Run-on-Slack Deno, same stack as slack-env-tracker):
- **Capture form** (link trigger): fields are thread permalink (required), retrieval keywords ("What would someone search to find this later?", optional), and a repo/system hint (optional). Reachable from Slack's workflow menu and pinnable as a channel bookmark. This is the command-style entry point.
- **`:cik:` reaction trigger** for in-context capture: an event trigger on `reaction_added`, filtered at the trigger to the custom `:cik:` emoji, captures the reacted message's thread with zero typing. No hints on this path; the ack reply links the form for a re-run with hints. Platform note (verified against docs.slack.dev 2026-08-14): Run-on-Slack supports only link, event, scheduled, and webhook triggers; message shortcuts and slash commands are classic-app features requiring a hosted Request URL, which our architecture decision rejected.
- A capture function that resolves the thread root, fetches the full thread via `conversations.replies`, builds the dispatch payload, fires `repository_dispatch` (event type `slack-capture`) at `playon/playon-context`, and replies in the thread: capture started, PR link will follow.
- Ephemeral error replies for bad permalinks and channels the bot is not in.
- Unit tests (permalink parsing, payload shaping, truncation) and a README documenting the trigger re-create gotcha.
- App manifest: name `context is king`, icon from `~/Downloads/context-is-king-icon.png`, installed to grid-playonsports.

**D2. Worker in `playon/playon-context`**:
- `.github/workflows/slack-capture.yml`, triggered by `repository_dispatch` type `slack-capture`, with a `dry_run` mode.
- `tools/slack-capture/` holding: the distiller prompt, a distill runner that calls the Claude API (`claude-sonnet-5`) and returns validated JSON, the promote-and-lint glue (real `cik-add`, card promoted into `domains/<repo>/`, root `routes_to` patched, `cik-lint`), the PR builder, and the Slack reply step.
- Golden-transcript tests for the distiller. Fixture #1 is the 2026-08-13 payout-timing thread, asserting: type gotcha, home statement-generation, keywords honored, no invented facts.

**D3. Platform setup** (manual, documented in the READMEs): app created and deployed, both triggers created, the custom `:cik:` emoji uploaded to the workspace, secrets set. Slack app env holds one fine-grained GitHub PAT (playon-context, `contents: write` only, for the dispatch call). playon-context Actions secrets hold `ANTHROPIC_API_KEY`, `SLACK_BOT_TOKEN`, and a read token for checking out context-is-king. The PR step uses the workflow's built-in `GITHUB_TOKEN`.

**D4. E2E validation**: dry-run demo in a test channel, then one real capture end to end, before announcing to xFin.

## Decisions (locked in design conversation)

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| 1 | Audience | xFin team first, workspace install | Tune quality and PR volume with a friendly audience, then widen. Fits the PDLC rollout narrative. |
| 2 | Trigger UX | Capture form (link trigger) + `:cik:` reaction (event trigger) | Run-on-Slack supports only link, event, scheduled, and webhook triggers; message shortcuts and slash commands need a classic app with hosted HTTP (verified 2026-08-14). The form covers capture-by-link with hints; the filtered `reaction_added` trigger delivers `channel_id` + `message_ts`, restoring zero-typing in-context capture. |
| 3 | Architecture | Thin Slack app + GitHub Action worker in playon-context | Reuses the real CIK toolchain (retrieval, placement, lint) with zero reimplementation drift. Secrets live in GitHub Actions. Slack app stays within Run-on-Slack limits. |
| 4 | Capture hints | Optional keywords + repo hint at trigger time | Threads talk in symptoms ("payments delayed"); retrieval needs the searchable phrasing ("statement generation schedule"). The capturer knows the vocabulary; Slack-sourced cards are anchorless so text is the whole retrieval surface. |
| 5 | Dedupe policy v1 | New card only, never auto-edit existing cards | Automated enrichment of verified cards from unverified chat is how good cards rot. PR body lists related cards and flags likely duplicates for the human reviewer. |
| 6 | Review surface | Auto-PR, no card-draft surface in Slack | The PR is the product and GitHub review is the existing editing gate. A draft-editing surface duplicates it on the platform least suited to interactivity. The single-shot capture form is the only interactive surface. |
| 7 | Anchors and status | Anchorless by default, `status: fresh` on merge, pinning is a human act | No `anchor_blobs` means the freshness engine correctly ignores unverifiable cards. PR approval is the verification step and the PR template says so. Distiller may propose anchors when the thread names files, landed unpinned with a verify-before-pinning note. |

## Architecture and flow

```
Slack thread
  |  :cik: reaction on a thread message  OR  capture form (permalink, keywords?, repo?)
  v
Run-on-Slack app (Deno, thin)
  |  resolve thread root, conversations.replies
  |  build payload, repository_dispatch -> playon/playon-context
  |  reply in thread: "Capturing... PR link will follow"
  v
GitHub Action @ playon-context (.github/workflows/slack-capture.yml)
  |  checkout playon-context + context-is-king (pinned ref)
  |  distill: Claude API (claude-sonnet-5) -> validated card JSON
  |  retrieval over the checked-out store -> related cards / duplicate flag
  |  real cik-add -> promote into domains/<repo>/ -> patch root routes_to -> cik-lint
  |  branch cik-slack-<channel>-<thread_ts> -> PR (or dry-run preview)
  v
Slack reply in thread: PR link (or failure notice with run link, or "nothing durable here" verdict)
```

## Component detail: Slack app

- **Payload** (client_payload, 9 top-level keys, within GitHub's 10-key limit on repository_dispatch):
  `channel`, `thread_ts`, `permalink`, `capturing_user` (display name + id), `repo_hint` (nullable), `keywords` (nullable), `truncated` (bool), `dry_run` (bool), `transcript` (array of `{user, ts, text}`).
- **Dry run plumbing**: repository_dispatch has no native inputs, so `dry_run` rides the payload. It is never exposed on the capturer-facing form; builders reach it via the manual `workflow_dispatch` entry point (fixture transcript, no Slack in the loop) or a local `slack run` dev instance of the app.
- **Size budget**: the serialized payload must stay under 60KB. If the thread exceeds it, drop oldest replies first (always keep the thread parent), set `truncated: true`, and note the count dropped. The distiller states truncation in the PR body.
- **Permalink parsing**: accepts both message and thread permalinks; a reply permalink resolves to its thread root via the `thread_ts` query param or a `conversations.replies` probe.
- **Platform gotchas honored**: single-shot form only, no durable inline interactivity; after any trigger input change, delete and re-create the trigger (`slack deploy` does not update trigger inputs), which applies to both the link trigger and the reaction event trigger; README states both. The reaction event trigger fires only in channels the app is a member of and is filtered at the trigger to the `:cik:` emoji, so cost stays contained.

## Component detail: worker

- **Distiller contract**: input is transcript + capturer hints + card conventions (types, no em dashes, body = answer plus durable why, Slack permalink as source line) + the list of existing root card ids + top retrieval hits for the thread content. Output is strict JSON: `{worthy: bool, reason, type, title, body, repo, confidence, related_card_ids[], proposed_anchors[]}`. `type` is one of architecture, gotcha, runbook, decision. The `reference` type is excluded until the known schema bug is fixed (reference cards currently fail to load).
- **Keyword guardrail**: keywords steer phrasing (they must appear in the title or opening sentences) and placement, never content. If keywords assert something the transcript does not support, the transcript wins.
- **Not-worthy path**: if `worthy: false` (pure chatter, no durable knowledge), no PR. The reply in the thread says so with the one-line reason.
- **Landing**: real `cik-add` with the distilled fields, then promote (move card from `.proposals/` into `domains/<repo>/`, apply the staged root patch as a surgical `routes_to` append, leave nothing in `.proposals/`), then `cik-lint`. Nothing ever merges into `.proposals/` (cards there are invisible to retrieval).
- **PR conventions**: branch `cik-slack-<channel>-<thread_ts>` (re-capture force-updates the same branch and PR), title prefix `cik-slack:`, body includes the thread permalink, capturing user, distiller confidence, related cards, likely-duplicate banner when applicable, truncation note when applicable, and the standing caveat that claims come from conversation, not code, so approval means the reviewer vouches for the content.
- **Reply step**: always runs (success or failure), posts PR link or failure notice + workflow run link back to the thread via `SLACK_BOT_TOKEN`.

## Error handling

| Failure | Behavior |
|---|---|
| Bad permalink / unparseable args | Form validation error, nothing dispatched |
| Bot not in channel | Ephemeral reply: invite @context-is-king, then retry |
| `conversations.replies` fails | In-thread reply with the error, no dispatch |
| `repository_dispatch` non-2xx | In-thread reply: capture failed to hand off, try again |
| Action fails at any step | Final always-run step posts failure + run link in thread |
| Distiller returns invalid JSON | One retry with the validation error appended, then fail visibly |
| Thread already captured | Same branch/PR force-updated, reply links the existing PR |

## Testing

- Deno unit tests: permalink parsing (message vs reply vs thread links), payload shaping, 60KB truncation behavior.
- Distiller golden tests: fixture transcripts with expected `{worthy, type, repo}` and negative assertions (no facts absent from the transcript). Fixture #1: the 2026-08-13 payout-timing thread. Fixture #2: a pure-chatter thread asserting `worthy: false`.
- Workflow `dry_run` input: full pipeline, no push, no PR; posts the would-be card into the thread. Doubles as the demo mode.
- E2E: one real capture in a test channel before the xFin announcement.

## Non-goals (v1)

- No card-draft or editing modal in Slack.
- No automated enrichment of existing cards from Slack content.
- No message shortcut and no slash command: they do not exist on Run-on-Slack (classic-app features requiring a hosted Request URL). Revisit only if the app ever moves to Bolt.
- No company-wide rollout, no per-user rate limiting until volume demands it. Note: v1 has no allowlist enforcement either; anyone in the workspace who finds the shortcut can technically use it. Scoping to xFin is social (where we announce it), not technical.
- No `reference`-type cards until the schema/lint bug is fixed upstream.

## Dependencies and open items

- `context-is-king` is consumed at a pinned ref (tag if one exists at build time, otherwise a SHA) in the workflow; bumps are deliberate. If the promote step proves generally useful it can be upstreamed later as `cik-add --live`; v1 keeps it as glue in `tools/slack-capture/`.
- The Slack app bot needs the usual read scopes (`channels:history`, `groups:history` for private channels it is invited to, `chat:write`, `commands`) and works only where invited.
- Store-integrity items tracked separately and not blockers: the `.proposals/` promotion backlog and the `type: reference` schema bug (this app avoids both by design).
