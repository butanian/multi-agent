import { DefineDatastore, Schema } from "deno-slack-sdk/mod.ts";

export const ConfigDatastore = DefineDatastore({
  name: "config",
  primary_key: "id",
  attributes: {
    id: { type: Schema.types.string },
    canvas_id: { type: Schema.types.string },
    channel_id: { type: Schema.types.string },
  },
});
