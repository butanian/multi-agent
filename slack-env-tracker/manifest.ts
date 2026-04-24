import { Manifest } from "deno-slack-sdk/mod.ts";
import { EnvironmentsDatastore } from "./datastores/environments.ts";
import { ConfigDatastore } from "./datastores/config.ts";

export default Manifest({
  name: "env-tracker",
  description: "Track environment and service ownership across teams",
  icon: "assets/icon.png",
  workflows: [],
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
