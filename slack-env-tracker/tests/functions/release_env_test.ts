import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { releaseEnvironment } from "../../functions/release_env.ts";

function createMockClient(
  existingItems: Record<string, Record<string, unknown>> = {},
) {
  const stored: Record<string, Record<string, unknown>> = { ...existingItems };
  return {
    apps: {
      datastore: {
        get: async ({ id }: { datastore: string; id: string }) => {
          if (stored[id]) return { ok: true, item: stored[id] };
          return { ok: false, item: undefined };
        },
        put: async ({ item }: { datastore: string; item: Record<string, unknown> }) => {
          stored[item.id as string] = item;
          return { ok: true };
        },
        query: async () => ({ ok: true, items: Object.values(stored) }),
      },
    },
    users: {
      info: async () => ({ ok: true, user: { real_name: "Test User" } }),
    },
    canvases: {
      create: async () => ({ ok: true, canvas_id: "C_MOCK" }),
      edit: async () => ({ ok: true }),
    },
  };
}

Deno.test("releaseEnvironment releases a claimed combo", async () => {
  const client = createMockClient({
    "qa1::monolith": {
      id: "qa1::monolith",
      environment: "QA1",
      service: "Monolith",
      owner_id: "U100",
      claimed_at: 1000,
    },
  });
  const result = await releaseEnvironment(client, "QA1", "Monolith");
  assertEquals(result.includes("released"), true);
});

Deno.test("releaseEnvironment reports when combo is not in use", async () => {
  const client = createMockClient({
    "qa1::monolith": {
      id: "qa1::monolith",
      environment: "QA1",
      service: "Monolith",
      owner_id: "",
      claimed_at: 0,
    },
  });
  const result = await releaseEnvironment(client, "QA1", "Monolith");
  assertEquals(result.includes("not currently in use"), true);
});

Deno.test("releaseEnvironment reports when combo does not exist", async () => {
  const client = createMockClient();
  const result = await releaseEnvironment(client, "QA1", "Unknown");
  assertEquals(result.includes("does not exist"), true);
});

Deno.test("releaseEnvironment allows releasing someone else's claim", async () => {
  const client = createMockClient({
    "qa1::monolith": {
      id: "qa1::monolith",
      environment: "QA1",
      service: "Monolith",
      owner_id: "U200",
      claimed_at: 1000,
    },
  });
  const result = await releaseEnvironment(client, "QA1", "Monolith");
  assertEquals(result.includes("released"), true);
});
