import { DefineWorkflow, Schema } from "deno-slack-sdk/mod.ts";
import { TakeEnvFunction } from "../functions/take_env.ts";

export const TakeEnvWorkflow = DefineWorkflow({
  callback_id: "take_env_workflow",
  title: "Take Environment",
  input_parameters: {
    properties: {
      interactivity: { type: Schema.slack.types.interactivity },
      channel_id: { type: Schema.slack.types.channel_id },
    },
    required: ["interactivity"],
  },
});

const formStep = TakeEnvWorkflow.addStep(Schema.slack.functions.OpenForm, {
  title: "Take Environment",
  interactivity: TakeEnvWorkflow.inputs.interactivity,
  submit_label: "Take",
  fields: {
    elements: [
      { name: "environment", title: "Environment", type: Schema.types.string, description: "e.g. QA1, Staging" },
      { name: "service", title: "Service", type: Schema.types.string, description: "e.g. Monolith, GoFan-Next" },
    ],
    required: ["environment", "service"],
  },
});

const takeStep = TakeEnvWorkflow.addStep(TakeEnvFunction, {
  environment: formStep.outputs.fields.environment,
  service: formStep.outputs.fields.service,
  user_id: TakeEnvWorkflow.inputs.interactivity.interactor.id,
});

TakeEnvWorkflow.addStep(Schema.slack.functions.SendMessage, {
  channel_id: TakeEnvWorkflow.inputs.channel_id,
  message: takeStep.outputs.message,
});
