# Shellcheck Patterns Reference

## Contents
- Quoting Rules
- Variable Declaration
- Source Directives
- Array Handling
- Conditionals and Tests
- Anti-Patterns

---

## Quoting Rules

The single most common shellcheck category. This project enforces `"$var"` everywhere.

### WARNING: Unquoted Variables (SC2086)

**The Problem:**

```bash
# BAD — word splitting and globbing on unquoted variable
local files=$1
rm $files
```

**Why This Breaks:**
1. If `$files` contains spaces, each word becomes a separate argument
2. If it contains glob characters (`*`, `?`), the shell expands them
3. `rm important file.txt` deletes TWO files: `important` and `file.txt`

**The Fix:**

```bash
# GOOD — quoted variable prevents splitting
local files="$1"
rm "$files"
```

### Deliberate Word Splitting

When you actually need splitting, use arrays:

```bash
# BAD — relying on word splitting for multiple args
local opts="--profile default --region us-west-2"
aws ec2 describe-instances $opts

# GOOD — use an array
local -a opts=(--profile default --region us-west-2)
aws ec2 describe-instances "${opts[@]}"
```

---

## Variable Declaration

### WARNING: Declare and Assign Separately (SC2155)

**The Problem:**

```bash
# BAD — masks the exit code of the command
local output=$(aws ec2 describe-instances)
```

**Why This Breaks:**
`local` always returns 0, so if the command fails, `set -e` won't catch it. The error is silently swallowed.

**The Fix:**

```bash
# GOOD — exit code is preserved
local output
output=$(aws ec2 describe-instances)
```

This project uses `set -euo pipefail` everywhere, making SC2155 a real bug source.

### Unused Variables (SC2034)

Variables set in sourced library files trigger SC2034 because shellcheck doesn't see the consumer. This project handles it with `-x` flag and `# shellcheck source=` directives rather than disabling the code.

```bash
# In lib/core.sh — these look "unused" to shellcheck without -x
CFG_AWS_REGION="us-west-2"
CFG_SSH_KEY_PATH="~/.ssh/key.pem"
```

The `-x` flag in `shellcheck -x -S warning` resolves this by following source chains.

---

## Source Directives

### Static Paths

Used in `bin/ec2` for all library sourcing:

```bash
# shellcheck source=../lib/core.sh
source "${EC2_ROOT}/lib/core.sh"
# shellcheck source=../lib/cmd_instances.sh
source "${EC2_ROOT}/lib/cmd_instances.sh"
```

The path is relative to the file containing the directive, not the working directory.

### Dynamic Paths

Used in `scripts/lib.sh` where the path is computed at runtime:

```bash
# shellcheck source=/dev/null
source "$env_file"
```

Use `/dev/null` sparingly — it disables cross-file analysis for that source.

---

## Array Handling

### WARNING: Expanding Arrays Without Index (SC2128)

```bash
# BAD — expands only the first element
local tags=("Name=dev" "Project=aws-setup")
echo "$tags"

# GOOD — expands all elements
echo "${tags[@]}"
```

### WARNING: Unquoted Array Expansion (SC2068)

```bash
# BAD — word splitting on elements with spaces
for tag in ${tags[@]}; do echo "$tag"; done

# GOOD — preserves elements
for tag in "${tags[@]}"; do echo "$tag"; done
```

---

## Conditionals and Tests

### `[` vs `[[`

Shellcheck prefers `[[` for Bash scripts (SC2292). This project uses `[[ ]]` consistently:

```bash
# BAD — POSIX test, vulnerable to word splitting
if [ -z $var ]; then

# GOOD — Bash conditional, no splitting issues
if [[ -z "$var" ]]; then
```

### WARNING: Using `==` in `[ ]` (SC2039)

```bash
# BAD — == is not POSIX in single brackets
[ "$state" == "running" ]

# GOOD — use [[ ]] for == or = for [ ]
[[ "$state" == "running" ]]
```

---

## Anti-Patterns

### WARNING: Parsing ls Output (SC2012)

```bash
# BAD — breaks on filenames with spaces/newlines
for f in $(ls presets/); do echo "$f"; done

# GOOD — use glob
for f in presets/*.yaml; do echo "$f"; done
```

### WARNING: Useless Cat (SC2002)

```bash
# BAD — unnecessary process
cat config.yaml | grep "region"

# GOOD — grep reads files directly
grep "region" config.yaml
```

### WARNING: cd Without Error Check (SC2164)

```bash
# BAD — if cd fails, subsequent commands run in wrong directory
cd /some/path
rm -rf data/

# GOOD — fail fast
cd /some/path || die "Cannot cd to /some/path"
```

This project uses `set -e` which catches this, but explicit handling is clearer.