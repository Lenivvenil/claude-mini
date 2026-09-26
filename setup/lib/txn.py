"""Crash-safe changes inside one project (docs/port/PLAN.md §4, ADR-0031 §2; #313).

Every change is recorded in <run_dir>/intent.jsonl before and after it happens, so a crash at any
point leaves either the old file or the new one, and `recover()` can tell which.

File change, per item:
  1. append {op: file, state: started, path, sha_before, sha_candidate, tmp, backup}, fsync;
  2. write the candidate to a temp file in the target's directory, fsync;
  3. validate the candidate (caller's check); on failure remove it, append state: aborted;
  4. copy the original to the backup (if there is one), fsync; atomic os.replace;
  5. append {state: done, sha_after}.

`recover()` handles a `started` record without an end: the target still has sha_before -> the
temp file is removed; the target has sha_candidate -> the original comes back from the backup (or
the new file is removed when there was none); anything else -> reported as broken, left alone.

Package installs are logged the same way (op: install / uninstall) by setup/harness.

Fault injection for tests: CLAUDE_MINI_SETUP_FAULT=<point> makes the process exit(99) at that
point without cleanup. Points: after-intent, before-swap, after-swap, after-done.
"""
import hashlib
import json
import os
import shutil
import time

FAULT_ENV = "CLAUDE_MINI_SETUP_FAULT"


class TxnError(Exception):
    pass


def fault(point):
    if os.environ.get(FAULT_ENV) == point:
        os._exit(99)


def sha_of(path):
    if not os.path.lexists(path):
        return None
    if os.path.islink(path) or not os.path.isfile(path):
        return "not-a-regular-file"
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _fsync_dir(path):
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        os.close(fd)


class Txn:
    def __init__(self, project, run_dir):
        self.project = os.path.realpath(project)
        self.run_dir = self.contain(run_dir)
        self.log = os.path.join(self.run_dir, "intent.jsonl")

    def contain(self, rel):
        """Absolute path of rel inside the project; refuses anything that resolves outside."""
        if os.path.isabs(rel):
            raise TxnError(f"{rel}: absolute paths are not accepted")
        path = os.path.realpath(os.path.join(self.project, rel))
        if path != self.project and not path.startswith(self.project + os.sep):
            raise TxnError(f"{rel}: resolves outside the project")
        return path

    # --- intent log -------------------------------------------------------------------------
    def append(self, record):
        os.makedirs(self.run_dir, exist_ok=True)
        record = dict(record, ts=time.strftime("%Y-%m-%dT%H:%M:%S%z"))
        with open(self.log, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")
            fh.flush()
            os.fsync(fh.fileno())

    def records(self):
        if not os.path.exists(self.log):
            return []
        out = []
        with open(self.log, encoding="utf-8") as fh:
            for n, line in enumerate(fh, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except ValueError:
                    raise TxnError(f"{self.log}:{n}: unreadable intent record") from None
        return out

    def open_records(self):
        """`started` records with no later done/aborted/recovered record for the same key."""
        pending = {}
        for r in self.records():
            key = (r.get("op"), r.get("item"), r.get("path"))
            if r.get("state") == "started":
                pending[key] = r
            else:
                pending.pop(key, None)
        return list(pending.values())

    # --- file change ------------------------------------------------------------------------
    def write_file(self, item, rel, data, validate=None, mode=0o644):
        path = self.contain(rel)
        directory = os.path.dirname(path)
        before = sha_of(path)
        if before == "not-a-regular-file":
            raise TxnError(f"{rel}: exists and is not a regular file; left alone")
        candidate = hashlib.sha256(data).hexdigest()
        if before == candidate:
            return False  # nothing to do, nothing written
        stamp = f"{os.getpid()}-{int(time.time() * 1000)}"
        tmp = os.path.join(directory, f".{os.path.basename(path)}.claude-mini-{stamp}.tmp")
        backup = None
        if before is not None:
            backup = os.path.join(self.run_dir, "backups", stamp, rel)
        base = {"op": "file", "item": item, "path": rel}
        self.append(dict(base, state="started", sha_before=before, sha_candidate=candidate,
                         tmp=os.path.relpath(tmp, self.project),
                         backup=os.path.relpath(backup, self.project) if backup else None))
        fault("after-intent")
        os.makedirs(directory, exist_ok=True)
        with open(tmp, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, mode)
        if validate is not None:
            problem = validate(tmp)
            if problem:
                os.unlink(tmp)
                self.append(dict(base, state="aborted", reason=problem))
                raise TxnError(f"{rel}: candidate rejected: {problem}")
        if backup:
            os.makedirs(os.path.dirname(backup), exist_ok=True)
            shutil.copy2(path, backup)
            with open(backup, "rb") as fh:
                os.fsync(fh.fileno())
        fault("before-swap")
        os.replace(tmp, path)
        _fsync_dir(directory)
        fault("after-swap")
        self.append(dict(base, state="done", sha_after=candidate))
        fault("after-done")
        return True

    # --- recovery ---------------------------------------------------------------------------
    def recover(self):
        """Resolve interrupted changes. Returns (recovered, broken): lists of human lines."""
        recovered, broken = [], []
        for r in self.open_records():
            if r.get("op") != "file":
                broken.append(f"{r.get('item')}: interrupted {r.get('op')} of {r.get('path')}; "
                              "check it by hand")
                continue
            path = self.contain(r["path"])
            tmp = self.contain(r["tmp"])
            now = sha_of(path)
            if now == r["sha_before"]:
                if os.path.lexists(tmp):
                    os.unlink(tmp)
                self.append({"op": "file", "item": r["item"], "path": r["path"],
                             "state": "recovered", "result": "unchanged"})
                recovered.append(f"{r['item']}: {r['path']} was not changed; temp file removed")
            elif now == r["sha_candidate"]:
                if r.get("backup"):
                    backup = self.contain(r["backup"])
                    if sha_of(backup) != r["sha_before"]:
                        broken.append(f"{r['item']}: {r['path']} changed, backup missing or "
                                      "altered; restore by hand")
                        continue
                    shutil.copy2(backup, path + ".claude-mini-restore")
                    os.replace(path + ".claude-mini-restore", path)
                else:
                    os.unlink(path)
                self.append({"op": "file", "item": r["item"], "path": r["path"],
                             "state": "recovered", "result": "restored"})
                recovered.append(f"{r['item']}: {r['path']} restored to its state before setup")
            else:
                broken.append(f"{r['item']}: {r['path']} matches neither the original nor the "
                              "candidate; left alone")
        return recovered, broken
