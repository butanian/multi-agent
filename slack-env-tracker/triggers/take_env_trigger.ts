import { Trigger } from "deno-slack-api/types.ts";
import { TriggerContextData, TriggerTypes } from "deno-slack-api/mod.ts";
import { TakeEnvWorkflow } from "../workflows/take_env_workflow.ts";

const trigger: Trigger<typeof TakeEnvWorkflow.definition> = {
  type: TriggerTypes.Shortcut,
  name: "Take Environment",
  description: "Claim an environment/service combo",
  workflow: `#/workflows/${TakeEnvWorkflow.definition.callback_id}`,
  inputs: {
    interactivity: { value: TriggerContextData.Shortcut.interactivity },
    channel_id: { value: TriggerContextData.Shortcut.channel_id },
  },
};

export default trigger;
