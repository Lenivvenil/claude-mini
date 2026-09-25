#!/usr/bin/env python3
"""Parse a Bash command for `git ... commit` and print the commit subject (#308).

Input: env CMD (the command), CWD (for relative -F paths).
Output: NOTCOMMIT | ALLOW | NOMSG | SUBJECT<TAB><subject>. See commit-msg-check.sh.
"""
import os, re, shlex

cmd, cwd = os.environ["CMD"], os.environ["CWD"]
SEP = set(";&|()<>")

def tokens(text):
    lx = shlex.shlex(text, posix=True, punctuation_chars=";&|()<>")
    lx.whitespace_split = True
    lx.commenters = ""
    try:
        return list(lx)
    except ValueError:          # unbalanced quotes: fall back to a plain split
        return text.split()

def heredoc_first_line(text):
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if re.search(r"<<-?\s*['\"]?[A-Za-z_][A-Za-z0-9_]*['\"]?", line):
            return lines[i + 1] if i + 1 < len(lines) else ""
    return None

def subject_of(value):
    if value.lstrip().startswith("$(") and "<<" in value:
        line = heredoc_first_line(value)
        return line if line is not None else ""
    return value.split("\n", 1)[0]

toks = tokens(cmd)
i, found = 0, None
while i < len(toks):
    if toks[i] == "git":
        j = i + 1
        while j < len(toks) and not set(toks[j]) <= SEP:
            if toks[j] == "commit":
                found = j
                break
            j += 1
        if found is not None:
            break
    i += 1
if found is None:
    print("NOTCOMMIT"); raise SystemExit

args, k = [], found + 1
while k < len(toks) and not set(toks[k]) <= SEP:
    args.append(toks[k]); k += 1

reuse = False
n = 0
while n < len(args):
    a = args[n]
    nxt = args[n + 1] if n + 1 < len(args) else None
    if a in ("-m", "--message") or re.fullmatch(r"-[a-zA-Z]*m", a):
        print("SUBJECT\t" + subject_of(nxt or "")); raise SystemExit
    if a.startswith("--message="):
        print("SUBJECT\t" + subject_of(a.split("=", 1)[1])); raise SystemExit
    if re.fullmatch(r"-m.+", a):
        print("SUBJECT\t" + subject_of(a[2:])); raise SystemExit
    if a in ("-F", "--file") or a.startswith("--file="):
        path = a.split("=", 1)[1] if a.startswith("--file=") else (nxt or "")
        if path == "-":
            line = heredoc_first_line(cmd)
            print("SUBJECT\t" + (line or "")); raise SystemExit
        full = path if os.path.isabs(path) else os.path.join(cwd, path)
        try:
            with open(full, encoding="utf-8", errors="replace") as fh:
                print("SUBJECT\t" + fh.readline().rstrip("\n")); raise SystemExit
        except OSError:
            print("ALLOW"); raise SystemExit      # git will report the missing file itself
    if a in ("-c", "-C", "--reuse-message", "--reedit-message", "--amend", "--no-edit") \
       or a.startswith(("--reuse-message=", "--reedit-message=", "--fixup", "--squash")):
        reuse = True
    n += 1
print("ALLOW" if reuse else "NOMSG")
