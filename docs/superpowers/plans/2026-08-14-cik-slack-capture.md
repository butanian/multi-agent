# CIK Slack Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **In this workspace** execution is by the swarm: Agent 1 dispatches tasks to Agents 2/3/4 via `./send-to-agent.sh`, workers use isolated clones, Agent 1 gates and merges. The wave table below is the dispatch map.

**Goal:** Ship the "context is king" Slack capture app: a `:cik:` reaction or a capture form turns a Slack thread into a reviewed card PR in playon-context.

**Architecture:** Thin Run-on-Slack (Deno) app captures the thread and fires `repository_dispatch` at playon-context; a GitHub Action there distills the card with the Claude API, places it with the real cik toolchain, opens the PR, and replies in the thread. Spec: `docs/superpowers/specs/2026-08-14-cik-slack-capture-design.md` @ 9ef8eda.

**Tech Stack:** deno-slack-sdk (model on `~/Development/slack-env-tracker`), GitHub Actions, Node 20, context-is-king toolchain (`cik-add`, `cik-ask`, `cik-lint`), Claude API (`claude-sonnet-5`).

## Global Constraints

- No em dashes in ANY generated text: code comments, cards, PR bodies, Slack messages, commit messages. Use a period or comma.
- Never log or echo secret values. Reference `$VAR` only.
- Distilled card `type` is one of: architecture, gotcha, runbook, decision. Never reference (even after Task 0 fixes the enum; Slack-sourced reference cards are out of scope).
- Cards land in `domains/<repo>/` with the live root's `routes_to` patched. Nothing may remain in `.proposals/` (cards there are invisible to retrieval).
- Dispatch payload: max 10 top-level keys (GitHub limit), serialized size <= 60,000 bytes.
- Branch: `cik-slack-<channel>-<thread_ts with '.' replaced by '-'>`. PR title prefix: `cik-slack:`.
- Slack-sourced cards ship with NO `anchor_blobs` and `status: fresh`; `last_verified` set to the capture date.
- Workers: isolated clones only. Agent 3 owns `playon/cik-slack-capture`, Agent 4 owns the playon-context worker branch (`feat/slack-capture-worker` off current main, NOT the audit branch). Push the moment tests are green, before any review step.
- Commit messages follow each repo's existing conventions; write them yourself per step.

## Waves (dispatch map)

| Wave | Agent | Task(s) | Repo |
|------|-------|---------|------|
| 0 | Agent 2 | Task 0 (reference type enum fix) | context-is-king |
| 1 | Agent 3 | Tasks 1-5 (Deno app) | cik-slack-capture (new) |
| 1 | Agent 4 | Tasks 6-10 (worker) | playon-context |
| 2 | Agent 1 + Aneesh | Task 11 (platform setup + E2E) | both |

Wave 1 tasks are independent of Wave 0 except the workflow's pinned context-is-king ref (Task 10 pins whatever SHA includes Task 0; Agent 1 supplies it at integration).

---

### Task 0: Allow `reference` in the card type enum (context-is-king)

The store already contains a merged `type: reference` card (domains/member-service, PayPal tax ceiling) that the schema rejects, so `cik-lint` exits 1 on main and reference cards silently fail to load, while `cik-add --type reference` is advertised. Fix the enum.

**Files:**
- Modify: `src/card/schema.ts` (the `CARD_TYPES` array)
- Test: `tests/card/schema.test.ts` (or the existing schema test file; extend it)

**Interfaces:**
- Produces: `CardSchema` accepting `type: "reference"`. Everything else unchanged.

- [ ] **Step 1: Write the failing test**

```ts
import { CardSchema, CARD_TYPES } from "../../src/card/schema.js";

it("accepts reference as a card type", () => {
  expect(CARD_TYPES).toContain("reference");
  const card = CardSchema.parse({
    id: "member-service-some-reference",
    type: "reference",
    systems: ["member-service"],
    repos: ["member-service"],
    anchors: [],
    links: [],
    body: "x",
  });
  expect(card.type).toBe("reference");
});
```

Adjust the parsed object to the real required fields if the schema requires more; copy the shape from an existing passing schema test in the same file.

