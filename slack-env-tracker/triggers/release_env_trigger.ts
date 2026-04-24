import { Trigger } from "deno-slack-api/types.ts";
import { TriggerContextData, TriggerTypes } from "deno-slack-api/mod.ts";
import { ReleaseEnvWorkflow } from "../workflows/release_env_workflow.ts";

const trigger: Trigger<typeof ReleaseEnvWorkflow.definition> = {
  type: TriggerTypes.Shortcut,
  name: "Release Environment",
  description: "Release an environment/service combo",
  workflow: `#/workflows/${ReleaseEnvWorkflow.definition.callback_id}`,
  inputs: {
    interactivity: { value: TriggerContextData.Shortcut.interactivity },
    channel_id: { value: TriggerContextData.Shortcut.channel_id },
  },
};

export default trigger;
