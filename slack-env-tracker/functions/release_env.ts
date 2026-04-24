import { DefineFunction, Schema, SlackFunction } from "deno-slack-sdk/mod.ts";
import { makeId } from "../lib/env_id.ts";
import { refreshCanvas } from "../lib/canvas.ts";

export const ReleaseEnvFunction = DefineFunction({
  callback_id: "release_env",
  title: "Release Environment",
  source_file: "functions/release_env.ts",
  input_parameters: {
    properties: {
      environment: { type: Schema.types.string },
      service: { type: Schema.types.string },
    },
    required: ["environment", "service"],
  },
  output_parameters: {
    properties: {
      message: { type: Schema.types.string },
    },
    required: ["message"],
  },
});

// deno-lint-ignore no-explicit-any
export async function releaseEnvironment(client: any, environment: string, service: string): Promise<string> {
  const env = environment.trim();
  const svc = service.trim();
  const id = makeId(env, svc);

  const existing = await client.apps.datastore.get({ datastore: "environments", id });

  if (!existing.ok || !existing.item) {
    return `${env} - ${svc} does not exist.`;
  }

  if (!existing.item.owner_id) {
    return `${existing.item.environment} - ${existing.item.service} is not currently in use.`;
  }

  await client.apps.datastore.put({
    datastore: "environments",
    item: {
      id,
      environment: existing.item.environment,
      service: existing.item.service,
      owner_id: "",
      claimed_at: 0,
    },
  });

  await refreshCanvas(client);
  return `${existing.item.environment} - ${existing.item.service} has been released.`;
}

export default SlackFunction(ReleaseEnvFunction, async ({ inputs, client }) => {
  const message = await releaseEnvironment(client, inputs.environment, inputs.service);
  return { outputs: { message } };
});
