#!/usr/bin/env python3
"""Parse a Bash command for every `git ... commit` and print each commit's subject (#308).

Input: env CMD (the command), CWD (the session's working directory).
Output, one line per commit invocation found, in order:
    ALLOW                      no subject to check (reuse / fixup / squash / amend)
    NOMSG                      no message source: git would open an editor
    SUBJECT<TAB><subject>      first line of the first message source
Nothing is printed when the command runs no `git ... commit`.

Tokenised with shlex (POSIX quoting, multi-line strings). Handled:
  -m/--message VALUE, --message=VALUE, -mVALUE, short bundles (-am, -am"x");
  VALUE of the form "$(cat <<'EOF' ... EOF)" -> first heredoc line;
  -F/--file PATH and --file=PATH, relative to the effective directory
  (preceding `cd`, git's global -C); -F - bound to this commit's own heredoc;
  -c/-C/--reuse-message/--reedit-message, --amend/--no-edit, --fixup/--squash.
"""
import os
import re
import shlex

CMD, CWD = os.environ["CMD"], os.environ.get("CWD", ".")
PUNCT = ";&|()<>"
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", ";;", "|&"}
GIT_GLOBAL_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def tokenize(text):
    lx = shlex.shlex(text, posix=True, punctuation_chars=PUNCT)
    lx.whitespace_split = True
    lx.commenters = ""
    try:
        return list(lx)
    except ValueError:  # unbalanced quotes: fall back to a plain split
        return text.split()


def heredoc_subject(value):
    """First line after the heredoc opener inside a $(cat <<'EOF' ...) value."""
    lines = value.split("\n")
    for i, line in enumerate(lines):
        if re.search(r"<<-?\s*['\"]?[A-Za-z_][A-Za-z0-9_]*['\"]?", line):
            return lines[i + 1] if i + 1 < len(lines) else ""
    return ""


def subject_of(value):
    if value.lstrip().startswith("$(") and "<<" in value:
        return heredoc_subject(value)
    return value.split("\n", 1)[0]


def stdin_heredoc_subject(delim, occurrence):
    """First body line of the `occurrence`-th heredoc opened with `delim` on a commit line."""
    opener = re.compile(r"\bcommit\b.*<<-?\s*['\"]?" + re.escape(delim) + r"['\"]?\s*$")
    lines = CMD.split("\n")
    seen = 0
    for i, line in enumerate(lines):
        if opener.search(line):
            if seen == occurrence:
                return lines[i + 1] if i + 1 < len(lines) else ""
            seen += 1
    return ""


def read_first_line(path, base):
    full = path if os.path.isabs(path) else os.path.join(base, path)
    try:
        with open(full, encoding="utf-8", errors="replace") as fh:
            return fh.readline().rstrip("\n")
    except OSError:
        return None  # git reports the missing file itself


def analyse(args, base, heredoc_delim, heredoc_occurrence):
    # Subject-generating or message-reusing options win regardless of order.
    for a in args:
        if a in ("-c", "-C", "--reuse-message", "--reedit-message", "--amend", "--no-edit") \
                or a.startswith(("--reuse-message=", "--reedit-message=", "--fixup", "--squash")):
            has_msg = any(x in ("-m", "--message", "-F", "--file") or x.startswith(("--message=", "--file="))
                          or re.fullmatch(r"-[a-zA-Z]*m.*", x) for x in args)
            if a.startswith(("--fixup", "--squash")) or not has_msg:
                return "ALLOW"
    n = 0
    while n < len(args):
        a = args[n]
        nxt = args[n + 1] if n + 1 < len(args) else ""
        if a in ("-m", "--message"):
            return "SUBJECT\t" + subject_of(nxt)
        if a.startswith("--message="):
            return "SUBJECT\t" + subject_of(a.split("=", 1)[1])
        m = re.fullmatch(r"-([a-zA-Z]*?)m(.*)", a, re.S)
        if m and not a.startswith("--"):
            return "SUBJECT\t" + subject_of(m.group(2) if m.group(2) else nxt)
        if a in ("-F", "--file") or a.startswith("--file="):
            path = a.split("=", 1)[1] if a.startswith("--file=") else nxt
            if path == "-":
                if heredoc_delim is None:
                    return "ALLOW"  # message piped from elsewhere: nothing visible to check
                return "SUBJECT\t" + stdin_heredoc_subject(heredoc_delim, heredoc_occurrence)
            line = read_first_line(path, base)
            return "ALLOW" if line is None else "SUBJECT\t" + line
        n += 1
    return "NOMSG"


def main():
    toks = tokenize(CMD)
    cur_dir = CWD
    heredoc_count = {}
    i = 0
    while i < len(toks):
        t = toks[i]
        if t == "cd" and i + 1 < len(toks) and toks[i + 1] not in SEPARATORS:
            target = os.path.expanduser(toks[i + 1])
            cur_dir = target if os.path.isabs(target) else os.path.normpath(os.path.join(cur_dir, target))
            i += 2
            continue
        if t != "git":
            i += 1
            continue
        # git [global options] <subcommand> args...
        j, git_dir = i + 1, cur_dir
        while j < len(toks) and toks[j].startswith("-") and toks[j] not in SEPARATORS:
            if toks[j] in GIT_GLOBAL_WITH_VALUE and j + 1 < len(toks):
                if toks[j] == "-C":
                    d = toks[j + 1]
                    git_dir = d if os.path.isabs(d) else os.path.normpath(os.path.join(git_dir, d))
                j += 2
            else:
                j += 1
        if j >= len(toks) or toks[j] != "commit":
            i = j + 1
            continue
        args, k, delim = [], j + 1, None
        # shlex treats newlines as spaces: a following `git` or `cd` starts a new command
        while k < len(toks) and toks[k] not in SEPARATORS and toks[k] not in ("git", "cd"):
            if toks[k] in ("<<", "<<-") and k + 1 < len(toks):
                delim = toks[k + 1]
                k += 2
                continue
            if set(toks[k]) <= set(PUNCT):  # other redirections: skip operator and target
                k += 2
                continue
            args.append(toks[k])
            k += 1
        occurrence = heredoc_count.get(delim, 0) if delim else 0
        if delim:
            heredoc_count[delim] = occurrence + 1
        print(analyse(args, git_dir, delim, occurrence))
        i = k
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
