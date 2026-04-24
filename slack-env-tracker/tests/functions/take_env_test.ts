import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { takeEnvironment } from "../../functions/take_env.ts";

function createMockClient(
  existingItems: Record<string, Record<string, unknown>> = {},
  allItems: Record<string, unknown>[] = [],
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
        query: async () => ({ ok: true, items: allItems }),
      },
    },
    users: {
      info: async ({ user }: { user: string }) => ({
        ok: true,
        user: { real_name: `User ${user}`, name: user },
      }),
    },
    canvases: {
      create: async () => ({ ok: true, canvas_id: "C_MOCK" }),
      edit: async () => ({ ok: true }),
    },
  };
}

Deno.test("takeEnvironment claims an unclaimed combo", async () => {
  const client = createMockClient();
  const result = await takeEnvironment(client, "QA1", "Monolith", "U100");
  assertEquals(result.includes("QA1"), true);
  assertEquals(result.includes("Monolith"), true);
});

Deno.test("takeEnvironment auto-creates a new combo", async () => {
  const client = createMockClient();
  const result = await takeEnvironment(client, "QA2", "NewService", "U100");
  assertEquals(result.includes("QA2"), true);
  assertEquals(result.includes("NewService"), true);
});

Deno.test("takeEnvironment rejects if claimed by someone else", async () => {
  const client = createMockClient({
    "qa1::monolith": {
      id: "qa1::monolith",
      environment: "QA1",
      service: "Monolith",
      owner_id: "U200",
      claimed_at: 1000,
    },
  });
  const result = await takeEnvironment(client, "QA1", "Monolith", "U100");
  assertEquals(result.includes("in use"), true);
});

Deno.test("takeEnvironment tells user if they already own it", async () => {
  const client = createMockClient({
    "qa1::monolith": {
      id: "qa1::monolith",
      environment: "QA1",
      service: "Monolith",
      owner_id: "U100",
      claimed_at: 1000,
    },
  });
  const result = await takeEnvironment(client, "QA1", "Monolith", "U100");
  assertEquals(result.includes("already have"), true);
});
