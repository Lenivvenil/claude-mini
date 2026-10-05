# Deploy MACH into a project

For an agent asked "deploy my harness for this project". Decision: [ADR-0031](docs/decisions/0031-project-scoped-plugin-two-layer-deploy.md).

`<harness>` is the path of this repository. The project is the directory the request came from.
`--project` resolves to the top level of the git repository it lies in: a subdirectory of a
repository means the whole repository. Every report starts with the project it acted on.

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
setup, unless someone edited them since (then they are left and listed). A `.claude/` directory setup
created goes too, if nothing else is in it.

Never: edit `~/.claude/settings.json`, shell profiles, global git config or other projects; enable
the plugin at user scope; install a system program without the owner naming it; push.

Exit codes: 0 ok · 1 invalid config or state · 2 usage · 3 a program needs consent · 4 a step failed
· 5 verify: not ready.

## Moving from claude-mini

Until October 2026 the harness was called claude-mini ([ADR-0034](docs/decisions/0034-rename-project-to-mach.md)).
A project set up under that name is moved by `apply`, nothing is edited by hand.

1. Rename the local clone and point it at the new address:
   `mv ~/projects/claude-mini ~/projects/mach && git -C ~/projects/mach remote set-url origin https://github.com/Lenivvenil/mach.git`
2. In every project set up before the rename: `<harness>/setup/harness apply --project <project>`.
   It renames `.claude/claude-mini.json` to `.claude/mach.json`, undoes the old setup (plugin
   `claude-mini@claude-mini`, its exclude lines), keeps setup's log under `.claude/mach/` and sets up
   `mach@mach`. `apply --dry-run` shows the move first.
3. When the last project has moved, the machine-wide marketplace `claude-mini` is gone as well; if the
   report says it was kept, remove it with `claude plugin marketplace remove claude-mini`.

Until step 2 the project's plugin id `claude-mini@claude-mini` no longer resolves, so the harness,
its commit check included, is off in that project. Where `mach@mach` is enabled by other means but
only `.claude/claude-mini.json` exists, the commit check refuses every commit and names this command.
Claude Code keeps its memory per project path: after step 1, move
`~/.claude/projects/-Users-<you>-projects-claude-mini/` to the name of the new path.
