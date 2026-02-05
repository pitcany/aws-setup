---
name: aws-ec2
description: |
  Manages EC2 instance lifecycle in the EC2 Ops Kit codebase — launching, stopping, terminating instances, SSH, cleanup, and presets.
  Use when: modifying bin/ec2, lib/cmd_instances.sh, lib/cmd_network.sh, lib/cmd_cleanup.sh, presets/*.yaml, or config.yaml; adding commands, fixing instance operations, or extending the CLI.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# AWS EC2 Skill

EC2 Ops Kit is a pure Bash CLI (`bin/ec2`) for managing AWS EC2 instances. It uses a source-and-dispatch pattern: `bin/ec2` sources all `lib/*.sh` files, parses global flags, loads YAML config, and routes to `cmd_*` functions via a `case` statement. State flows through `EC2_*` (runtime), `CFG_*` (config), and `PRESET_*` (preset) globals.

## Quick Start

### Launch and connect

```bash
ec2 up --preset cpu-small --name dev-box
ec2 ssh dev-box
ec2 stop dev-box
```

### Launch GPU spot with TTL

```bash
ec2 up --preset gpu-t4 --name training --spot --ttl-hours 8
ec2 ssh training
ec2 terminate training
```

## Key Concepts

| Concept | Purpose | Location |
|---------|---------|----------|
| `cmd_*` functions | Public command handlers | `lib/cmd_instances.sh`, `lib/cmd_network.sh` |
| `_prefix_action` | Private subcommand handlers | e.g. `_eip_list`, `_spot_prices` |
| `resolve_one_instance` | Name/ID → instance lookup | `lib/core.sh:313` |
| `build_tag_spec` | Generates AWS tag JSON | `lib/core.sh:429` |
| `dry_run_guard` | Prevents execution in `--dry-run` | `lib/core.sh:279` |
| `load_preset` | Reads preset YAML into `PRESET_*` globals | `lib/core.sh:170` |
| `aws_cmd` | Wraps `aws` with profile/region | `lib/core.sh:226` |

## Common Patterns

### Adding a new command

1. Create `cmd_<name>()` in the appropriate `lib/cmd_*.sh`
2. Add `_<name>_help()` with usage, options, examples
3. Add routing in `bin/ec2` case statement (line 137+)
4. Add to `show_help()` in `bin/ec2`
5. Add tests in `tests/test_cli.sh`

### State checks before operations

```bash
# ALWAYS check state before acting — prevents double-start, stop-on-terminated
if [[ "$state" == "running" ]]; then
  info "$name ($id) is already running."
  return 0
fi
if [[ "$state" != "stopped" ]]; then
  die "Cannot start instance in state: $state"
fi
```

### Destructive operation guard

```bash
if ! dry_run_guard "aws ec2 terminate-instances --instance-ids $id"; then
  return 0
fi
confirm "Stop instance ${name:-$id}?" || return 1
```

## See Also

- [patterns](references/patterns.md) — Code patterns, naming, error handling, tagging
- [workflows](references/workflows.md) — Development, testing, adding commands/presets

## Related Skills

- See the **bash** skill for shell scripting conventions (`set -euo pipefail`, quoting, local variables)
- See the **aws-cli** skill for `aws` command patterns and `--query` JMESPath
- See the **jq** skill for JSON parsing of AWS CLI output
- See the **yaml** skill for the custom YAML parser limitations
- See the **aws-spot** skill for spot instance pricing and interruption handling
- See the **aws-eip** skill for Elastic IP lifecycle management
- See the **shellcheck** skill for lint compliance rules