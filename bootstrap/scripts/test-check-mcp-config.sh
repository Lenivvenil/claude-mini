#!/usr/bin/env bash
# test-check-mcp-config.sh — unit tests for check-mcp-config.sh
#
# Tests each exit condition with a minimal fixture .mcp.json in a temp directory.
# No external dependencies beyond bash and jq (same as the linter itself).
#
# Exit codes: 0 = all pass, 1 = one or more failures.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LINTER="$SCRIPT_DIR/check-mcp-config.sh"

pass=0
fail=0
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

_run() {
  local desc="$1"
  local fixture="$2"
  local expect_exit="$3"

  local file="$tmpdir/mcp-test-$$.json"
  printf '%s' "$fixture" > "$file"

  bash "$LINTER" "$file" >/dev/null 2>&1
  local actual_exit=$?

  if [ "$actual_exit" -eq "$expect_exit" ]; then
    echo "PASS: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected exit $expect_exit, got $actual_exit)"
    fail=$((fail + 1))
  fi
}

# --- Fixtures ---

VALID_PINNED='{
  "mcpServers": {
    "serena": {
      "type": "stdio",
      "command": "uvx",
      "args": ["--from", "git+https://github.com/oraios/serena@v1.2.0", "serena", "start-mcp-server"]
    }
  }
}'

VALID_SCOPED_NPM='{
  "mcpServers": {
    "context7": {
      "type": "stdio",
      "command": "npx",
      "args": ["@upstash/context7-mcp@2.2.4"]
    }
  }
}'

VALID_HTTP_ALLOWLISTED='{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": { "Authorization": "Bearer sometoken" }
    }
  }
}'

MISSING_PIN='{
  "mcpServers": {
    "bad-server": {
      "type": "stdio",
      "command": "npx",
      "args": ["some-mcp-server"]
    }
  }
}'

LATEST_TAG='{
  "mcpServers": {
    "bad-server": {
      "type": "stdio",
      "command": "npx",
      "args": ["some-mcp-server@latest"]
    }
  }
}'

STAR_TAG='{
  "mcpServers": {
    "bad-server": {
      "type": "stdio",
      "command": "npx",
      "args": ["some-mcp-server@*"]
    }
  }
}'

SCOPED_NO_VERSION='{
  "mcpServers": {
    "bad-server": {
      "type": "stdio",
      "command": "npx",
      "args": ["@upstash/context7-mcp"]
    }
  }
}'

UNALLOWED_HTTP='{
  "mcpServers": {
    "bad-server": {
      "type": "http",
      "url": "https://evil.example.com/mcp/",
      "headers": { "Authorization": "Bearer sometoken" }
    }
  }
}'

LOCAL_HTTP_NO_AUTH='{
  "mcpServers": {
    "bad-server": {
      "type": "http",
      "url": "http://localhost:8080/mcp/"
    }
  }
}'

LOCAL_HTTP_WITH_AUTH='{
  "mcpServers": {
    "ok-local": {
      "type": "http",
      "url": "http://localhost:8080/mcp/",
      "headers": { "Authorization": "Bearer somelocaltoken" }
    }
  }
}'

EMPTY='{
  "mcpServers": {}
}'

# Multi-package bypass: one pinned package + one unpinned → must fail
# (covers npx --package=a@1.0.0 --package=b@latest pattern)
MULTI_PKG_BYPASS='{
  "mcpServers": {
    "bad-server": {
      "type": "stdio",
      "command": "npx",
      "args": ["--package=@upstash/context7-mcp@2.2.4", "--package=evil-helper@latest", "context7-mcp"]
    }
  }
}'

# uvx --with bypass: pinned base + unpinned extra dep
UVX_WITH_BYPASS='{
  "mcpServers": {
    "bad-server": {
      "type": "stdio",
      "command": "uvx",
      "args": ["--from", "git+https://github.com/oraios/serena@v1.2.0", "--with", "evil@latest", "serena"]
    }
  }
}'

# 0.0.0.0 local bind without auth — must fail (ADR-0028 policy 3)
LOCAL_HTTP_0000_NO_AUTH='{
  "mcpServers": {
    "bad-server": {
      "type": "http",
      "url": "http://0.0.0.0:8080/mcp/"
    }
  }
}'

# Missing mcpServers key entirely — must exit 2 (setup error)
MISSING_KEY='{"foo": "bar"}'

# mcpServers is null — must exit 2
NULL_SERVERS='{"mcpServers": null}'

# --- Tests ---

_run "valid pinned git-tag (serena-style)"       "$VALID_PINNED"         0
_run "valid scoped npm package with version"     "$VALID_SCOPED_NPM"     0
_run "valid HTTP allowlisted URL"                "$VALID_HTTP_ALLOWLISTED" 0
_run "empty mcpServers — passes trivially"       "$EMPTY"                0
_run "missing pin — no @ in args"                "$MISSING_PIN"          1
_run "scoped npm package without version"        "$SCOPED_NO_VERSION"    1
_run "latest tag rejected"                       "$LATEST_TAG"           1
_run "star tag rejected"                         "$STAR_TAG"             1
_run "HTTP URL not in allowlist"                 "$UNALLOWED_HTTP"       1
_run "local HTTP without auth — rejected"        "$LOCAL_HTTP_NO_AUTH"   1
_run "local HTTP with auth — allowlist check applies" "$LOCAL_HTTP_WITH_AUTH" 1
_run "multi-pkg bypass: pinned+unpinned — rejected" "$MULTI_PKG_BYPASS"  1
_run "uvx --with bypass: pinned+unpinned — rejected" "$UVX_WITH_BYPASS"  1
_run "0.0.0.0 local bind without auth — rejected" "$LOCAL_HTTP_0000_NO_AUTH" 1
_run "missing mcpServers key — setup error (exit 2)" "$MISSING_KEY"      2
_run "null mcpServers — setup error (exit 2)"    "$NULL_SERVERS"         2

echo ""
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