- [ ] **Step 2: Run it, verify it fails** with a zod enum error mentioning the allowed types.
- [ ] **Step 3: Add `"reference"` to `CARD_TYPES` in `src/card/schema.ts`.** One-word change; do not touch edge or status enums.
- [ ] **Step 4: Full gate**: `npm test && npm run typecheck && npm run build`. All green.
- [ ] **Step 5: Verify against the real store**: cik-lint has NO `--store` flag; it reads `CIK_CARDS_DIR` (default `$PWD/.context`). Read `bin/cik-lint.mjs` for the exact contract and point `CIK_CARDS_DIR` at the real playon-context cards location. The pre-existing reference-card failure (member-service paypal-managed-subscriptions) must be gone; note any remaining unrelated warnings in the PR body.
- [ ] **Step 6: Commit, push branch `fix/reference-card-type`, open PR** on context-is-king titled "fix: accept reference card type in schema and lint". Body: the store already holds a merged reference card, cik-add advertises the type, the enum was the only blocker. Signal Agent 1 with the PR number.

---

### Task 1: Scaffold `playon/cik-slack-capture`

Agent 1 creates the empty GitHub repo (internal) before dispatch. Model every file on `~/Development/slack-env-tracker` (read it, it is the org's proven pattern).

**Files:**
- Create: `deno.jsonc`, `import_map.json`, `slack.json`, `.gitignore`, `assets/icon.png` (copy from `~/Downloads/context-is-king-icon.png`), `manifest.ts` (skeleton), `README.md` (skeleton)

**Interfaces:**
- Produces: a repo where `deno task test` and `slack manifest validate` run clean.

- [ ] **Step 1: Clone the empty repo** to `~/Development/cik-slack-capture-agent3` (your isolated clone), copy `deno.jsonc`, `import_map.json`, `slack.json`, `.gitignore` from slack-env-tracker verbatim, then update the name fields.
- [ ] **Step 2: Copy the icon** to `assets/icon.png`.
- [ ] **Step 3: Write the skeleton manifest** (workflows added in Task 5):

```ts
import { Manifest } from "deno-slack-sdk/mod.ts";

export default Manifest({
  name: "context is king",
  description: "Capture a Slack thread into the playon-context card store as a reviewed PR",
  icon: "assets/icon.png",
  workflows: [],
  outgoingDomains: ["api.github.com"],
  botScopes: [
    "chat:write",
    "chat:write.public",
    "channels:history",
    "groups:history",
    "reactions:read",
    "users:read",
  ],
});
```

- [ ] **Step 4: Verify** `slack manifest validate` passes (or `deno check manifest.ts` if not logged in yet).
- [ ] **Step 5: Commit** "chore: scaffold Run-on-Slack app" and push `main`.

---

### Task 2: Permalink parser (`lib/permalink.ts`)

**Files:**
- Create: `lib/permalink.ts`
- Test: `tests/lib/permalink_test.ts`

**Interfaces:**
- Produces: `parsePermalink(url: string): { channel: string; ts: string; threadTs?: string } | null`

- [ ] **Step 1: Write failing tests**

```ts
import { assertEquals } from "std/assert/mod.ts";
import { parsePermalink } from "../../lib/permalink.ts";

Deno.test("parses a plain message permalink", () => {
  assertEquals(
    parsePermalink("https://playonsports.slack.com/archives/C057GMLG25B/p1786716584334739"),
    { channel: "C057GMLG25B", ts: "1786716584.334739", threadTs: undefined },
  );
});

Deno.test("parses a reply permalink with thread_ts", () => {
  assertEquals(
    parsePermalink("https://playonsports.slack.com/archives/C057GMLG25B/p1786716584334739?thread_ts=1786659951.662889&cid=C057GMLG25B"),
    { channel: "C057GMLG25B", ts: "1786716584.334739", threadTs: "1786659951.662889" },
  );
});

Deno.test("returns null on junk", () => {
  assertEquals(parsePermalink("https://example.com/nope"), null);
});
```

- [ ] **Step 2: Run `deno task test`, verify failure** (module not found).
- [ ] **Step 3: Implement**

```ts
export interface ParsedPermalink { channel: string; ts: string; threadTs?: string }

export function parsePermalink(url: string): ParsedPermalink | null {
  const m = url.match(/\/archives\/([A-Z0-9]+)\/p(\d{10})(\d{6})/);
  if (!m) return null;
  const tm = url.match(/[?&]thread_ts=(\d+\.\d+)/);
  return { channel: m[1], ts: `${m[2]}.${m[3]}`, threadTs: tm ? tm[1] : undefined };
}
```

- [ ] **Step 4: Tests green. Commit** "feat: permalink parser".

---

### Task 3: Transcript builder with 60KB budget (`lib/payload.ts`)

**Files:**
- Create: `lib/payload.ts`
- Test: `tests/lib/payload_test.ts`

**Interfaces:**
- Produces:
  - `interface TranscriptMsg { user: string; ts: string; text: string }`
  - `buildTranscript(msgs: TranscriptMsg[], budgetBytes?: number): { transcript: TranscriptMsg[]; truncated: boolean }` (default budget 60000; drops oldest replies first, always keeps `msgs[0]`, the thread parent)
  - `buildClientPayload(args: { channel: string; threadTs: string; permalink: string; capturingUser: string; repoHint: string | null; keywords: string | null; dryRun: boolean; msgs: TranscriptMsg[] }): object` returning exactly the 9 spec keys: `channel, thread_ts, permalink, capturing_user, repo_hint, keywords, truncated, dry_run, transcript`.

- [ ] **Step 1: Write failing tests**: (a) under budget returns all + `truncated: false`; (b) over budget keeps parent, drops oldest replies until it fits, `truncated: true`; (c) `buildClientPayload` output has exactly those 9 keys and serializes under 60000 bytes for a padded input.

```ts
Deno.test("truncates oldest replies first, keeps parent", () => {
  const big = "x".repeat(20000);
  const msgs = [
    { user: "U1", ts: "1", text: "parent" },
    { user: "U2", ts: "2", text: big },
    { user: "U3", ts: "3", text: big },
    { user: "U4", ts: "4", text: big },
  ];
  const { transcript, truncated } = buildTranscript(msgs, 45000);
  assertEquals(truncated, true);
  assertEquals(transcript[0].text, "parent");
  assertEquals(transcript.map((m) => m.ts), ["1", "3", "4"]);
});
```

- [ ] **Step 2: Verify failure.**
- [ ] **Step 3: Implement**

```ts
export interface TranscriptMsg { user: string; ts: string; text: string }

const size = (v: unknown) => new TextEncoder().encode(JSON.stringify(v)).length;

export function buildTranscript(msgs: TranscriptMsg[], budgetBytes = 60000) {
  if (size(msgs) <= budgetBytes) return { transcript: msgs, truncated: false };
  const parent = msgs[0];
  let tail = msgs.slice(1);
  while (tail.length && size([parent, ...tail]) > budgetBytes) tail = tail.slice(1);
  return { transcript: [parent, ...tail], truncated: true };
}
```

`buildClientPayload` composes the object literally; keep the transcript budget at 55000 inside it so the whole payload clears 60000 with headroom.

- [ ] **Step 4: Tests green. Commit** "feat: transcript and dispatch payload builders".

---

### Task 4: Capture function (`functions/capture_thread.ts`)

**Files:**
- Create: `functions/capture_thread.ts`
- Test: `tests/functions/capture_thread_test.ts` (test the exported pure helper `resolveTarget`; the handler itself is covered by Task 11 E2E)

**Interfaces:**
- Consumes: `parsePermalink`, `buildTranscript`, `buildClientPayload`.
- Produces: `CaptureThreadFunction` with inputs `{ channel_id?, message_ts?, permalink?, keywords?, repo_hint?, capturing_user }` (only `capturing_user` required). Reads env `GITHUB_PAT`.

- [ ] **Step 1: Write the failing test for `resolveTarget`**: permalink wins when present; else `{channel_id, message_ts}`; error string when neither.
- [ ] **Step 2: Verify failure.**
- [ ] **Step 3: Implement the function**

```ts
import { DefineFunction, Schema, SlackFunction } from "deno-slack-sdk/mod.ts";
import { parsePermalink } from "../lib/permalink.ts";
import { buildClientPayload, buildTranscript, TranscriptMsg } from "../lib/payload.ts";

export const CaptureThreadFunction = DefineFunction({
  callback_id: "capture_thread",
  title: "Capture thread into playon-context",
  source_file: "functions/capture_thread.ts",
  input_parameters: {
    properties: {
      channel_id: { type: Schema.slack.types.channel_id },
      message_ts: { type: Schema.types.string },
      permalink: { type: Schema.types.string },
      keywords: { type: Schema.types.string },
      repo_hint: { type: Schema.types.string },
      capturing_user: { type: Schema.slack.types.user_id },
    },
    required: ["capturing_user"],
  },
  output_parameters: { properties: {}, required: [] },
});

export function resolveTarget(i: { permalink?: string; channel_id?: string; message_ts?: string }):
  | { channel: string; ts: string; threadTs?: string }
  | { error: string } {
  if (i.permalink) {
    const p = parsePermalink(i.permalink);
    return p ?? { error: "That does not look like a Slack message permalink." };
  }
  if (i.channel_id && i.message_ts) return { channel: i.channel_id, ts: i.message_ts };
  return { error: "No message to capture." };
}

export default SlackFunction(CaptureThreadFunction, async ({ inputs, client, env }) => {
  const target = resolveTarget(inputs);
  if ("error" in target) return { error: target.error };
  const { channel } = target;

  const post = (text: string, thread?: string) =>
    client.chat.postMessage({ channel, thread_ts: thread, text });

  // Resolve the thread root: a reply carries thread_ts; a root is its own ts.
  const probe = await client.conversations.replies({ channel, ts: target.ts, limit: 1 });
  if (!probe.ok) {
    return { error: `Cannot read that channel (${probe.error}). Invite @context is king and retry.` };
  }
  const rootTs = target.threadTs ?? probe.messages?.[0]?.thread_ts ?? target.ts;

  // Fetch the full thread, oldest first, paging on next_cursor.
  const raw: { user?: string; ts: string; text?: string }[] = [];
  let cursor: string | undefined;
  do {
    const page = await client.conversations.replies({ channel, ts: rootTs, limit: 200, cursor });
    if (!page.ok) return { error: `Thread fetch failed: ${page.error}` };
    raw.push(...(page.messages ?? []));
    cursor = page.response_metadata?.next_cursor || undefined;
  } while (cursor);

  // Best-effort display names, cached per user id.
  const names = new Map<string, string>();
  const nameOf = async (id?: string) => {
    if (!id) return "unknown";
    if (!names.has(id)) {
      const u = await client.users.info({ user: id });
      names.set(id, u.ok ? (u.user?.profile?.display_name || u.user?.real_name || id) : id);
    }
    return names.get(id)!;
  };
  const msgs: TranscriptMsg[] = [];
  for (const m of raw) if (m.text) msgs.push({ user: await nameOf(m.user), ts: m.ts, text: m.text });

  const permalinkResp = await client.chat.getPermalink({ channel, message_ts: rootTs });
  const payload = buildClientPayload({
    channel,
    threadTs: rootTs,
    permalink: permalinkResp.ok ? permalinkResp.permalink! : (inputs.permalink ?? ""),
    capturingUser: await nameOf(inputs.capturing_user),
    repoHint: inputs.repo_hint || null,
    keywords: inputs.keywords || null,
    dryRun: false,
    msgs,
  });

  const resp = await fetch("https://api.github.com/repos/playon/playon-context/dispatches", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GITHUB_PAT}`,
      Accept: "application/vnd.github+json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ event_type: "slack-capture", client_payload: payload }),
  });
  if (resp.status !== 204) {
    await post(`Capture hand-off failed (GitHub ${resp.status}). Try again in a minute.`, rootTs);
    return { error: `dispatch failed: ${resp.status}` };
  }

  await post("Capturing this thread into playon-context. The PR link will follow here.", rootTs);
  return { outputs: {} };
});
```

- [ ] **Step 4: `deno task test` green, `deno check` clean. Commit** "feat: capture function".

---

### Task 5: Workflows, triggers, manifest wiring, README

**Files:**
- Create: `workflows/capture_form_workflow.ts`, `workflows/capture_reaction_workflow.ts`, `triggers/capture_form_trigger.ts`, `triggers/capture_reaction_trigger.ts`
- Modify: `manifest.ts` (add both workflows), `README.md`

**Interfaces:**
- Consumes: `CaptureThreadFunction` (Task 4).

- [ ] **Step 1: Form workflow** (mirror env-tracker's OpenForm idiom):

```ts
import { DefineWorkflow, Schema } from "deno-slack-sdk/mod.ts";
import { CaptureThreadFunction } from "../functions/capture_thread.ts";

