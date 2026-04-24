import { DefineFunction, Schema, SlackFunction } from "deno-slack-sdk/mod.ts";
import { makeId } from "../lib/env_id.ts";
import { refreshCanvas } from "../lib/canvas.ts";

export const TakeEnvFunction = DefineFunction({
  callback_id: "take_env",
  title: "Take Environment",
  source_file: "functions/take_env.ts",
  input_parameters: {
    properties: {
      environment: { type: Schema.types.string },
      service: { type: Schema.types.string },
      user_id: { type: Schema.slack.types.user_id },
    },
    required: ["environment", "service", "user_id"],
  },
  output_parameters: {
    properties: {
      message: { type: Schema.types.string },
    },
    required: ["message"],
  },
});

// deno-lint-ignore no-explicit-any
export async function takeEnvironment(client: any, environment: string, service: string, userId: string): Promise<string> {
  const env = environment.trim();
  const svc = service.trim();
  const id = makeId(env, svc);

  const existing = await client.apps.datastore.get({ datastore: "environments", id });

  if (existing.ok && existing.item) {
    if (existing.item.owner_id === userId) {
      return `You already have ${existing.item.environment} - ${existing.item.service}.`;
    }
    if (existing.item.owner_id) {
      const ownerResp = await client.users.info({ user: existing.item.owner_id });
      const ownerName = ownerResp.ok ? (ownerResp.user?.real_name || "someone") : "someone";
      return `${existing.item.environment} - ${existing.item.service} is currently in use by ${ownerName}.`;
    }
  }

  await client.apps.datastore.put({
    datastore: "environments",
    item: {
      id,
      environment: env,
      service: svc,
      owner_id: userId,
      claimed_at: Math.floor(Date.now() / 1000),
    },
  });

  await refreshCanvas(client);
  return `You now have ${env} - ${svc}.`;
}

export default SlackFunction(TakeEnvFunction, async ({ inputs, client }) => {
  const message = await takeEnvironment(client, inputs.environment, inputs.service, inputs.user_id);
  return { outputs: { message } };
});
