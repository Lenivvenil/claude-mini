# feat(audit): /audit-pass skill for supervisory re-pass

**Priority:** P1
**Estimate:** S
**Depends on:** —

## Problem statement

Human-authored tickets do not pass the same quality gate as LLM-generated ones. This ticket introduces the audit-pass skill to close that gap.

## Acceptance criteria

- [ ] `bootstrap/scripts/ticket-audit.sh` checks all 8 fields.
- [ ] SKILL.md passes lint-prompts.sh.
- [ ] `docs/skills/audit-pass.md` documents usage.

## Non-goals

Not a blocking gate. Not auto-edit.

## References

Принцип 9.