export const CaptureFormWorkflow = DefineWorkflow({
  callback_id: "capture_form_workflow",
  title: "Capture context",
  input_parameters: {
    properties: { interactivity: { type: Schema.slack.types.interactivity } },
    required: ["interactivity"],
  },
});

const form = CaptureFormWorkflow.addStep(Schema.slack.functions.OpenForm, {
  title: "Capture context",
  interactivity: CaptureFormWorkflow.inputs.interactivity,
  submit_label: "Capture",
  fields: {
    elements: [
      { name: "permalink", title: "Thread permalink", type: Schema.types.string },
      { name: "keywords", title: "What would someone search to find this later?", type: Schema.types.string },
      { name: "repo", title: "Repo or system (optional)", type: Schema.types.string },
    ],
    required: ["permalink"],
  },
});

CaptureFormWorkflow.addStep(CaptureThreadFunction, {
  permalink: form.outputs.fields.permalink,
  keywords: form.outputs.fields.keywords,
  repo_hint: form.outputs.fields.repo,
  capturing_user: CaptureFormWorkflow.inputs.interactivity.interactor.id,
});
```

- [ ] **Step 2: Reaction workflow**: inputs `{ channel_id, message_ts, capturing_user }`, single step calling `CaptureThreadFunction` with those three.
- [ ] **Step 3: Triggers.** Form trigger is `TriggerTypes.Shortcut` with `interactivity: TriggerContextData.Shortcut.interactivity` (copy env-tracker's shape). Reaction trigger:

```ts
import { Trigger } from "deno-slack-api/types.ts";
import { TriggerContextData, TriggerEventTypes, TriggerTypes } from "deno-slack-api/mod.ts";
import { CaptureReactionWorkflow } from "../workflows/capture_reaction_workflow.ts";

