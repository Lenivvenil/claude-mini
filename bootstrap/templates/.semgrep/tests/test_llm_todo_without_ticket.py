# Semgrep test fixtures for llm-todo-without-ticket
# Format: "# ruleid: <id>" marks expected match; "# ok: <id>" marks expected non-match.

# ok: llm-todo-without-ticket
x = 1  # TODO #123: fix this later

# ok: llm-todo-without-ticket
y = 2  # FIXME https://github.com/org/repo/issues/42 description

# ruleid: llm-todo-without-ticket
z = 3  # TODO: fix this without any ticket

# ruleid: llm-todo-without-ticket
w = 4  # FIXME no reference here

# ruleid: llm-todo-without-ticket
v = 5  # HACK this needs cleanup
