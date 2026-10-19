---
name: quiet-shell
description: Run shell commands so their output stays short. Use for every build, test, install, git or log command.
---
# Quiet shell

- **Quiet flags:** `npm i --silent`, `pip install -q`, `cargo build -q`, `pytest -q --no-header -rf`, `go test ./pkg/...`, and a dot or summary reporter for JS test runners.
- **Git:** start with `git status -sb` and `git --no-pager diff --stat`. Then run `git --no-pager diff -U1 -- <file>` only for the files you need. For history, use `git log --oneline -n 10`.
- **Long or unknown output:** write it to a file and look at only the part you need:
  ```bash
  cmd > "${TMPDIR:-/tmp}/pi-out.log" 2>&1; echo "exit $?"
  tail -n 30 "${TMPDIR:-/tmp}/pi-out.log"
  rg -n "error|FAIL|panic|Traceback" "${TMPDIR:-/tmp}/pi-out.log" | head -n 20
  ```
- **Scope** tests, linters and type checks to the files or packages you touched. Run the full suite only when asked.
- **Never** run `ls -R`, `find /`, `tree` without `-L 2`, or `cat` on large files. Use `fd --max-depth 2`.
- If a result ends with a path to the saved raw output (token-killer tee file), read only the slice you need from it.
