# bootstrap/scripts — utility scripts

Scripts in this directory are installed by `universal-setup.sh` into
`~/.claude/scripts/` and used by bootstrap and pipeline workflows.
Each script documents its interface in inline comments at the top.

---

## notify.sh — push notifications

Sends a push notification with a given severity. Planned for use by `sprint.sh`
(sprint orchestrator, ADR-0030; not yet implemented — see #44 Phase-0 conditions)
and any other bootstrap script that needs to alert the operator without blocking
the pipeline.

### Interface

```bash
notify.sh <severity> <title> <url>
```

| Argument   | Values                     | Description                             |
|------------|----------------------------|-----------------------------------------|
| `severity` | `info`, `warn`, `critical` | Determines sound and ntfy.sh priority   |
| `title`    | Short string               | Human-readable message                  |
| `url`      | URL string                 | Context link — issue, PR, or dashboard  |

### Transports

**1. macOS osascript** — always attempted on Darwin if `osascript` is in `PATH`:

| Severity   | Sound   | Notes                              |
|------------|---------|------------------------------------|
| `info`     | silent  |                                    |
| `warn`     | Ping    |                                    |
| `critical` | Sosumi  | Loud; operator expected to respond |

URL appears as text in the notification body. Clicking the notification does not
open the URL — this is an `osascript` limitation. Use ntfy.sh for clickable
notifications on your phone.

Requires Terminal.app to have **Notifications** permission:
`System Settings → Notifications → Terminal → Allow Notifications`.

**2. ntfy.sh** — attempted when `NTFY_TOPIC` env var is set and curl is available:

| Severity   | ntfy priority |
|------------|---------------|
| `info`     | default       |
| `warn`     | high          |
| `critical` | urgent        |

The notification on your phone is clickable and opens `url`. Subscribe to your
topic in the ntfy.sh mobile app before first use.

### Graceful degradation

Transport failures never block the pipeline — `notify.sh` always exits 0 unless
passed bad arguments.

| Condition                                   | Behaviour                                     |
|---------------------------------------------|-----------------------------------------------|
| `NTFY_TOPIC` unset                          | ntfy.sh silently skipped                      |
| `NTFY_TOPIC` contains invalid characters    | Warning to stderr, ntfy skipped, exit 0       |
| curl delivery fails (network / HTTP error)  | Warning to stderr, exit 0                     |
| Neither transport available (headless CI)   | Warning to stderr, exit 0                     |

**Known limitations:** Notification history is not logged (out of scope for this
script — see issue #223). If both transports are unavailable, the escalation is
silently suppressed with only a stderr warning; no automatic retry or fallback to
GitHub issue creation is performed.

### Exit codes

| Code | Meaning                                                    |
|------|------------------------------------------------------------|
| `0`  | Notification sent or gracefully suppressed                 |
| `1`  | Bad arguments (wrong count or unknown severity)            |

### Environment variables

| Variable     | Required | Description                                              |
|--------------|----------|----------------------------------------------------------|
| `NTFY_TOPIC` | No       | ntfy.sh topic (`[A-Za-z0-9_-]+`). Subscribe to it first. If unset or invalid, ntfy.sh transport is skipped silently. |

### Manual smoke test

**Prerequisites:**

1. Install the script: `./bootstrap/universal-setup.sh --install` (from this repo root)
2. Grant Terminal.app notification permission: `System Settings → Notifications → Terminal → Allow Notifications`
3. For ntfy.sh tests: install the ntfy.sh mobile app and subscribe to your topic

```bash
# Local notifications (macOS)
bash ~/.claude/scripts/notify.sh info     "smoke info"     "https://github.com"
bash ~/.claude/scripts/notify.sh warn     "smoke warn"     "https://github.com"
bash ~/.claude/scripts/notify.sh critical "smoke critical" "https://github.com"

# ntfy.sh (replace my-topic with your subscribed topic)
NTFY_TOPIC=my-topic bash ~/.claude/scripts/notify.sh warn "ntfy smoke" "https://github.com"

# No transports — should print WARNING and exit 0
env -i PATH=/dev/null /bin/bash ~/.claude/scripts/notify.sh info "no transport" "https://github.com"
```

Expected results:
- First three: notification appears in Notification Center with the appropriate sound.
- Fourth: notification appears on phone (requires ntfy.sh subscription); clicking opens GitHub.
- Fifth: prints `notify: WARNING: no transport available ...` to stderr, exits 0.
