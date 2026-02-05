# Bash Workflows Reference

## Contents
- Adding a New Command
- Adding a New Test
- Running Tests
- Debugging
- Working with the YAML Parser
- Releasing Changes

## Adding a New Command

Copy this checklist and track progress:
- [ ] Step 1: Create `cmd_<name>()` in the appropriate `lib/cmd_*.sh` file
- [ ] Step 2: Add `_<name>_help()` with usage, options, and examples
- [ ] Step 3: Add routing in `bin/ec2` case statement (line 137+), including aliases
- [ ] Step 4: Add entry to `show_help()` in `bin/ec2`
- [ ] Step 5: Add tests in `tests/test_cli.sh`
- [ ] Step 6: Run `./tests/run_tests.sh` and verify all pass

### Step 1: Command Function

Follow the existing pattern — flag parsing loop, guard clauses, then action:

```bash
# lib/cmd_instances.sh (or appropriate module)
cmd_mycommand() {
  local target="" flag_verbose=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose)  flag_verbose=true; shift ;;
      -h|--help)  _mycommand_help; return 0 ;;
      *)          target="$1"; shift ;;
    esac
  done

  if [[ -z "$target" ]]; then
    die "Usage: ec2 mycommand <name|instance-id>"
  fi

  local line
  line="$(resolve_one_instance "$target")"
  local id name state
  IFS=$'\t' read -r id name state _ _ _ <<< "$line"

  # Guard: check state
  if [[ "$state" == "terminated" ]]; then
    die "Instance is terminated"
  fi

  # Dry-run check for destructive ops
  if ! dry_run_guard "aws ec2 my-action --instance-ids $id"; then
    return 0
  fi

  # Do the work
  aws_cmd ec2 my-action --instance-ids "$id" >/dev/null
  log "Action completed on $id"
}
```

### Step 3: Routing Entry

```bash
# bin/ec2, inside the command routing case statement
case "$COMMAND" in
  # ... existing commands ...
  mycommand|myalias)  cmd_mycommand "$@" ;;
  # ...
esac
```

## Adding a New Test

Tests use a `case` dispatch pattern with simple assertions.

```bash
# tests/test_cli.sh — add a new case
  mytestname)
    # Setup
    CFG_TAG_PROJECT="test-project"

    # Execute
    result="$(some_function "input")"

    # Assert
    [[ "$result" == "expected" ]] || { echo "FAIL: got $result"; exit 1; }
    ;;
```

Register it in `tests/run_tests.sh`:

```bash
run_test "my test description" bash "$SCRIPT_DIR/test_cli.sh" mytestname
```

### Test Runner Pattern

The runner uses `pass`/`fail` counters and a `run_test` helper:

```bash
run_test() {
  local name="$1"; shift
  printf '  %-50s ' "$name"
  if output=$("$@" 2>&1); then
    printf '%b\n' "${GREEN}PASS${NC}"
    pass=$((pass + 1))
  else
    printf '%b\n' "${RED}FAIL${NC}"
    printf '%s\n' "$output" | head -5 | sed 's/^/    /'
    fail=$((fail + 1))
  fi
}
```

## Running Tests

```bash
./tests/run_tests.sh
```

1. Make changes
2. Validate: `./tests/run_tests.sh`
3. If validation fails, fix issues and repeat step 2
4. Only proceed when all tests pass

Tests run in mock mode (`EC2_MOCK=true`) — no AWS API calls are made. The **shellcheck** skill covers lint configuration.

## Debugging

### Enable Debug Output

```bash
ec2 --debug list
# or
EC2_DEBUG=1 ./bin/ec2 list
```

This activates `debug()` calls throughout the codebase, printing to stderr with `[debug]` prefix.

### Mock Mode

Run any command without AWS API calls:

```bash
ec2 --mock list
```

Useful for testing CLI parsing and flag behavior. Auth checks are skipped.

### Common Debug Scenarios

**Config not loading:**
```bash
EC2_DEBUG=1 ./bin/ec2 --config ./config.yaml list
# Look for "Loading config from ..." in debug output
```

**Shellcheck failures:**
```bash
shellcheck -x -S warning bin/ec2 lib/*.sh
# -x follows source directives
# -S warning sets minimum severity
```

**Flag parsing issues — trace execution:**
```bash
bash -x ./bin/ec2 --profile myprof list 2>&1 | head -40
```

## Working with the YAML Parser

The `parse_yaml` function in `core.sh` handles flat and one-level nested YAML only. See the **yaml** skill for format details.

### What It Supports

```yaml
# Top-level key: value
name: my-value

# One level of nesting
aws:
  profile: default
  region: us-west-2

# Quoted values (both styles)
path: "/home/user/.ssh/key.pem"
desc: 'single quoted'

# Comments (full-line only, not inside quotes)
# This is a comment
```

### What It Does NOT Support

- Multi-level nesting (`a: b: c:`)
- Lists (`- item`)
- Multi-line strings (`|`, `>`)
- Anchors and aliases (`&`, `*`)
- Flow syntax (`{a: 1, b: 2}`)

### WARNING: Inline Comments in Quoted Values

```yaml
# BAD — inline comment stripped even though it's part of the value
description: "My instance # with hash"   # parse_yaml strips " # with hash"

# GOOD — value is fully quoted, no inline comment
description: "My instance with hash"
```

The parser skips inline comment stripping when the line contains quotes, but edge cases exist. Keep values simple.

### Using Parsed Output

```bash
# parse_yaml returns "section_key=value" lines
local parsed
parsed="$(parse_yaml "$config_file")"

# Extract a value with a helper pattern
local val
val="$(printf '%s\n' "$parsed" | while IFS='=' read -r k v; do
  [[ "$k" == "aws_region" ]] && printf '%s' "$v" && break
done)"
```

## Releasing Changes

Copy this checklist and track progress:
- [ ] Step 1: Ensure all tests pass: `./tests/run_tests.sh`
- [ ] Step 2: Run shellcheck manually: `shellcheck -x -S warning bin/ec2 lib/*.sh`
- [ ] Step 3: Test the specific command manually with `--dry-run`
- [ ] Step 4: Test with `--mock` flag for non-destructive validation
- [ ] Step 5: Commit with descriptive message referencing what changed
- [ ] Step 6: Create PR against `main` branch