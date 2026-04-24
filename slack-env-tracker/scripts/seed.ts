// Run via: slack deno run scripts/seed.ts
// Or manually after deploying the app, use `slack datastore put` CLI commands.
//
// This script outputs the slack CLI commands to seed the datastore.
// Copy and run them after deploying the app.

const environments = ["QA1", "Staging"];
const services = [
  "Monolith",
  "GoFan-Next",
  "HQ",
  "Order-Service",
  "AuthService",
  "User Service",
  "GF Web",
];

for (const env of environments) {
  for (const svc of services) {
    const id = `${env.toLowerCase()}::${svc.toLowerCase()}`;
    const item = { id, environment: env, service: svc, owner_id: "", claimed_at: 0 };
    const payload = JSON.stringify({ datastore: "environments", item });
    console.log(`slack datastore put '${payload}'`);
  }
}

console.log(`\n# Run each command above to seed the environments datastore.`);
console.log(`# Total: ${environments.length * services.length} records.`);
