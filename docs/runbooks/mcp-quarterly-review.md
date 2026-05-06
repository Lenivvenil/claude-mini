# MCP Quarterly Security Review

**Frequency:** Every Q — January, April, July, October.  
**Policy source:** `docs/decisions/0028-mcp-transport-security.md`  
**Allowlist source of truth:** `bootstrap/scripts/check-mcp-config.sh` (constant `ALLOWED_HTTP_URLS`). This runbook mirrors it for readability — at any discrepancy, the script is authoritative.

---

## Current allowlist

| Server | Transport | Pinned version | URL / command |
|---|---|---|---|
| `serena` | stdio | `v1.2.0` | `uvx --from git+https://github.com/oraios/serena@v1.2.0` |
| `context7` | stdio | `2.2.4` | `npx @upstash/context7-mcp@2.2.4` |
| `github` | HTTP (allowlisted) | N/A | `https://api.githubcopilot.com/mcp/` |

**Note on `context7`:** the stdio transport connects Claude Code to a local npm process. That process makes HTTPS calls to the Upstash backend (`mcp.context7.com`). stdio closes the Claude↔local-process unauthenticated-HTTP vector; it does NOT isolate from Upstash. This is by design — see ADR-0028 §"Принципиальная важная точность".

---

## Review checklist (run each Q)

### Step 1 — Advisory database check

For each pinned package, check for known CVEs:

```bash
# Serena — GitHub Advisory Database
open "https://github.com/advisories?query=oraios%2Fserena"
# or: gh api graphql -f query='{ securityAdvisories(first:5) { nodes { summary } } }'

# Context7 npm package
open "https://github.com/advisories?query=upstash%2Fcontext7-mcp"
# or: install in a temp dir and audit:
#   mkdir -p /tmp/ctx7-audit && cd /tmp/ctx7-audit && npm install @upstash/context7-mcp@2.2.4 && npm audit

# GitHub Copilot MCP API — check GitHub Security Advisories
open "https://github.com/advisories?query=github+copilot+mcp"
```

### Step 2 — CVE search for transport layer

Search for new CVEs affecting the Anthropic MCP SDK or stdio transport:

```bash
# Search GitHub for new issues/advisories
gh search issues "MCP SDK CVE" --repo modelcontextprotocol/python-sdk --state open | head -10
gh search issues "stdio transport vulnerability" --repo modelcontextprotocol/python-sdk --state open | head -10
```

### Step 3 — Pin staleness check

Verify current pins against latest releases:

```bash
# Serena latest release
curl -s https://api.github.com/repos/oraios/serena/releases/latest \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])"

# Context7 latest npm version
npm view @upstash/context7-mcp version
```

If latest is significantly ahead of pinned: evaluate upgrade cost and CVE exposure. Update `.mcp.json` and re-run `bash bootstrap/scripts/check-mcp-config.sh`.

### Step 4 — Allowlist endpoint status

```bash
# GitHub Copilot MCP API — check availability
curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
  https://api.githubcopilot.com/mcp/
# Expected: 200 or 401 (reachable). 000 = network failure.
```

Check GitHub changelog for any auth mechanism changes at `https://api.githubcopilot.com`.

---

## Plugin-marketplace deduplication

When `.mcp.json` is first applied (or after any version pin update), confirm no plugin-marketplace duplicates remain. Claude Code deduplication only triggers when command/URL matches exactly — a pinned entry differs from an unpinned plugin entry, so both can load simultaneously:

```bash
# Check for duplicate entries per server
claude mcp list | grep -E 'serena|context7|github'
```

If a server appears twice (once from plugin, once from `.mcp.json`):

```bash
# Remove the unpinned plugin-scope copy (keep the .mcp.json project-scope one)
claude mcp remove serena --scope user 2>/dev/null || claude mcp remove serena --scope local
claude mcp remove context7 --scope user 2>/dev/null || claude mcp remove context7 --scope local
```

After removal, restart Claude Code and verify `claude mcp list` shows each server once.

## Output

Record one of the following in the session log after completing all four steps:

- `mcp-review Q<quarter> <year>: no findings` — all clear, no action needed
- `mcp-review Q<quarter> <year>: upgrade pin to <server>@<version>` — open PR with `.mcp.json` update
- `mcp-review Q<quarter> <year>: ADR-trigger — re-evaluate transport policy` — open ADR-0028 amendment

---

## Adding a new external HTTP MCP server

HTTP servers outside `ALLOWED_HTTP_URLS` are rejected by CI. To add one:

1. Open an ADR-0028 amendment in `docs/decisions/0028-mcp-transport-security.md`.
2. Add the URL to `ALLOWED_HTTP_URLS` in `bootstrap/scripts/check-mcp-config.sh`.
3. Update the allowlist table in this runbook.
4. PR must have `Implements docs/decisions/0028-mcp-transport-security.md` in body.

---

## Missed reviews

If the quarterly review is skipped two Q in a row: open a follow-up issue to evaluate mechanical enforcement (cron-generated issue, dashboard alert). Manual discipline is the current mechanism — see ADR-0028 Negative Consequences.
