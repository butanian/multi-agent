import { Manifest } from "deno-slack-sdk/mod.ts";

export default Manifest({
  name: "env-tracker",
  description: "Track environment and service ownership across teams",
  icon: "assets/icon.png",
  workflows: [],
  datastores: [],
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
