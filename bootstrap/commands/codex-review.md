---
description: Second-voice review via Codex CLI on ChatGPT Plus. Graceful degradation on Plus-OAuth flake.
allowed-tools: Bash(~/.claude/scripts/review-codex.sh), Bash(git diff:*), Bash(git show:*), Bash(gh issue create:*)
model: claude-sonnet-4-6
---

# /codex-review

!`~/.claude/scripts/review-codex.sh`

## Your task

1. Above runs `review-codex.sh`, which:
   - Invokes Codex CLI on current diff (staged → working tree → last commit, fallback chain)
   - On success: returns Codex findings as markdown
   - On failure (exit 4/124): creates GitHub issue `type:deferred-review` and returns `SKIPPED` marker

2. Present Codex findings to operator. If Codex SKIPPED:
   > Codex review skipped due to Plus-OAuth flake. Issue opened as `type:deferred-review`. Merge is NOT blocked — but DoD criterion "two-voice review" is not satisfied; record the gap in PR body.

3. If Codex succeeded, **compare with your own `/review` findings** (if recent):
   - **Agreement** — reinforces confidence.
   - **Codex found something you missed** — acknowledge honestly: "Codex caught X, I missed it. Here's why that matters: ..."
   - **Disagreement** — surface it: "I think Codex is wrong about Y because...". Operator decides.

## Hard rules

- You do NOT silently ignore SKIPPED status. It must be communicated.
- You do NOT dismiss Codex findings without engagement. Every Codex finding gets a response.
- You DO treat Codex finding you missed as valuable signal — that's the entire point of two-voice.
