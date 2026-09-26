#!/usr/bin/env bash
# tests/jev/run.sh — advisory Jev plan check (PLAN P8, #319). A local stub stands in for the API;
# no network, no real key. Exit 0 = all passed.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JEV="$REPO/plugin/bin/jev-check"
BASE="${PORT_RUN_TMP:-$REPO/.port-run/tmp}"
mkdir -p "$BASE"
T=$(mktemp -d "$BASE/jev.XXXXXX")
STUB_PID=""
TRAP_PID=""
trap 'for p in $STUB_PID $TRAP_PID; do { kill "$p"; wait "$p"; } 2>/dev/null; done; rm -rf "$T"' EXIT
FAIL=0
ok() { echo "  ok   $*"; }
fail() { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }
is() {  # is <got> <want> <label>
    if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 — got '$1', expected '$2'"; fi
}
status() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' 2>/dev/null || echo "not-json"; }

# The stub answers by mode file: ok | high | outofrange | sleep | garbage | http401 | redirect |
# disconnect. It records the last
# Authorization header it saw, so the test can check the key went to the server and nowhere else.
cat > "$T/stub.py" <<'PY'
import http.server, json, sys, time, os
d = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        open(os.path.join(d, "auth"), "w").write(self.headers.get("Authorization", ""))
        open(os.path.join(d, "request.json"), "w").write(json.dumps(body))
        mode = open(os.path.join(d, "mode")).read().strip()
        if mode == "redirect":
            self.send_response(302); self.send_header("Location", open(os.path.join(d, "trap_url")).read()); self.end_headers(); return
        if mode == "disconnect":
            self.close_connection = True; self.connection.shutdown(2); return
        if mode == "sleep":
            time.sleep(6)
        if mode == "http401":
            self.send_response(401); self.end_headers(); self.wfile.write(b'{"error":"bad key"}'); return
        if mode == "garbage":
            payload = b"not json"
        else:
            p = {"high": 0.95, "outofrange": 1.7}.get(mode, 0.05)
            payload = json.dumps({"model": "jev-1.13.0", "usage": {"input_tokens": 10, "output_tokens": 0},
                                  "answers": {q: {"type": "noul", "noul": p} for q in body["questions"]}}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(payload)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(d, "port"), "w").write(str(s.server_port))
s.serve_forever()
PY
python3 "$T/stub.py" "$T" & STUB_PID=$!
for _ in $(seq 1 50); do [ -s "$T/port" ] && break; sleep 0.1; done
PORT=$(cat "$T/port")
# A second server stands in for a foreign host a redirect points at; it records any header it gets.
mkdir -p "$T/trap"
python3 -c '
import http.server, os, sys
d = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self): self._r()
    def do_GET(self): self._r()
    def _r(self):
        open(os.path.join(d, "auth"), "w").write(self.headers.get("Authorization", "none"))
        self.send_response(200); self.end_headers()
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(d, "port"), "w").write(str(s.server_port))
s.serve_forever()' "$T/trap" & TRAP_PID=$!
for _ in $(seq 1 50); do [ -s "$T/trap/port" ] && break; sleep 0.1; done
printf 'http://localhost:%s/steal' "$(cat "$T/trap/port")" > "$T/trap_url"

proj() {  # proj <name> <jev-override-json>
    mkdir -p "$T/$1/.claude" && git -C "$T/$1" init -q
    printf '{"jev": %s}\n' "$2" > "$T/$1/.claude/claude-mini.json"
    echo "$T/$1"
}
ON="{\"enabled\": true, \"endpoint\": \"http://127.0.0.1:$PORT/v1/systemone\", \"key_env\": \"JEV_TEST_KEY\"}"
printf '# Plan\n\nUse Postgres because ADR-0003 says so.\n' > "$T/plan.md"
KEY="test-key-$$-secret"

echo "jev-check"
p=$(proj off '{"enabled": false}')
is "$(status "$("$JEV" "$T/plan.md" --project "$p")")" disabled "disabled in config → disabled"

p=$(proj on "$ON")
is "$(status "$(env -u JEV_TEST_KEY "$JEV" "$T/plan.md" --project "$p")")" unavailable "no key → unavailable"

