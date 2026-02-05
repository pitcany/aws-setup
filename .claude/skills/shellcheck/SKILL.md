---
name: shellcheck
description: |
  Lints Bash scripts for syntax errors, quoting issues, and style violations.
  Use when: writing or modifying .sh files, reviewing Bash code, fixing CI lint failures, adding new shell scripts to the project.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# Shellcheck

Static analysis for Bash scripts. Catches quoting bugs, undefined variables, deprecated syntax, and portability issues before they become runtime failures.

## This Project's Setup

Shellcheck runs as part of the test suite with **strict settings**:

```bash
shellcheck -x -S warning "$file"
```

- `-S warning` — treats warnings as errors (strict)
- `-x` — follows `source` directives to analyze included files

**Linted files:** `bin/ec2` and all `lib/*.sh`. Run via `./tests/run_tests.sh`.

## Quick Reference

| Flag | Purpose |
|------|---------|
| `-x` | Follow `source`/`.` directives |
| `-S warning` | Minimum severity: warning (fails on warnings) |
| `-S error` | Minimum severity: error only |
| `-e SC2034` | Exclude specific code |
| `-f diff` | Output as unified diff (auto-fixable) |
| `-f json` | Machine-readable output |
| `--shell=bash` | Force shell dialect |

## Source Directives

Every `source` statement needs a directive so shellcheck can resolve the file:

```bash
# shellcheck source=../lib/core.sh
source "${EC2_ROOT}/lib/core.sh"
```

For dynamic paths that can't be resolved statically:

```bash
# shellcheck source=/dev/null
source "$env_file"
```

## Suppressing Warnings

Suppress per-line with `disable`:

```bash
# shellcheck disable=SC2155
local output=$(some_command)
```

Suppress for an entire file (place after shebang):

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2034
```

NEVER blanket-disable without a comment explaining why.

## Common Codes in Bash Projects

| Code | Issue | Fix |
|------|-------|-----|
| SC2086 | Unquoted variable | `"$var"` not `$var` |
| SC2155 | Declare and assign separately | Split `local x=$(cmd)` into two lines |
| SC2034 | Unused variable | Remove or export if used by sourced script |
| SC2154 | Variable referenced but not assigned | Add `# shellcheck source=` or declare |
| SC2064 | Use single quotes for trap to prevent early expansion | `trap 'cleanup' EXIT` |
| SC2206 | Quote to prevent word splitting in arrays | `arr=("$var")` |
| SC2128 | Expanding array without index | `"${arr[@]}"` not `"$arr"` |

## Integration with This Project

The test runner (`tests/run_tests.sh:40-50`) conditionally runs shellcheck:

```bash
if command -v shellcheck &>/dev/null; then
  for f in "$PROJECT_ROOT"/bin/ec2 "$PROJECT_ROOT"/lib/*.sh; do
    run_test "shellcheck $(basename "$f")" shellcheck -x -S warning "$f"
  done
else
  run_skip "shellcheck" "not installed"
fi
```

New scripts added to `lib/` are automatically picked up by the glob.

## See Also

- [patterns](references/patterns.md) — Common SC codes, quoting rules, anti-patterns
- [workflows](references/workflows.md) — Lint-fix cycle, CI integration, adding new scripts

## Related Skills

See the **bash** skill for shell scripting patterns (`set -euo pipefail`, error handling, local variables) that prevent shellcheck warnings in the first place.