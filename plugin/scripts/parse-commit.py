#!/usr/bin/env python3
"""Parse a Bash command for every `git ... commit` and print each commit's subject (#308).

Input: env CMD (the command), CWD (the session's working directory).
Output, one line per commit invocation found, in order:
    ALLOW                      no subject to check (reuse / fixup / squash / amend / dry run)
    NOMSG                      no message source: git would open an editor
    SUBJECT<TAB><subject>      first line of the first message source
Nothing is printed when the command runs no `git ... commit`.

A small Bash-aware tokenizer (not shlex) keeps what matters for this check:
quoting ('...', "...", $'...', backslash), comments only at a word start, newlines
and control operators as command boundaries, heredocs only at a real `<<`/`<<-`
operator (bodies are data, tabs stripped for <<-), $( ... ) kept as raw text.
`git` counts only in command position. git commit options are parsed with their
argument boundaries: -m/-F/-c/-C/-t take a value (attached or next word).
The effective directory follows `cd` (with its options), is restored after a
`( ... )` subshell, and honours git's global -C.
Known limits: aliases, functions, eval, `sh -c '...'`, variables in paths.
"""
import os

CMD, CWD = os.environ["CMD"], os.environ.get("CWD", ".")

OPERATORS = ["<<<", "<<-", "&&", "||", ";;", "|&", "<<", ">>", ">&", "<&", "&>", ">|",
             ";", "&", "|", "(", ")", "<", ">"]
BOUNDARY = {";", "&&", "||", "|", "&", "|&", ";;", "(", ")", "\n"}
OP_START = set(";&|()<>")
GIT_GLOBAL_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
SHORT_WITH_VALUE = set("mFcCt")
SHORT_OPTIONAL_ATTACHED = set("Su")  # -S[<keyid>], -u[<mode>]: value only when attached
LONG_WITH_VALUE = {"--message", "--file", "--reuse-message", "--reedit-message", "--template",
                   "--author", "--date", "--cleanup", "--trailer", "--fixup", "--squash",
                   "--pathspec-from-file"}
ANSI_C = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "e": "\x1b", "E": "\x1b",
          "f": "\f", "v": "\v", "\\": "\\", "'": "'", '"': '"', "?": "?"}


class Tok:
    def __init__(self, kind, value, heredoc=None):
        self.kind, self.value, self.heredoc = kind, value, heredoc  # kind: word | op

    def is_op(self, *values):
        return self.kind == "op" and (not values or self.value in values)


def scan_subst(s, i):
    """s[i:] starts with '$('; return index just past the matching ')'."""
    depth, i = 0, i + 1
    while i < len(s):
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if s.startswith("<<", i) and not s.startswith("<<<", i):
            # heredoc inside the substitution: its body is text (apostrophes, "1)")
            strip = s.startswith("<<-", i)
            j = i + (3 if strip else 2)
            while j < len(s) and s[j] in " \t":
                j += 1
            delim, j = read_word(s, j)
            nl = s.find("\n", j)
            while nl >= 0:
                end = s.find("\n", nl + 1)
                line = s[nl + 1:len(s) if end < 0 else end]
                if (line.lstrip("\t") if strip else line) == delim:
                    break
                nl = end
            i = len(s) if nl < 0 or end < 0 else end
            continue
        if c == "'":
            i = s.find("'", i + 1)
            if i < 0:
                return len(s)
        elif c == '"':
            i += 1
            while i < len(s) and s[i] != '"':
                i += 2 if s[i] == "\\" else 1
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(s)