const trigger: Trigger<typeof CaptureReactionWorkflow.definition> = {
  type: TriggerTypes.Event,
  name: "Capture on :cik: reaction",
  description: "React with :cik: to capture a thread into playon-context",
  workflow: `#/workflows/${CaptureReactionWorkflow.definition.callback_id}`,
  event: {
    event_type: TriggerEventTypes.ReactionAdded,
    all_resources: true,
    filter: { version: 1, root: { statement: "{{data.reaction}} == cik" } },
  },
  inputs: {
    channel_id: { value: TriggerContextData.Event.ReactionAdded.channel_id },
    message_ts: { value: TriggerContextData.Event.ReactionAdded.message_ts },
    capturing_user: { value: TriggerContextData.Event.ReactionAdded.user_id },
  },
};

export default trigger;
```

- [ ] **Step 4: Wire both workflows into `manifest.ts`.** `slack manifest validate` (or `deno check` on every file) clean; `deno task test` green.
- [ ] **Step 5: README**: setup (`slack env add GITHUB_PAT <fine-grained PAT, playon-context contents:write>`), trigger creation (`slack trigger create --trigger-def triggers/<file>.ts`), the trigger re-create gotcha (input changes require delete + re-create; `slack deploy` does not update them), the `:cik:` emoji prerequisite, the invite-the-bot requirement, and the capture flow diagram from the spec.
- [ ] **Step 6: Commit** "feat: workflows, triggers, README" and push. Signal Agent 1.

---

### Task 6: Worker payload validation + fixtures (playon-context)

Branch `feat/slack-capture-worker` off playon-context main. Everything for Tasks 6-10 lives under `tools/slack-capture/` except the workflow file.

**Files:**
- Create: `tools/slack-capture/validate.mjs`, `tools/slack-capture/fixtures/payout-timing.json`, `tools/slack-capture/fixtures/chatter.json`
- Test: `tools/slack-capture/tests/validate.test.mjs` (plain `node --test`)

**Interfaces:**
- Produces: `validatePayload(obj): { ok: true, payload } | { ok: false, errors: string[] }` enforcing the 9 keys, types, non-empty transcript array of `{user, ts, text}` strings.

- [ ] **Step 1: Build the fixtures.** `payout-timing.json`: a payload whose transcript is the 2026-08-13 payments-delayed thread (channel C057GMLG25B, thread_ts 1786659951.662889; reconstruct the messages from the thread, author display names fine). `keywords`: "payout schedule statement timing friday". `chatter.json`: a 5-message lunch-plans thread, no keywords.
- [ ] **Step 2: Failing tests**: valid fixture passes; missing key, wrong-typed transcript, and empty transcript each fail with a named error.
- [ ] **Step 3: Implement `validatePayload`** with hand-rolled checks (no new dependencies in this repo).
- [ ] **Step 4: `node --test tools/slack-capture/tests/` green. Commit** "feat: slack-capture payload validation and fixtures".

---

### Task 7: Distiller (`tools/slack-capture/distill.mjs` + `prompt.md`)

**Files:**
- Create: `tools/slack-capture/distill.mjs`, `tools/slack-capture/prompt.md`
- Test: `tools/slack-capture/tests/distill.test.mjs`

**Interfaces:**
- Produces: `distill({ payload, roots, relatedCards, fetchImpl? }): Promise<Distilled>` where `Distilled = { worthy, reason, type, title, body, repo, home_root, confidence, related_card_ids, proposed_anchors }`. `fetchImpl` defaults to global fetch; tests inject a stub. Reads `ANTHROPIC_API_KEY` from env. Model: `claude-sonnet-5`, `max_tokens: 3000`.
- Consumes: nothing from other tasks (roots/relatedCards passed in by Task 9).

- [ ] **Step 1: Write `prompt.md`** containing: the card conventions (type meanings; title phrased for retrieval; body = answer plus durable why; no em dashes; Slack permalink as a Source line; keywords MUST appear in the title or opening sentences; keywords steer phrasing and placement, never content, the transcript wins on any conflict; claims come from conversation so hedge unverified infra claims), the placeholders `{{TRANSCRIPT}}`, `{{KEYWORDS}}`, `{{REPO_HINT}}`, `{{ROOTS}}` (list of real root ids), `{{RELATED}}`, and the exact output contract: respond with ONLY a JSON object `{worthy, reason, type, title, body, repo, home_root, confidence, related_card_ids, proposed_anchors}`; `home_root` MUST be one of `{{ROOTS}}`; `type` one of architecture, gotcha, runbook, decision; `worthy: false` with a one-line reason for chatter.
- [ ] **Step 2: Failing tests with a stubbed `fetchImpl`**: (a) happy path parses the stub's JSON; (b) invalid JSON from the stub triggers exactly one retry with the validation error appended to the user message, then succeeds; (c) two invalid responses throw; (d) `home_root` not in roots list is rejected as invalid (drives the retry).
- [ ] **Step 3: Implement.** POST `https://api.anthropic.com/v1/messages` with headers `x-api-key`, `anthropic-version: 2023-06-01`; body `{ model: "claude-sonnet-5", max_tokens: 3000, messages: [{ role: "user", content: rendered }] }`. Parse `content[0].text`, strip any code fences, `JSON.parse`, validate fields (types above, confidence 0..1, home_root in roots). On validation failure, retry once with the error text appended. Throw after the second failure.
- [ ] **Step 4: Tests green. Commit** "feat: slack-capture distiller".

