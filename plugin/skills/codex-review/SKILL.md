---
name: codex-review
description: Second-opinion code review by OpenAI Codex CLI over the whole branch against its base. Run before opening or merging a PR.
argument-hint: "[base-branch, default main]"
disable-model-invocation: true
allowed-tools: Bash(codex review:*) Bash(git merge-base:*) Bash(git rev-parse:*) Bash(git diff:*)
---

# /codex-review

Base branch: `$ARGUMENTS` if given, otherwise `main`.

Branch: !`git rev-parse --abbrev-ref HEAD`
Head: !`git rev-parse --short HEAD`

## Your task

1. Record what is reviewed: `git merge-base <base> HEAD` and `git diff --stat <base>...HEAD`. If the stat is empty, stop and say there is nothing to review.
2. Run the review with the Bash tool and a timeout of at least 900000 ms:

   ```bash
   codex review --base <base>
   ```

   The model and reasoning effort come from the user's `~/.codex/config.toml`; do not pass `-c model=...`. A top model at high effort takes minutes, not seconds.
3. Report the result with its status, exactly one of:
   - **FINDINGS** — list every finding with `path:line`, severity and Codex's reasoning;
   - **PASS** — Codex reported no findings;
   - **ERROR** — the command failed or timed out; show the exit code and stderr tail. Never report ERROR as PASS.
4. For each finding give your own verdict: agree (and fix plan), disagree (with evidence), or unsure. Do not dismiss a finding without engaging it.

## Output

In chat: the reviewed range (base SHA..head SHA, files changed), the status line (FINDINGS, PASS or ERROR), each finding with `path:line`, and your verdict on each.

## Hard rules

- Review the whole branch against the base, never only the last commit.
- Do not open issues or comment on PRs from this skill.
