---
name: feature
description: Take one issue from plan to an open pull request, then hand off. Use for "/feature N", "сделай задачу N", "take issue N". Calling it authorizes the whole cycle; it stops only for an owner decision or a blocking finding.
argument-hint: "[issue-number]"
disable-model-invocation: true
---

# /feature

Issue: !`gh issue view $ARGUMENTS --json number,title,body,labels 2>/dev/null || echo "no issue given or gh unavailable — ask the owner what to build"`

Base branch: run `"${CLAUDE_PLUGIN_ROOT}/bin/config" get git.base_branch`. If it exits non-zero, stop and show its message.

## Steps

1. **Branch.** If you are on the base branch, create a branch for this issue. Never commit on the base branch.
2. **Plan.** Run the `claude-mini:plan` skill for the issue. If the plan flags the change as architecturally significant, draft the ADR (`claude-mini:solutions-architect` or `claude-mini:adr-author`) and stop for the owner: the decision is theirs.
3. **Implement.** Follow the plan. Run the project's tests after each meaningful change. If the plan proves wrong, update `plan.md` before going on. Independent parts may go to subagents in isolated worktrees.
4. **Verify.** Run the project's own test, lint and type commands, as `AGENTS.md`, the build files or CI define them. All must pass. A check that cannot run is reported with the reason, never as passed.
5. **Check against the issue.** Map each acceptance criterion to evidence in the diff: covered, partial or missing, with `path:line`. List changes that no criterion asks for.
6. **Review.** Pick critics by what the change touches and run them in parallel:
   - `claude-mini:security-reviewer` for auth, secrets, input handling, dependencies;
   - `claude-mini:reliability-reviewer` for scripts, CI, hooks, jobs, migrations, shared state;
   - `claude-mini:docs-reviewer` for README, runbooks, guides;
   - `claude-mini:domain-reviewer` for domain docs or declared invariants;
   - `claude-mini:adr-reviewer` for ADRs;
   - `claude-mini:adversarial-critic` for any non-trivial code change.

   Then run `claude-mini:codex-review` if Codex is enabled in config and installed. Fix what you agree with. Give evidence for what you reject.
7. **Commit and pull request.** Commit in Conventional Commits form, the plugin hook checks the subject. Open the PR with `Closes #<issue>`, the acceptance table, the checks run with their results, and the review outcome. The PR title is also Conventional Commits: a squash merge makes it the commit subject.
8. **Hand off.** Run `claude-mini:handoff`.

## Output

The PR link, the acceptance table summary (covered / partial / missing), each check with its result, and what is left for the owner.

## Hard rules

- The owner merges. Do NOT merge, close issues or push to the base branch.
- Stop and ask the owner only for a decision that is theirs: an ADR, a missing acceptance criterion, a blocking finding you cannot resolve, or scope beyond the issue.
- Every "passed" names the command that ran.
