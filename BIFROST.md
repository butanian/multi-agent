# Bifrost gateway

Any pane, Claude or Codex, can run through PlayOn's Bifrost gateway (`https://bifrost.playonshared.co`) instead of directly. It is chosen per pane in the provider prompt (recorded as `GATEWAY_n=direct|bifrost` in `swarms/<N>/launch.env`; a missing value means `direct`).

One-time setup:

```bash
npx -y @maximhq/bifrost-cli
~/.bifrost/bin/bifrost context add playon --base-url https://bifrost.playonshared.co --use
~/.bifrost/bin/bifrost auth login     # Google SSO; no key is stored
```

For Codex panes also create `~/.codex/bifrost.config.toml` (provider `bifrost`, `base_url = "https://bifrost.playonshared.co/openai/v1"`, an `[model_providers.bifrost.auth]` command that runs `bifrost --context playon auth print-token`). Codex model ids need the `openai/` prefix. Do not add the `PlayOn_mcp` connector to this profile: swarm Codex panes run with `-a never` and could write to Slack and Jira unprompted.

Launchers refuse to start a Bifrost pane, and `restart-swarm.sh --hard` refuses before checkpointing, when Bifrost is missing or signed out, `jq` is missing, or the Codex profile does not point at the gateway. Claude Bifrost panes pass one merged `--settings` argument (`tools/bifrost-claude-settings.json` plus pane 1's settings), because a repeated `--settings` replaces the earlier one. Bifrost models are not checked against the Bifrost catalog; Claude models still are checked against the native list.