echo ok > "$T/mode"
o=$(JEV_TEST_KEY=$KEY "$JEV" "$T/plan.md" --project "$p" 2>"$T/err")
is "$(status "$o")" ok "valid answers → ok"
is "$(printf '%s' "$o" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["findings"]))')" 0 "low probabilities → no findings"
is "$(cat "$T/auth")" "Bearer $KEY" "key sent as Bearer header"
is "$(python3 -c 'import json,sys; b=json.load(open(sys.argv[1])); print(b["model"], sorted(b["questions"]) == sorted(json.load(open(sys.argv[2]))), "plan" in b["state"])' "$T/request.json" "$REPO/plugin/skills/plan/jev-questions.v1.json")" "jev-1.13.0 True True" "request carries model, all questions and the plan"
if printf '%s' "$o" | grep -qF "$KEY" || grep -qF "$KEY" "$T/err"; then fail "key leaked to output"; else ok "key not in output"; fi

echo high > "$T/mode"
o=$(JEV_TEST_KEY=$KEY "$JEV" "$T/plan.md" --project "$p")
is "$(printf '%s' "$o" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["findings"]))')" 3 "high probabilities → three advisory findings"

echo garbage > "$T/mode"
is "$(status "$(JEV_TEST_KEY=$KEY "$JEV" "$T/plan.md" --project "$p")")" invalid_response "malformed JSON → invalid_response"

echo outofrange > "$T/mode"
is "$(status "$(JEV_TEST_KEY=$KEY "$JEV" "$T/plan.md" --project "$p")")" invalid_response "probability outside 0..1 → invalid_response"

echo http401 > "$T/mode"
is "$(status "$(JEV_TEST_KEY=$KEY "$JEV" "$T/plan.md" --project "$p")")" unavailable "HTTP 401 → unavailable"

echo redirect > "$T/mode"
is "$(status "$(JEV_TEST_KEY=$KEY "$JEV" "$T/plan.md" --project "$p")")" unavailable "redirect → unavailable"
if [ -e "$T/trap/auth" ]; then fail "redirect was followed (trap saw: $(cat "$T/trap/auth" | cut -c1-12)...)"; else ok "redirect not followed, key stays with the endpoint"; fi

echo disconnect > "$T/mode"
o=$(JEV_TEST_KEY=$KEY "$JEV" "$T/plan.md" --project "$p" 2>"$T/err")
is "$(status "$o")" unavailable "dropped connection → unavailable JSON"
if [ -s "$T/err" ]; then fail "dropped connection wrote to stderr"; else ok "dropped connection: no traceback"; fi

echo ok > "$T/mode"
o=$(JEV_TEST_KEY="$(printf 'abc\ndef-%s' "$KEY")" "$JEV" "$T/plan.md" --project "$p" 2>"$T/err")
is "$(status "$o")" unavailable "key with an embedded newline → unavailable"
if grep -qF "$KEY" "$T/err" || printf '%s' "$o" | grep -qF "$KEY"; then fail "malformed key leaked"; else ok "malformed key not in output"; fi

printf 'AC: the export includes totals\n' | JEV_TEST_KEY=$KEY "$JEV" "$T/plan.md" - --project "$p" >/dev/null
is "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"].get("issue", "").strip())' "$T/request.json")" "AC: the export includes totals" "issue from stdin goes into the state"

echo sleep > "$T/mode"
start=$(python3 -c 'import time; print(time.time())')
o=$(JEV_TEST_KEY=$KEY "$JEV" "$T/plan.md" --project "$p"); rc=$?
took=$(python3 -c "import time; print(round(time.time() - $start, 2))")
is "$(status "$o")" timeout "slow server → timeout"
if python3 -c "import sys; sys.exit(0 if $took < 3.5 else 1)"; then ok "timeout within 3.5 s ($took s)"; else fail "timeout took $took s"; fi
is "$rc" 0 "exit 0 even on timeout (advisory)"

python3 -c 'print("# Plan\n" + "word " * 40000)' > "$T/big.md"
rm -f "$T/request.json"
is "$(status "$(JEV_TEST_KEY=$KEY "$JEV" "$T/big.md" --project "$p")")" oversized_state "oversized plan → oversized_state"
if [ -e "$T/request.json" ]; then fail "oversized plan was sent"; else ok "oversized plan not sent"; fi

[ "$FAIL" -eq 0 ] && echo "All passed." || echo "$FAIL failed."
exit "$FAIL"
