import { DefineWorkflow, Schema } from "deno-slack-sdk/mod.ts";
import { AddEnvFunction } from "../functions/add_env.ts";

export const AddEnvWorkflow = DefineWorkflow({
  callback_id: "add_env_workflow",
  title: "Add Environment",
  input_parameters: {
    properties: {
      interactivity: { type: Schema.slack.types.interactivity },
      channel_id: { type: Schema.slack.types.channel_id },
    },
    required: ["interactivity"],
  },
});

const formStep = AddEnvWorkflow.addStep(Schema.slack.functions.OpenForm, {
  title: "Add Environment",
  interactivity: AddEnvWorkflow.inputs.interactivity,
  submit_label: "Add",
  fields: {
    elements: [
      { name: "environment", title: "Environment", type: Schema.types.string, description: "e.g. QA1, Staging" },
      { name: "service", title: "Service", type: Schema.types.string, description: "e.g. Monolith, GoFan-Next" },
    ],
    required: ["environment", "service"],
  },
});

const addStep = AddEnvWorkflow.addStep(AddEnvFunction, {
  environment: formStep.outputs.fields.environment,
  service: formStep.outputs.fields.service,
});

AddEnvWorkflow.addStep(Schema.slack.functions.SendMessage, {
  channel_id: AddEnvWorkflow.inputs.channel_id,
  message: addStep.outputs.message,
});
