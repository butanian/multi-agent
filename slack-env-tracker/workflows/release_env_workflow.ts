import { DefineWorkflow, Schema } from "deno-slack-sdk/mod.ts";
import { ReleaseEnvFunction } from "../functions/release_env.ts";

export const ReleaseEnvWorkflow = DefineWorkflow({
  callback_id: "release_env_workflow",
  title: "Release Environment",
  input_parameters: {
    properties: {
      interactivity: { type: Schema.slack.types.interactivity },
      channel_id: { type: Schema.slack.types.channel_id },
    },
    required: ["interactivity"],
  },
});

const formStep = ReleaseEnvWorkflow.addStep(Schema.slack.functions.OpenForm, {
  title: "Release Environment",
  interactivity: ReleaseEnvWorkflow.inputs.interactivity,
  submit_label: "Release",
  fields: {
    elements: [
      { name: "environment", title: "Environment", type: Schema.types.string, description: "e.g. QA1, Staging" },
      { name: "service", title: "Service", type: Schema.types.string, description: "e.g. Monolith, GoFan-Next" },
    ],
    required: ["environment", "service"],
  },
});

const releaseStep = ReleaseEnvWorkflow.addStep(ReleaseEnvFunction, {
  environment: formStep.outputs.fields.environment,
  service: formStep.outputs.fields.service,
});

ReleaseEnvWorkflow.addStep(Schema.slack.functions.SendMessage, {
  channel_id: ReleaseEnvWorkflow.inputs.channel_id,
  message: releaseStep.outputs.message,
});
