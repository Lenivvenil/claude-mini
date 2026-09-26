# Deploy claude-mini into a project

For an agent asked "deploy my harness for this project". Decision: [ADR-0031](docs/decisions/0031-project-scoped-plugin-two-layer-deploy.md).

`<harness>` is the path of this repository. The project is the directory the request came from.

1. `<harness>/setup/harness assess --project .` — read-only. Prints Broken / Not done / Works for the
   machine and the project.
2. If a program is missing and the report offers `--allow-system <id>`, ask the owner. Install only
   the items the owner names. Logins and other `needs-manual` items are the owner's to do.
3. `<harness>/setup/harness apply --project . [--allow-system <id,...>]` — does only what is missing.
   The project layer (git exclude lines, the plugin enabled for this project only) needs no consent:
   it writes inside the project, plus Claude Code's own plugin registry entry for this project.
4. `<harness>/setup/harness verify --project .` — exit 0 means ready.
5. Show the owner the report from step 3 as is. Start a new Claude session in the project to load
   the plugin.

Undo: `<harness>/setup/harness uninstall --project .` returns the project files to their bytes before
setup, unless someone edited them since (then they are left and listed).

Never: edit `~/.claude/settings.json`, shell profiles, global git config or other projects; enable
the plugin at user scope; install a system program without the owner naming it; push.

Exit codes: 0 ok · 1 invalid config or state · 2 usage · 3 a program needs consent · 4 a step failed
· 5 verify: not ready.
