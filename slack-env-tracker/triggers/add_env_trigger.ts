import { Trigger } from "deno-slack-api/types.ts";
import { TriggerContextData, TriggerTypes } from "deno-slack-api/mod.ts";
import { AddEnvWorkflow } from "../workflows/add_env_workflow.ts";

const trigger: Trigger<typeof AddEnvWorkflow.definition> = {
  type: TriggerTypes.Shortcut,
  name: "Add Environment",
  description: "Add a new environment/service combo",
  workflow: `#/workflows/${AddEnvWorkflow.definition.callback_id}`,
  inputs: {
    interactivity: { value: TriggerContextData.Shortcut.interactivity },
    channel_id: { value: TriggerContextData.Shortcut.channel_id },
  },
};

export default trigger;
