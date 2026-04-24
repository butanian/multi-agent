import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildCanvasMarkdown, EnvRecord } from "../../lib/canvas.ts";

Deno.test("buildCanvasMarkdown groups by environment alphabetically", () => {
  const records: EnvRecord[] = [
    { id: "staging::monolith", environment: "Staging", service: "Monolith", owner_id: "", owner_name: "", claimed_at: 0 },
    { id: "qa1::monolith", environment: "QA1", service: "Monolith", owner_id: "", owner_name: "", claimed_at: 0 },
  ];
  const md = buildCanvasMarkdown(records);
  const qaIndex = md.indexOf("QA1");
  const stagingIndex = md.indexOf("Staging");
  assertEquals(qaIndex < stagingIndex, true);
});

Deno.test("buildCanvasMarkdown sorts services alphabetically within environment", () => {
  const records: EnvRecord[] = [
    { id: "qa1::monolith", environment: "QA1", service: "Monolith", owner_id: "", owner_name: "", claimed_at: 0 },
    { id: "qa1::hq", environment: "QA1", service: "HQ", owner_id: "", owner_name: "", claimed_at: 0 },
  ];
  const md = buildCanvasMarkdown(records);
  const hqIndex = md.indexOf("HQ");
  const monolithIndex = md.indexOf("Monolith");
  assertEquals(hqIndex < monolithIndex, true);
});

Deno.test("buildCanvasMarkdown shows green circle for unclaimed", () => {
  const records: EnvRecord[] = [
    { id: "qa1::monolith", environment: "QA1", service: "Monolith", owner_id: "", owner_name: "", claimed_at: 0 },
  ];
  const md = buildCanvasMarkdown(records);
  assertEquals(md.includes("🟢 Monolith"), true);
  assertEquals(md.includes("🔴"), false);
});

Deno.test("buildCanvasMarkdown shows red circle with owner name for claimed", () => {
  const records: EnvRecord[] = [
    { id: "qa1::monolith", environment: "QA1", service: "Monolith", owner_id: "U123", owner_name: "Phi Nguyen", claimed_at: 1000 },
  ];
  const md = buildCanvasMarkdown(records);
  assertEquals(md.includes("🔴 Monolith (Phi Nguyen)"), true);
  assertEquals(md.includes("🟢"), false);
});

Deno.test("buildCanvasMarkdown returns empty message when no records", () => {
  const md = buildCanvasMarkdown([]);
  assertEquals(md.includes("No environments"), true);
});
