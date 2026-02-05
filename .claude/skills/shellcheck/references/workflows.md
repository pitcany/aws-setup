# Shellcheck Workflows Reference

## Contents
- Lint-Fix Cycle
- Adding New Scripts
- CI Integration
- Fixing Common Failures
- Bulk Fixing

---

## Lint-Fix Cycle

The standard iterate-until-pass workflow:

1. Run shellcheck: `shellcheck -x -S warning bin/ec2 lib/*.sh`
2. Fix the first reported issue
3. Re-run shellcheck
4. Repeat until clean

Copy this checklist when linting a new or modified script:
- [ ] Run `shellcheck -x -S warning <file>`
- [ ] Fix all SC errors (highest priority)
- [ ] Fix all SC warnings
- [ ] Add `# shellcheck source=` directives for any `source` statements
- [ ] Re-run to confirm clean output
- [ ] Run full test suite: `./tests/run_tests.sh`

### Quick Single-File Check

```bash
shellcheck -x -S warning lib/cmd_instances.sh
```

### Check All Project Files

```bash
shellcheck -x -S warning bin/ec2 lib/*.sh
```

### Diff-Friendly Output

For auto-fixable issues, shellcheck can output a diff:

```bash
shellcheck -f diff lib/core.sh | patch -p1
```

WARNING: Review the diff before applying. Not all suggestions are appropriate (e.g., it may suggest `[` over `[[` for portability, but this project targets Bash 4+).

---

## Adding New Scripts

When adding a new `.sh` file to `lib/`:

1. **It's automatically linted** — the test runner globs `lib/*.sh`
2. **Add source directives** in `bin/ec2` if it's sourced there:

```bash
# shellcheck source=../lib/cmd_newfeature.sh
source "${EC2_ROOT}/lib/cmd_newfeature.sh"
```

3. **No shebang needed for library files** — they're sourced, not executed
4. **No `set -euo pipefail` in library files** — inherited from `bin/ec2`

When adding a new executable script (e.g., in `scripts/` or `bin/`):

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Then add it to the lint target if it's not under `lib/`.

---

## CI Integration

The test runner handles shellcheck gracefully when it's not installed:

```bash
if command -v shellcheck &>/dev/null; then
  # lint runs
else
  run_skip "shellcheck" "not installed"
fi
```

For CI environments, ensure shellcheck is installed. See the **bash** skill for shell environment setup.

### Installing Shellcheck

```bash
# macOS
brew install shellcheck

# Ubuntu/Debian
apt-get install shellcheck

# From binary (CI-friendly)
scversion="v0.10.0"
wget -qO- "https://github.com/koalaman/shellcheck/releases/download/${scversion}/shellcheck-${scversion}.linux.x86_64.tar.xz" \
  | tar -xJf - --strip-components=1 shellcheck-${scversion}/shellcheck
```

---

## Fixing Common Failures

### SC2154: Variable Referenced but Not Assigned

This fires on variables set in a sourced file. Two fixes:

**Option A — Source directive (preferred):**

```bash
# shellcheck source=../lib/core.sh
source "${EC2_ROOT}/lib/core.sh"
# Now CFG_AWS_REGION is known to shellcheck
```

**Option B — Explicit declaration (for external inputs):**

```bash
# Set by calling script or environment
: "${EC2_ROOT:?EC2_ROOT must be set}"
```

### SC2034: Variable Appears Unused

Common in library files where variables are consumed by the sourcing script. The `-x` flag resolves most cases. If it persists:

```bash
# shellcheck disable=SC2034  # Used by bin/ec2
CFG_AWS_REGION="$region"
```

Always add a comment explaining who uses it.

### SC2046: Quote to Prevent Word Splitting

```bash
# BAD — shellcheck flags this
local ami_id=$(aws ec2 describe-images --query 'Images[0].ImageId' --output text)

# GOOD — quote the command substitution AND declare separately
local ami_id
ami_id="$(aws ec2 describe-images --query 'Images[0].ImageId' --output text)"
```

### SC2162: read Without -r

```bash
# BAD — backslashes interpreted as escapes
read -p "Instance name: " name

# GOOD — raw mode preserves input
read -rp "Instance name: " name
```

---

## Bulk Fixing

### Find All Issues Across Project

```bash
shellcheck -x -S warning -f gcc bin/ec2 lib/*.sh 2>&1 | sort -t: -k4
```

Groups by error code so you can fix one category at a time.

### Count Issues by Code

```bash
shellcheck -x -S warning -f json bin/ec2 lib/*.sh 2>/dev/null \
  | jq -r '.[].code' | sort | uniq -c | sort -rn
```

See the **jq** skill for more JSON processing patterns.

### Fix All Quoting Issues at Once

Most SC2086 fixes are mechanical — add double quotes. The diff output helps:

```bash
for f in bin/ec2 lib/*.sh; do
  shellcheck -f diff "$f" > /tmp/sc.patch 2>/dev/null
  if [[ -s /tmp/sc.patch ]]; then
    echo "Fixing: $f"
    patch -p1 < /tmp/sc.patch
  fi
done
```

1. Run the bulk fix
2. Validate: `shellcheck -x -S warning bin/ec2 lib/*.sh`
3. If validation fails, fix remaining issues manually and repeat step 2
4. Run full test suite: `./tests/run_tests.sh`
5. Only commit when both shellcheck and tests pass