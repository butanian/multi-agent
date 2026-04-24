import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { makeId } from "../../lib/env_id.ts";

Deno.test("makeId lowercases and trims both parts", () => {
  assertEquals(makeId("  QA1 ", " Monolith "), "qa1::monolith");
});

Deno.test("makeId handles mixed case", () => {
  assertEquals(makeId("Staging", "GoFan-Next"), "staging::gofan-next");
});

Deno.test("makeId preserves hyphens and internal spaces", () => {
  assertEquals(makeId("QA1", "User Service"), "qa1::user service");
});