def read_word(s, i):
    """Read one shell word starting at s[i]; return (decoded value, next index)."""
    out = []
    while i < len(s):
        c = s[i]
        if c in " \t\n" or c in OP_START:
            break
        if c == "\\":
            if i + 1 < len(s) and s[i + 1] != "\n":
                out.append(s[i + 1])
            i += 2
        elif c == "'":
            j = s.find("'", i + 1)
            j = len(s) if j < 0 else j
            out.append(s[i + 1:j])
            i = j + 1
        elif s.startswith("$'", i):
            i += 2
            while i < len(s) and s[i] != "'":
                if s[i] == "\\" and i + 1 < len(s):
                    out.append(ANSI_C.get(s[i + 1], "\\" + s[i + 1]))
                    i += 2
                else:
                    out.append(s[i])
                    i += 1
            i += 1
        elif c == '"':
            i += 1
            while i < len(s) and s[i] != '"':
                if s[i] == "\\" and i + 1 < len(s) and s[i + 1] in '$`"\\\n':
                    if s[i + 1] != "\n":
                        out.append(s[i + 1])
                    i += 2
                elif s.startswith("$(", i):
                    j = scan_subst(s, i)
                    out.append(s[i:j])
                    i = j
                else:
                    out.append(s[i])
                    i += 1
            i += 1
        elif s.startswith("$(", i):
            j = scan_subst(s, i)
            out.append(s[i:j])
            i = j
        elif c == "`":
            j = s.find("`", i + 1)
            j = len(s) if j < 0 else j
            out.append(s[i:j + 1])
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out), i


def tokenize(s):
    toks, pending, i = [], [], 0
    while i < len(s):
        c = s[i]
        if c in " \t":
            i += 1
            continue
        if s.startswith("\\\n", i):
            i += 2
            continue
        if c == "#":  # comment: only reachable at a word start
            j = s.find("\n", i)
            i = len(s) if j < 0 else j
            continue
        if c == "\n":
            toks.append(Tok("op", "\n"))
            i += 1
            for doc in pending:  # heredoc bodies start on the next line
                lines = []
                while i < len(s):
                    j = s.find("\n", i)
                    j = len(s) if j < 0 else j
                    line = s[i:j]
                    i = j + 1
                    if doc["strip"]:
                        line = line.lstrip("\t")
                    if line == doc["delim"]:
                        break
                    lines.append(line)
                doc["body"] = "\n".join(lines)
            pending = []
            continue
        op = next((o for o in OPERATORS if s.startswith(o, i)), None)
        if op:
            i += len(op)
            if op in ("<<", "<<-"):
                while i < len(s) and s[i] in " \t":
                    i += 1
                delim, i = read_word(s, i)
                doc = {"delim": delim, "strip": op == "<<-", "body": ""}
                pending.append(doc)
                toks.append(Tok("op", "<<", doc))
            else:
                toks.append(Tok("op", op))
            continue
        value, i = read_word(s, i)
        toks.append(Tok("word", value))
    return toks


def subject_of(value):
    """First line of a message value; for "$(cat <<'EOF' ... EOF)" the first body line."""
    if value.lstrip().startswith("$(") and "<<" in value:
        lines = value.split("\n")
        return lines[1] if len(lines) > 1 else ""
    return value.split("\n", 1)[0]


def read_first_line(path, base):
    full = path if os.path.isabs(path) else os.path.join(base, path)
    try:
        with open(full, encoding="utf-8", errors="replace") as fh:
            return fh.readline().rstrip("\n")
    except OSError:
        return None  # git reports the missing file itself


def parse_commit_args(args):
    """Return (message sources in order as (kind, value), set of mode flags)."""
    sources, flags = [], set()
    n = 0
    while n < len(args):
        a = args[n]
        nxt = args[n + 1] if n + 1 < len(args) else ""
        if a == "--":
            break
        if a.startswith("--"):
            name, eq, val = a.partition("=")
            if name in LONG_WITH_VALUE and not eq:
                val, n = nxt, n + 1
            if name == "--message":
                sources.append(("m", val))
            elif name == "--file":
                sources.append(("F", val))
            elif name in ("--reuse-message", "--reedit-message"):
                flags.add("reuse")
            elif name in ("--fixup", "--squash"):
                flags.add("fixup")
            elif name in ("--amend", "--no-edit", "--dry-run"):
                flags.add(name[2:])
        elif a.startswith("-") and len(a) > 1:
            for pos in range(1, len(a)):
                ch = a[pos]
                if ch in SHORT_WITH_VALUE:
                    val = a[pos + 1:]
                    if not val:
                        val, n = nxt, n + 1
                    if ch == "m":
                        sources.append(("m", val))
                    elif ch == "F":
                        sources.append(("F", val))
                    elif ch in "cC":
                        flags.add("reuse")
                    break
                if ch in SHORT_OPTIONAL_ATTACHED:
                    break
        n += 1
    return sources, flags


