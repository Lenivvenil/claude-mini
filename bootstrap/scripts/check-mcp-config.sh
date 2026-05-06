#!/usr/bin/env bash
# check-mcp-config.sh — lint .mcp.json against ADR-0028 transport security policy
#
# Policies (ADR-0028 docs/decisions/0028-mcp-transport-security.md):
#   1. Version pinning: every stdio server must have an explicit @<version> or @<tag>
#      in its command args. "latest" and "*" are rejected.
#   2. Transport allowlist: every HTTP server URL must be in ALLOWED_HTTP_URLS.
#   3. No unauthenticated local HTTP: no server may use http://localhost or
#      http://127.0.0.1 without an Authorization header entry.
#
# Usage: bash bootstrap/scripts/check-mcp-config.sh [path/to/.mcp.json]
#   Default: .mcp.json in the current directory (repo root).
#
# Exit codes:
#   0 — all policies satisfied
#   1 — one or more policy violations found
#   2 — setup error (jq not installed, file missing/unparseable)

set -uo pipefail

# --- ALLOWLIST (source of truth — docs/runbooks/mcp-quarterly-review.md mirrors this) ---
ALLOWED_HTTP_URLS=(
  "https://api.githubcopilot.com/mcp/"
)

# --- Setup ---

MCP_FILE="${1:-.mcp.json}"
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
NC=$'\033[0m'

fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "${RED}ERROR${NC}: jq is required but not installed." >&2
  exit 2
fi

if [ ! -f "$MCP_FILE" ]; then
  echo "${RED}ERROR${NC}: $MCP_FILE not found." >&2
  exit 2
fi

if ! jq empty "$MCP_FILE" 2>/dev/null; then
  echo "${RED}ERROR${NC}: $MCP_FILE is not valid JSON." >&2
  exit 2
fi

# --- Structural validation: mcpServers must be a present, non-null object ---

mcp_type=$(jq -r 'if has("mcpServers") then (.mcpServers | type) else "missing" end' "$MCP_FILE")
case "$mcp_type" in
  object)  ;;  # valid
  missing) echo "${RED}ERROR${NC}: $MCP_FILE: 'mcpServers' key is absent — not a valid MCP config." >&2; exit 2 ;;
  null)    echo "${RED}ERROR${NC}: $MCP_FILE: 'mcpServers' is null — not a valid MCP config." >&2; exit 2 ;;
  *)       echo "${RED}ERROR${NC}: $MCP_FILE: 'mcpServers' is of type '$mcp_type', expected object." >&2; exit 2 ;;
esac

# --- Policy 1 & 2 & 3: iterate over servers ---

server_count=$(jq '.mcpServers | length' "$MCP_FILE")
if [ "$server_count" -eq 0 ]; then
  echo "No MCP servers configured (empty mcpServers object) — nothing to check."
  exit 0
fi

