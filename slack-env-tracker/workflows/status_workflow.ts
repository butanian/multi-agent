import { DefineWorkflow, Schema } from "deno-slack-sdk/mod.ts";
import { GetStatusFunction } from "../functions/get_status.ts";

export const StatusWorkflow = DefineWorkflow({
  callback_id: "status_workflow",
  title: "Environment Status",
  input_parameters: {
    properties: {
      interactivity: { type: Schema.slack.types.interactivity },
      channel_id: { type: Schema.slack.types.channel_id },
    },
    required: ["interactivity", "channel_id"],
  },
});

StatusWorkflow.addStep(GetStatusFunction, {
  user_id: StatusWorkflow.inputs.interactivity.interactor.id,
  channel_id: StatusWorkflow.inputs.channel_id,
});