def analyse(args, base, heredoc_body):
    sources, flags = parse_commit_args(args)
    # git itself rejects -m/-F together with -c/-C/--fixup/--squash, and a dry run
    # writes nothing: none of these needs a subject check.
    if flags & {"fixup", "reuse", "dry-run"}:
        return "ALLOW"
    if sources:
        kind, val = sources[0]
        if kind == "m":
            return "SUBJECT\t" + subject_of(val)
        if val == "-":
            if heredoc_body is None:
                return "ALLOW"  # message piped from elsewhere: nothing visible to check
            return "SUBJECT\t" + heredoc_body.split("\n", 1)[0]
        line = read_first_line(val, base)
        return "ALLOW" if line is None else "SUBJECT\t" + line
    if flags & {"amend", "no-edit"}:
        return "ALLOW"
    return "NOMSG"


def resolve(base, path):
    path = os.path.expanduser(path)
    return path if os.path.isabs(path) else os.path.normpath(os.path.join(base, path))


def main():
    toks = tokenize(CMD)
    cur_dir, dir_stack = CWD, []
    i, cmd_pos = 0, True
    while i < len(toks):
        t = toks[i]
        if t.kind == "op":
            if t.value == "(":
                dir_stack.append(cur_dir)
            elif t.value == ")" and dir_stack:
                cur_dir = dir_stack.pop()
            if t.value in BOUNDARY:
                cmd_pos = True
            elif t.value != "<<" and i + 1 < len(toks) and toks[i + 1].kind == "word":
                i += 1  # redirection target (a heredoc delimiter is consumed by tokenize)
            i += 1
            continue
        if not cmd_pos:
            i += 1
            continue
        word = t.value
        if "=" in word and word.split("=", 1)[0].isidentifier():  # VAR=value prefix
            i += 1
            continue
        cmd_pos = False
        if word == "cd":
            j, operand, opts_done = i + 1, None, False
            while j < len(toks) and toks[j].kind == "word":
                w = toks[j].value
                j += 1
                if not opts_done and w == "--":
                    opts_done = True
                elif not opts_done and w.startswith("-") and w != "-":
                    continue  # -L, -P, -e, -@
                elif operand is None:
                    operand = w
            if operand is None:
                cur_dir = os.path.expanduser("~")
            elif operand != "-":  # `cd -` goes to $OLDPWD: unknown here, keep
                cur_dir = resolve(cur_dir, operand)
            i = j
            continue
        if word != "git":
            i += 1
            continue
        # git [global options] <subcommand> args...
        j, git_dir = i + 1, cur_dir
        while j < len(toks) and toks[j].kind == "word" and toks[j].value.startswith("-"):
            if toks[j].value in GIT_GLOBAL_WITH_VALUE and j + 1 < len(toks):
                if toks[j].value == "-C":
                    git_dir = resolve(git_dir, toks[j + 1].value)
                j += 2
            else:
                j += 1
        if j >= len(toks) or toks[j].kind != "word" or toks[j].value != "commit":
            i = j
            continue
        args, k, body = [], j + 1, None
        while k < len(toks) and not toks[k].is_op(*BOUNDARY):
            tk = toks[k]
            if tk.is_op("<<"):
                body = tk.heredoc["body"]
                k += 1
                continue
            if tk.kind == "op":  # other redirections: skip operator and target
                k += 2
                continue
            args.append(tk.value)
            k += 1
        print(analyse(args, git_dir, body))
        i = k
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
