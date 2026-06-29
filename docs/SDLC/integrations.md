# Integrations And MCP Configuration

External integrations are declared in:

```text
tools/ai-sdlc/config/integrations.yaml
```

The default configuration includes disabled examples for Jira, GitHub, and
Linear through MCP. The scripts intentionally run offline: they check whether
an integration is enabled, which environment variables are present, and whether
the configured MCP metadata is plausible. They do not call the external service.

## Jira Through MCP

To enable Jira in a target project:

1. Install or configure a Jira MCP server in the AI client you use.
2. Set `jira.enabled: true` in `integrations.yaml`.
3. Set the expected MCP server name in `jira.mcp_server`.
4. Provide the required environment variables:

```text
JIRA_SITE_URL
JIRA_PROJECT_KEY
JIRA_EMAIL
JIRA_API_TOKEN
```

The readiness report is written to:

```text
.sdlc/local-pipeline/sdlc-integrations-report.json
```

Do not commit secrets. The report lists only variable names and status, never
secret values.

## MCP Client Differences

Codex, Claude, Copilot, and other clients can use different MCP configuration
schemas. Treat `tools/ai-sdlc/config/mcp_servers.example.yaml` as a portable
checklist, not as a file that every client can consume directly.
