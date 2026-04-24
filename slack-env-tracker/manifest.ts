import { Manifest } from "deno-slack-sdk/mod.ts";
import { EnvironmentsDatastore } from "./datastores/environments.ts";
import { ConfigDatastore } from "./datastores/config.ts";
import { TakeEnvWorkflow } from "./workflows/take_env_workflow.ts";
import { ReleaseEnvWorkflow } from "./workflows/release_env_workflow.ts";
import { AddEnvWorkflow } from "./workflows/add_env_workflow.ts";
import { StatusWorkflow } from "./workflows/status_workflow.ts";

export default Manifest({
  name: "env-tracker",
  description: "Track environment and service ownership across teams",
  icon: "assets/icon.png",
  workflows: [TakeEnvWorkflow, ReleaseEnvWorkflow, AddEnvWorkflow, StatusWorkflow],
  datastores: [EnvironmentsDatastore, ConfigDatastore],
  outgoingDomains: [],
  botScopes: [
    "commands",
    "chat:write",
    "chat:write.public",
    "canvases:write",
    "canvases:read",
    "datastore:read",
    "datastore:write",
    "users:read",
  ],
});
