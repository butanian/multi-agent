import { Trigger } from "deno-slack-api/types.ts";
import { TriggerContextData, TriggerTypes } from "deno-slack-api/mod.ts";
import { StatusWorkflow } from "../workflows/status_workflow.ts";

const trigger: Trigger<typeof StatusWorkflow.definition> = {
  type: TriggerTypes.Shortcut,
  name: "Environment Status",
  description: "View current environment ownership",
  workflow: `#/workflows/${StatusWorkflow.definition.callback_id}`,
  inputs: {
    interactivity: { value: TriggerContextData.Shortcut.interactivity },
    channel_id: { value: TriggerContextData.Shortcut.channel_id },
  },
};

export default trigger;
