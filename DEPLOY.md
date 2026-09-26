# Deploy claude-mini into a project

**Status: skeleton.** The commands below arrive in phases P2 (#313) and P3 (#314). Until then this
file only fixes the contract. Decision: [ADR-0031](docs/decisions/0031-project-scoped-plugin-two-layer-deploy.md).

This file is written for an agent. A person or a Claude session with no prior context should be able
to follow it from top to bottom when asked "deploy my harness for this project".

## Rules

- The target is the project the request came from (the current working directory), and nothing else.
- Every write goes inside that project. The only writes outside it are the closed list of ADR-0031 §3:
  Claude Code's own plugin registry and cache entries, CodeBurn's own cache directories if enabled,
  and system programs the owner names explicitly.
- Never install a system program without the owner's explicit consent for that exact item.
- Never edit shell profiles, `~/.claude/settings.json`, other projects, or global git config.
- Uncertain? Stop and report. Do not guess.

## Steps

1. **Assess** (read-only): `setup/harness assess --project <dir>` prints the checklist for both layers
   (machine, project) and the minimal delta.
2. **Show the delta** to the owner. Items marked `needs-manual` (logins, GUI steps) are the owner's.
   Items of kind `system-binary` need explicit consent: `--allow-system <id,...>`.
3. **Apply**: `setup/harness apply --project <dir> [--allow-system ...]` applies only the delta, one
   atomic item at a time, and records every change in `<dir>/.claude/claude-mini/manifest.jsonl`.
4. **Verify**: `setup/harness verify --project <dir>`.
5. **Report** the consequences in three sections: Broken / Not done / Works, each item re-checked.
6. **Roll back** if anything is wrong: `setup/harness uninstall --project <dir>` returns the project
   and the allowed outside entries to their prior state.