while IFS= read -r name; do
  transport=$(jq -r --arg n "$name" '.mcpServers[$n].type // "stdio"' "$MCP_FILE")

  if [ "$transport" = "stdio" ]; then
    # Collect all args into a single space-joined string for version scanning
    args_str=$(jq -r --arg n "$name" \
      '[ .mcpServers[$n].command // "",
         (.mcpServers[$n].args // [])[] ] | join(" ")' \
      "$MCP_FILE")

    # Version-pin check: two-pass approach.
    #
    # Pass 1 — FAIL if any unpinned token exists (covers multi-package patterns
    #   like "npx --package=a@1.0 --package=b@latest" where rightmost-match would
    #   find a@1.0 and silently pass b@latest). Scans ALL @-tokens, not just rightmost.
    #   Scoped package names like @scope/pkg are excluded (contain a slash; e.g.
    #   @upstash/context7-mcp has a slash before the @<version> separator).
    #   Note: version-shaped tokens in non-package arg positions (e.g. git URL fragments,
    #   header values) could produce false negatives — not validated; document known scope.
    #
    # Pass 2 — FAIL if no semver/vtag pin found at all.
    #
    # Accepted forms: @1.2.3, @v1.2.0, @1.2.3-beta.1 (npm semver with pre-release)
    # Rejected forms: @latest, @*, @abc1234 (commit SHAs — use git tags instead)

    unpinned=$(echo "$args_str" | grep -oE '@(latest|\*)' | head -1)
    if [ -n "$unpinned" ]; then
      echo "${RED}FAIL${NC} [version-pin] '$name': unpinned token '$unpinned' found in args"
      echo "       All packages in command+args must be pinned. 'latest' and '*' are rejected."
      echo "       Fix: replace '$unpinned' with explicit semver, e.g. @1.2.3 or @v1.2.0"
      echo "       See: docs/runbooks/mcp-quarterly-review.md, ADR-0028 policy 1"
      fail=1
    else
      version_pin=$(echo "$args_str" | grep -oE '@v?[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9.-]+)?' | tail -1)
      if [ -z "$version_pin" ]; then
        echo "${RED}FAIL${NC} [version-pin] '$name': no @<semver> or @v<tag> found in args: $args_str"
        echo "       Fix: add version specifier, e.g. 'npx pkg@1.2.3' or 'uvx --from git+...@v1.2.0'"
        echo "       Note: commit SHAs are not accepted — use a git tag. See ADR-0028 policy 1"
        echo "       See: docs/runbooks/mcp-quarterly-review.md"
        fail=1
      else
        echo "${GREEN}OK${NC}   [version-pin] '$name': $version_pin"
      fi
    fi

  elif [ "$transport" = "http" ] || [ "$transport" = "sse" ]; then
    url=$(jq -r --arg n "$name" '.mcpServers[$n].url // ""' "$MCP_FILE")

    # Policy 3: reject unauthenticated local HTTP.
    # Covers localhost, 127.0.0.1, and 0.0.0.0 (all documented in ADR-0028 §policy 3).
    # IPv6 loopback [::1] is also covered (spirit of policy, even if not enumerated in ADR).
    if echo "$url" | grep -qiE '^https?://(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(:[0-9]+)?/'; then
      # Only Authorization header counts (ADR-0028 §policy 3 names this explicitly).
      # env.MCP_AUTH is not an ADR-documented auth mechanism — excluded intentionally.
      auth=$(jq -r --arg n "$name" \
        '.mcpServers[$n].headers.Authorization // ""' \
        "$MCP_FILE")
      if [ -z "$auth" ]; then
        echo "${RED}FAIL${NC} [local-http-auth] '$name': local HTTP endpoint '$url' has no Authorization header — unauthenticated local HTTP is forbidden (ADR-0028 policy 3)"
        fail=1
        continue
      fi
    fi

    # Policy 2: URL must be in allowlist
    allowed=0
    for allowed_url in "${ALLOWED_HTTP_URLS[@]}"; do
      if [ "$url" = "$allowed_url" ]; then
        allowed=1
        break
      fi
    done

    if [ "$allowed" -eq 0 ]; then
      echo "${RED}FAIL${NC} [http-allowlist] '$name': '$url' is not in the approved HTTP allowlist"
      echo "       Allowlist (source of truth: ALLOWED_HTTP_URLS in bootstrap/scripts/check-mcp-config.sh):"
      for u in "${ALLOWED_HTTP_URLS[@]}"; do echo "         $u"; done
      echo "       To add a new endpoint: amend ADR-0028 and update ALLOWED_HTTP_URLS in this script"
      echo "       See: docs/decisions/0028-mcp-transport-security.md, docs/runbooks/mcp-quarterly-review.md"
      fail=1
    else
      echo "${GREEN}OK${NC}   [http-allowlist] '$name': $url"
    fi

  else
    echo "${RED}FAIL${NC} [unknown-transport] '$name': unknown transport type '$transport'"
    fail=1
  fi

done < <(jq -r '.mcpServers | keys[]' "$MCP_FILE")

if [ "$fail" -eq 0 ]; then
  echo "All MCP server policies satisfied."
fi

exit "$fail"