---

### Task 8: Promote step (`tools/slack-capture/promote.mjs`)

`cik-add` stages pr-tier cards to `.proposals/` (card + patched root copy). Retrieval ignores dot-dirs, so the worker must land them live, exactly as the manual flow does.

**Files:**
- Create: `tools/slack-capture/promote.mjs`
- Test: `tools/slack-capture/tests/promote.test.mjs` (uses a tmp-dir fixture store)

**Interfaces:**
- Produces: `promote({ storeDir, cardId, rootId, capturedOn }): { cardPath }`. Moves `.proposals/<cardId>.md` into the directory containing the live root file whose frontmatter id is `rootId`, appends `cardId` to that live root's `routes_to` (supports BOTH the single-line flow form `- routes_to: [a, b]` and the block-list form), stamps the card's frontmatter with `status: fresh` and `last_verified: "<capturedOn>"` (YYYY-MM-DD, inserted before the closing `---` if absent), deletes both `.proposals/` staging files, throws if anything is missing. It never adds `anchor_blobs`; Slack-sourced cards stay unpinned by design.

- [ ] **Step 1: Failing tests**: (a) flow-form root gains `, <cardId>]` before the closing bracket; (b) block-form root gains a correctly indented `      - <cardId>` line as the last entry; (c) card file ends up next to the root; (d) `.proposals/` is empty afterward; (e) idempotent, appending an id already present is a no-op; (f) the promoted card's frontmatter carries `status: fresh` and `last_verified: "<capturedOn>"` and has no `anchor_blobs` key.
- [ ] **Step 2: Verify failures.**
- [ ] **Step 3: Implement.** Find the live root with a recursive scan of `domains/` for a file whose frontmatter contains `id: <rootId>`. For flow form, regex `(- routes_to: \[)([^\]]*)(\])` on the root text. For block form, find the `- routes_to:` line, collect the following more-indented lines, insert after the last one at the same indent. Write with the file's original trailing-newline state preserved.
- [ ] **Step 4: Tests green. Commit** "feat: slack-capture promote step".

