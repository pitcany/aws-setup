---
name: bash
description: |
  Manages Bash 4+ scripting, shell functions, error handling, and CLI patterns.
  Use when: writing or modifying .sh files, adding CLI commands, building shell functions,
  fixing shellcheck warnings, implementing error handling, or working with bash arrays/strings.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# Bash Skill

This project is a pure Bash 4+ CLI (`bin/ec2`) following a source-and-dispatch architecture. All scripts use `set -euo pipefail`, communicate state via `EC2_*`/`CFG_*`/`PRESET_*` globals, and route commands through a central `case` statement. See the **shellcheck** skill for linting.

## Quick Reference

### Script Header

Every script and sourced library starts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Sourced libraries omit the shebang but keep the comment header:

```bash
#!/usr/bin/env bash
# cmd_instances.sh — list, info, up, start, stop, terminate
# Sourced by bin/ec2; do not run directly.
```

### Variable Quoting

```bash
# GOOD — always double-quote
local key_path="${1:-$CFG_SSH_KEY_PATH}"
aws_cmd ec2 describe-instances --instance-ids "$id"

# BAD — unquoted variables break on spaces and empty strings
aws_cmd ec2 describe-instances --instance-ids $id
```

### Local Variables

```bash
# GOOD — declare with local inside functions
my_function() {
  local instance_id="$1"
  local public_ip=""
  public_ip="$(aws_cmd ec2 describe-instances ...)"
}

# BAD — leaks into global scope
my_function() {
  instance_id="$1"
}
```

## Key Concepts

| Concept | Convention | Example |
|---------|-----------|---------|
| Globals | `EC2_*` screaming snake | `EC2_DRY_RUN`, `EC2_MOCK` |
| Config vars | `CFG_*` screaming snake | `CFG_AWS_REGION`, `CFG_SSH_KEY_PATH` |
| Preset vars | `PRESET_*` screaming snake | `PRESET_INSTANCE_TYPE` |
| Public functions | `cmd_<name>` | `cmd_list`, `cmd_up`, `cmd_ssh` |
| Private functions | `_<prefix>_<name>` | `_eip_list`, `_spot_prices` |
| Help functions | `_<cmd>_help` | `_up_help`, `_cleanup_help` |
| Utilities | `snake_case` | `load_config`, `resolve_instance` |

## Common Patterns

### Flag Parsing Loop

**When:** Every command that accepts options.

```bash
cmd_list() {
  local filter_state="" filter_tag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state)    filter_state="$2"; shift 2 ;;
      --tag)      filter_tag="$2"; shift 2 ;;
      -h|--help)  _list_help; return 0 ;;
      *)          warn "Unknown option: $1"; shift ;;
    esac
  done
  # ... command body
}
```

### Logging (never raw echo)

```bash
log "Instance launched: $instance_id"   # [ok] green
info "Waiting for IP..."                # [info] blue
warn "Permissions too open"             # [warn] yellow, stderr
err "Something failed"                  # [error] red, stderr
die "Fatal: cannot continue"            # [error] + exit 1
debug "Verbose detail"                  # only when EC2_DEBUG=1
```

### Safety Guards

```bash
# Confirmation prompt (skipped with --yes)
confirm "Stop instance ${name}?" || return 1

# Dry-run guard (returns 1 in dry-run mode)
if ! dry_run_guard "aws ec2 terminate-instances --instance-ids $id"; then
  return 0
fi
```

## See Also

- [patterns](references/patterns.md) — Error handling, arrays, process substitution, portability
- [workflows](references/workflows.md) — Adding commands, testing, debugging

## Related Skills

- See the **shellcheck** skill for linting and static analysis
- See the **yaml** skill for config and preset file format
- See the **aws-cli** skill for AWS command patterns
- See the **jq** skill for JSON parsing in pipelines