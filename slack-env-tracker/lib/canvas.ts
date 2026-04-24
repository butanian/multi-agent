export interface EnvRecord {
  id: string;
  environment: string;
  service: string;
  owner_id: string;
  owner_name: string;
  claimed_at: number;
}

export function buildCanvasMarkdown(records: EnvRecord[]): string {
  if (records.length === 0) {
    return "# Environment Tracker\n\nNo environments tracked yet. Use the **Add Environment** shortcut to get started.";
  }

  const grouped: Record<string, EnvRecord[]> = {};
  for (const record of records) {
    if (!grouped[record.environment]) {
      grouped[record.environment] = [];
    }
    grouped[record.environment].push(record);
  }

  const envNames = Object.keys(grouped).sort();
  const sections: string[] = ["# Environment Tracker\n"];

  for (const envName of envNames) {
    sections.push(`## ${envName}\n`);
    const services = grouped[envName].sort((a, b) =>
      a.service.localeCompare(b.service)
    );
    for (const svc of services) {
      if (svc.owner_id) {
        sections.push(`🔴 ${svc.service} (${svc.owner_name})`);
      } else {
        sections.push(`🟢 ${svc.service}`);
      }
    }
    sections.push("");
  }

  return sections.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function getAllRecordsWithNames(client: any): Promise<EnvRecord[]> {
  const result = await client.apps.datastore.query({ datastore: "environments" });
  if (!result.ok) {
    throw new Error(`Failed to query environments: ${result.error}`);
  }

  const records: EnvRecord[] = [];
  const userCache: Record<string, string> = {};

  for (const item of result.items) {
    let ownerName = "";
    if (item.owner_id) {
      if (!userCache[item.owner_id]) {
        const userResp = await client.users.info({ user: item.owner_id });
        userCache[item.owner_id] = userResp.ok
          ? (userResp.user?.real_name || userResp.user?.name || "Unknown")
          : "Unknown";
      }
      ownerName = userCache[item.owner_id];
    }
    records.push({
      id: item.id,
      environment: item.environment,
      service: item.service,
      owner_id: item.owner_id || "",
      owner_name: ownerName,
      claimed_at: item.claimed_at || 0,
    });
  }

  return records;
}

// deno-lint-ignore no-explicit-any
export async function getOrCreateCanvas(client: any): Promise<string> {
  const configResp = await client.apps.datastore.get({
    datastore: "config",
    id: "main",
  });

  if (configResp.ok && configResp.item?.canvas_id) {
    return configResp.item.canvas_id;
  }

  const createResp = await client.canvases.create({
    title: "Environment Tracker",
    document_content: {
      type: "markdown",
      markdown: "# Environment Tracker\n\nInitializing...",
    },
  });

  if (!createResp.ok) {
    throw new Error(`Failed to create canvas: ${createResp.error}`);
  }

  await client.apps.datastore.put({
    datastore: "config",
    item: { id: "main", canvas_id: createResp.canvas_id, channel_id: "" },
  });

  return createResp.canvas_id;
}

// deno-lint-ignore no-explicit-any
export async function refreshCanvas(client: any): Promise<void> {
  const canvasId = await getOrCreateCanvas(client);
  const records = await getAllRecordsWithNames(client);
  const markdown = buildCanvasMarkdown(records);

  await client.canvases.edit({
    canvas_id: canvasId,
    changes: [
      {
        operation: "replace",
        document_content: {
          type: "markdown",
          markdown,
        },
      },
    ],
  });
}
