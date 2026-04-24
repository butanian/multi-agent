import { DefineDatastore, Schema } from "deno-slack-sdk/mod.ts";

export const EnvironmentsDatastore = DefineDatastore({
  name: "environments",
  primary_key: "id",
  attributes: {
    id: { type: Schema.types.string },
    environment: { type: Schema.types.string },
    service: { type: Schema.types.string },
    owner_id: { type: Schema.types.string },
    claimed_at: { type: Schema.types.number },
  },
});
