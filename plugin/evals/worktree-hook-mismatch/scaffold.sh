#!/usr/bin/env bash
# Builds a repo whose uncommitted diff reproduces the pre-Codex state of PR #305.
set -euo pipefail
git init -q . && git config user.email eval@example.com && git config user.name eval
mkdir -p hooks
cat > install.sh <<'SH'
#!/usr/bin/env bash
# --hook-this-repo: install the governance commit-msg hook into the current repo
GIT_DIR=$(git rev-parse --git-dir) || exit 3
mkdir -p "$GIT_DIR/hooks"
cp hooks/commit-msg "$GIT_DIR/hooks/commit-msg" && echo "installed: $GIT_DIR/hooks/commit-msg"
SH
cat > check.sh <<'SH'
#!/usr/bin/env bash
# Called before every commit: enforce rules only in governed repos
hook="$(git rev-parse --git-dir)/hooks/commit-msg"
grep -q 'commit-msg-governance' "$hook" 2>/dev/null || exit 0   # not governed
echo "governed: enforcing rules"
SH
printf '#!/bin/sh\n# commit-msg-governance\nexit 0\n' > hooks/commit-msg
git add -A && git commit -q -m "chore: initial"
# The change under review: reader switched to the common dir so worktrees resolve
# to the main .git; the installer was left on --git-dir.
sed -i.bak 's/hook="$(git rev-parse --git-dir)/hook="$(git rev-parse --git-common-dir)/' check.sh && rm check.sh.bak
sed -i.bak 's/^# Called before every commit.*/# Called before every commit: enforce rules only in governed repos.\n# --git-common-dir: in a linked worktree this is the main .git, where git runs hooks./' check.sh && rm check.sh.bak
