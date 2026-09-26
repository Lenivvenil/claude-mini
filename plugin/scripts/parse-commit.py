#!/usr/bin/env python3
"""Parse a Bash command for every `git ... commit` and print each commit's subject (#308).

Input: env CMD (the command), CWD (the session's working directory).
Output, one line per commit invocation found, in order:
    ALLOW                      no subject to check (reuse / fixup / squash / amend / dry run)
    NOMSG                      no message source: git would open an editor
    SUBJECT<TAB><dir><TAB><subject>  first line of the first message source; <dir> is the
                               effective directory of that commit (cd, subshell, git -C)
    BADDIR                     that directory contains a tab or newline (hook denies)
Nothing is printed when the command runs no `git ... commit`.

Top-level heredoc bodies are cut out before tokenising (they are data, not commands)
and bound to their `<<` operator in order. The rest is tokenised with shlex (POSIX
quoting, multi-line strings). git commit options are parsed with their argument
boundaries: -m/-F/-c/-C/-t take a value (attached or next word), short flags bundle
(-am, -qam"x", -Fmsg.txt). Handled:
  -m/--message; a value of the form "$(cat <<'EOF' ... EOF)" -> first heredoc line;
  -F/--file PATH relative to the effective directory (preceding `cd`, restored after
  a `( ... )` subshell, git's global -C); -F - -> this commit's own heredoc;
  -c/-C/--reuse-message/--reedit-message, --amend/--no-edit, --fixup/--squash, --dry-run.
"""
import os
import re
import shlex

CMD, CWD = os.environ["CMD"], os.environ.get("CWD", ".")
PUNCT = ";&|()<>"
GIT_GLOBAL_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
SHORT_WITH_VALUE = set("mFcCt")
SHORT_OPTIONAL_ATTACHED = set("Su")  # -S[<keyid>], -u[<mode>]: value only when attached
LONG_WITH_VALUE = {"--message", "--file", "--reuse-message", "--reedit-message", "--template",
                   "--author", "--date", "--cleanup", "--trailer", "--fixup", "--squash",
                   "--pathspec-from-file"}
HEREDOC_OPENER = re.compile(r"(?<!<)<<(?!<)(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")


def split_heredocs(text):
    """Cut top-level heredoc bodies out of `text`; return (command text, bodies in order).

    A heredoc opened inside $( ... ) on its line (e.g. -m "$(cat <<'EOF' ...)") is part
    of a quoted value and is left in place; its body is still skipped for opener detection.
    """
    out, bodies, pending = [], [], []  # pending: [(delim, strip_tabs, keep, lines)]
    for line in text.split("\n"):
        if pending:
            delim, strip_tabs, keep, lines = pending[0]
            if (line.lstrip("\t") if strip_tabs else line) == delim:
                pending.pop(0)
                if keep:
                    out.append(line)
                else:
                    bodies.append("\n".join(lines))
            else:
                lines.append(line)
                if keep:
                    out.append(line)
            continue
        for m in HEREDOC_OPENER.finditer(line):
            before = line[:m.start()]
            in_subst = before.count("$(") > before.count(")")
            pending.append((m.group(3), m.group(1) == "-", in_subst, []))
        out.append(line)
    for _delim, _strip, keep, lines in pending:  # unterminated: body runs to the end
        if not keep:
            bodies.append("\n".join(lines))
    return "\n".join(out), bodies


def is_sep(tok):
    """Command separator token. shlex glues adjacent punctuation (`);`, `)&&`), and
    redirections (`>`, `>&`, `<<`) are not separators."""
    return bool(tok) and set(tok) <= set(PUNCT) and tok[0] not in "<>" \
        and any(c in ";|()" or (c == "&" and tok != ">&") for c in tok)


def tokenize(text):
    lx = shlex.shlex(text, posix=True, punctuation_chars=PUNCT)
    lx.whitespace_split = True
    lx.commenters = ""
    try:
        return list(lx)
    except ValueError:  # unbalanced quotes: fall back to a plain split
        return text.split()


def subject_of(value):
    if value.lstrip().startswith("$(") and "<<" in value:
        lines = value.split("\n")
        for i, line in enumerate(lines):
            if HEREDOC_OPENER.search(line):
                return lines[i + 1] if i + 1 < len(lines) else ""
        return ""
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


def main():
    text, bodies = split_heredocs(CMD)
    toks = tokenize(text)
    body_at = {pos: bodies[n] for n, pos in enumerate(p for p, t in enumerate(toks) if t == "<<")
               if n < len(bodies)}
    cur_dir, dir_stack = CWD, []
    i = 0
    while i < len(toks):
        t = toks[i]
        if is_sep(t):
            for c in t:
                if c == "(":
                    dir_stack.append(cur_dir)
                elif c == ")" and dir_stack:
                    cur_dir = dir_stack.pop()
        if t == "cd" and i + 1 < len(toks) and not is_sep(toks[i + 1]) and toks[i + 1] != "-":
            target = os.path.expanduser(toks[i + 1])
            cur_dir = target if os.path.isabs(target) else os.path.normpath(os.path.join(cur_dir, target))
            i += 2
            continue
        if t != "git":
            i += 1
            continue
        # git [global options] <subcommand> args...
        j, git_dir = i + 1, cur_dir
        while j < len(toks) and toks[j].startswith("-") and not is_sep(toks[j]):
            if toks[j] in GIT_GLOBAL_WITH_VALUE and j + 1 < len(toks):
                if toks[j] == "-C":
                    d = toks[j + 1]
                    git_dir = d if os.path.isabs(d) else os.path.normpath(os.path.join(git_dir, d))
                j += 2
            else:
                j += 1
        if j >= len(toks) or toks[j] != "commit":
            i = j  # the subcommand is a plain word; separators after it are handled above
            continue
        args, k, body = [], j + 1, None
        # shlex treats newlines as spaces: a following `git` or `cd` starts a new command
        while k < len(toks) and not is_sep(toks[k]) and toks[k] not in ("git", "cd"):
            if toks[k] in ("<<", "<<-") and k + 1 < len(toks):
                body = body_at.get(k)
                k += 2
                continue
            if set(toks[k]) <= set(PUNCT):  # other redirections: skip operator and target
                k += 2
                continue
            args.append(toks[k])
            k += 1
        verdict = analyse(args, git_dir, body)
        if verdict.startswith("SUBJECT\t"):
            if "\t" in git_dir or "\n" in git_dir:
                verdict = "BADDIR"
            else:
                verdict = "SUBJECT\t" + git_dir + "\t" + verdict[len("SUBJECT\t"):]
        print(verdict)
        i = k
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