---

### Task 9: Orchestrator (`tools/slack-capture/run.mjs`)

**Files:**
- Create: `tools/slack-capture/run.mjs`, `tools/slack-capture/pr-body.mjs`
- Test: `tools/slack-capture/tests/pr-body.test.mjs`, `tools/slack-capture/tests/branch-name.test.mjs`

**Interfaces:**
- Consumes: `validatePayload` (Task 6), `distill` (Task 7), `promote` (Task 8), context-is-king CLIs at `../../context-is-king` (path from env `CIK_DIR`, default `./context-is-king`).
- Produces: exit 0 always on handled paths; writes `channel`, `thread_ts`, `message` to `$GITHUB_OUTPUT` for the reply step. Exported pure helpers: `branchName(channel, threadTs)` returning `cik-slack-<channel>-<threadTs.replace(".", "-")>` and `buildPrBody({payload, distilled, duplicateOf})`.

- [ ] **Step 1: Failing tests** for `branchName` (dot replacement) and `buildPrBody` (contains permalink, capturing user, confidence, related cards list, the conversation-not-code caveat, a "Possible duplicate of `<id>`, consider enriching instead" banner when `duplicateOf` is set, a truncation note when `payload.truncated`, and a "proposed anchors are unverified, verify before pinning" note when `proposed_anchors` is non-empty).
- [ ] **Step 2: Implement helpers, tests green.**
- [ ] **Step 3: Implement `run.mjs` flow** (read payload from `process.env.PAYLOAD`, or the file named by `process.env.FIXTURE` for workflow_dispatch runs; `dry_run` true if payload.dry_run or `process.env.DRY_RUN_INPUT === "true"`):
  1. `validatePayload`; on failure write a failure `message` output and exit 0.
  2. Collect roots: scan `domains/` frontmatter for `type: root`, list ids.
  3. Related cards: run `node $CIK_DIR/bin/cik-ask.mjs "<title-less query: keywords + first 300 chars of parent message>" --format json --lexical` with env `CIK_CONTEXT_ROOTS=$PWD` (cik-ask has NO --store flag and its default store path does not exist in CI; `--lexical` avoids pulling a ~90MB semantic model per CI run for an advisory signal, semantic silently falls back to lexical anyway). Take top 5 ids; `duplicateOf` = top hit when its score field marks a strong hit (use the JSON's ordering, take hit #1 only if its id shares 3+ terms with the keywords/title; keep this heuristic in one small function).
  4. `distill` with payload, roots, related.
  5. If `!worthy`: `message` = "No durable knowledge found in this thread. Reason: <reason>", exit 0.
  6. Run cik-add via `execFileSync("node", [...])` with an argument ARRAY (never shell string interpolation, transcript text is untrusted): `--type <type> --title <title> --body <body string> --repo <repo> --root <home_root> --store .`, plus one `--anchor <path>` per entry in `proposed_anchors` (they land unpinned, there is no code checkout to pin against).
  7. Parse the staged card id AND path from cik-add stdout (format: `cik add: wrote <id> [<tier>] -> <path>`; use the printed path, do not reconstruct it), then `promote({ storeDir: ".", cardId, rootId: home_root, capturedOn: <payload capture date, UTC YYYY-MM-DD> })`.
  8. Run cik-lint with `CIK_CARDS_DIR` pointed at this store's cards location per `bin/cik-lint.mjs`'s actual contract (it has NO --store flag; its default is `$PWD/.context`, which lints nothing here); treat nonzero as failure (Task 0 fixed the pre-existing failure).
  9. If dry_run: `message` = the would-be card body (first 2500 chars) + "DRY RUN, no PR opened", exit 0.
  10. Else: `git checkout -B <branchName>`, `git add domains/ .proposals/`, commit `cik-slack: <title>` with an explicit identity (`git -c user.name="cik-slack-capture" -c user.email="cik-slack-capture@playonsports.com" commit ...`, CI runners have no git identity configured), `git push -f origin <branch>`, then `gh pr list --head <branch> --json number` and either `gh pr create` (title `cik-slack: <title>`, body from `buildPrBody`) or note the existing PR; `message` = "Card PR ready: <url>".
  11. Any thrown error: catch at top level, `message` = "Capture failed: <one-line error>. Run: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID", exit 0 (the reply step must still run and the workflow must not double-report).
- [ ] **Step 4: All `node --test tools/slack-capture/tests/` green. Commit** "feat: slack-capture orchestrator".

---

### Task 10: Workflow (`.github/workflows/slack-capture.yml`)

**Files:**
- Create: `.github/workflows/slack-capture.yml`

**Interfaces:**
- Consumes: `run.mjs` contract from Task 9 (env `PAYLOAD`/`FIXTURE`/`DRY_RUN_INPUT`/`CIK_DIR`, outputs `channel`, `thread_ts`, `message`).

- [ ] **Step 1: Write the workflow**

```yaml
name: slack-capture
on:
  repository_dispatch:
    types: [slack-capture]
  workflow_dispatch:
    inputs:
      fixture:
        description: Path to a payload fixture JSON in the repo
        required: true
      dry_run:
        description: "true = no push, no PR"
        default: "true"
permissions:
  contents: write
  pull-requests: write
concurrency:
  group: slack-capture-${{ github.event.client_payload.thread_ts || inputs.fixture }}
jobs:
  capture:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/checkout@v4
        with:
          repository: playon/context-is-king
          ref: PINNED_BY_AGENT_1_AT_INTEGRATION
          token: ${{ secrets.CIK_READ_TOKEN }}
          path: context-is-king
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - name: Build context-is-king
        run: cd context-is-king && npm ci && npm run build
      - name: Capture
        id: run
        env:
          PAYLOAD: ${{ toJson(github.event.client_payload) }}
          FIXTURE: ${{ inputs.fixture }}
          DRY_RUN_INPUT: ${{ inputs.dry_run }}
          CIK_DIR: ./context-is-king
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          GH_TOKEN: ${{ github.token }}
        run: node tools/slack-capture/run.mjs
      - name: Reply in Slack
        if: always()
        env:
          SLACK_BOT_TOKEN: ${{ secrets.SLACK_BOT_TOKEN }}
          CHANNEL: ${{ steps.run.outputs.channel }}
          THREAD_TS: ${{ steps.run.outputs.thread_ts }}
          MESSAGE: ${{ steps.run.outputs.message || format('Capture failed before producing a result. Run: {0}/{1}/actions/runs/{2}', github.server_url, github.repository, github.run_id) }}
        run: |
          set -eo pipefail
          if [ -z "$CHANNEL" ]; then echo "fixture run, no Slack reply"; exit 0; fi
          jq -n --arg c "$CHANNEL" --arg t "$THREAD_TS" --arg m "$MESSAGE" \
            '{channel: $c, thread_ts: $t, text: $m}' \
          | curl -sS -X POST https://slack.com/api/chat.postMessage \
              -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
              -H "Content-Type: application/json" -d @- \
          | jq -e '.ok' >/dev/null
```

Payload and message text reach the shell ONLY via env vars and jq --arg, never inline `${{ }}` interpolation into `run:` bodies (script-injection guard; transcript text is untrusted).

- [ ] **Step 2: Extract-test the reply block locally** under `bash -eo pipefail` with stub env values against a mock (or skip the curl with CHANNEL empty) and assert the output, per the CI-shell-fidelity rule.
- [ ] **Step 3: Validate the YAML** with `actionlint` if available, else `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/slack-capture.yml'))"`.
- [ ] **Step 4: Commit** "feat: slack-capture workflow", push branch, open the playon-context PR titled "feat: Slack capture worker (workflow + tools)". If the cik context gate fires with `CIK_GAP_CANDIDATES`, follow the gap-ask protocol and escalate the decision to Agent 1. Signal Agent 1.

---

### Task 11: Platform setup + E2E (Agent 1 with Aneesh)

- [ ] **Step 1:** Merge order: Task 0 PR (context-is-king) first, note its SHA; Agent 1 replaces `PINNED_BY_AGENT_1_AT_INTEGRATION` in the worker PR with that SHA; merge worker PR; merge/deploy app repo.
- [ ] **Step 2 (Aneesh, interactive):** create the two fine-grained PATs (dispatch PAT for the Slack env; CIK_READ_TOKEN) and set `ANTHROPIC_API_KEY`, `SLACK_BOT_TOKEN`, `CIK_READ_TOKEN` in playon-context Actions secrets. `slack env add GITHUB_PAT ...` on the deployed app. Upload the `:cik:` emoji. `slack deploy`, create both triggers.
- [ ] **Step 3:** Fixture dry run: `gh workflow run slack-capture -f fixture=tools/slack-capture/fixtures/payout-timing.json -f dry_run=true`; assert the run summary shows a gotcha card homed under statement-generation whose title or opening line contains the fixture keywords, and no facts absent from the transcript (this is the golden assertion from the spec, executed live). EXPECT the possible-duplicate banner naming the PR #48 payout-timing card and assert it IS present; it demonstrates dedupe working, it is not a failure.
- [ ] **Step 4:** Real E2E in a test channel: post a small thread, react `:cik:`, verify ack, PR, and the in-thread PR link; then run the form path with keywords on the same thread and verify the SAME PR updates (idempotency). Close the test PR.
- [ ] **Step 5:** Announce to xFin with a one-paragraph how-to; update registry.md and projects/contextisking/index.md.
