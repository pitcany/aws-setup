# EC2 Ops Kit

Fast, safe CLI for managing AWS EC2 instances (CPU and GPU) via one-liner bash commands. Built for data scientists who need on-demand compute — launch GPU spot instances, SSH in, track costs, and clean up orphaned resources. Pure Bash with zero dependencies beyond AWS CLI and jq.

## Tech Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| Language | Bash 4+ | Portable shell scripting, no compiled deps |
| Config | Custom YAML parser | Flat + one-level nested YAML (no Python needed) |
| Cloud | AWS CLI v2 | All EC2/EIP/Spot/Volume API calls |
| JSON | jq | AWS CLI output parsing |
| Testing | Bash + shellcheck | Mock-mode unit tests, lint checks |

## Quick Start

```bash
# Prerequisites: AWS CLI v2, jq, bash 4+

# 1. Bootstrap (checks deps, validates AWS creds)
./bootstrap.sh

# 2. Configure
cp config.example.yaml config.yaml
# Edit config.yaml — set ssh.key_path, ssh.key_name, security.group_id

# 3. Use
./bin/ec2 list
./bin/ec2 up --preset cpu-small --name dev-box
./bin/ec2 ssh dev-box

# Run tests (no AWS calls)
./tests/run_tests.sh
```

## Project Structure

```
aws/
├── bin/
│   └── ec2                     # CLI entrypoint — sources libs, routes commands
├── lib/
│   ├── core.sh                 # Config loader, YAML parser, logging, utilities
│   ├── cmd_instances.sh        # list, info, up, start, stop, terminate
│   ├── cmd_network.sh          # ssh, eip (Elastic IP management)
│   ├── cmd_spot.sh             # spot prices, history, cancel, interruption guide
│   └── cmd_cleanup.sh          # Orphan scanner (EIPs, volumes, TTL-expired)
├── presets/                    # YAML instance templates
│   ├── cpu-small.yaml          # t3.medium — dev, notebooks
│   ├── cpu-large.yaml          # c5.2xlarge — batch processing
│   ├── gpu-t4.yaml             # g4dn.xlarge — inference, light training
│   └── gpu-a10.yaml            # g5.xlarge — training, fine-tuning
├── tests/
│   ├── run_tests.sh            # Test runner (lint + unit tests)
│   ├── test_cli.sh             # CLI routing and flag parsing
│   ├── test_config.sh          # YAML parser unit tests
│   └── test_presets.sh         # Preset loading validation
├── scripts/                    # Legacy v1.0 scripts (preserved, superseded by bin/ec2)
├── config/
│   └── .env.example            # Legacy env config template
├── docs/
│   └── setup-guide.md          # Detailed setup guide for data scientists
├── config.example.yaml         # YAML config template
├── bootstrap.sh                # Dependency checker + setup wizard
└── README.md
```

## Architecture Overview

The CLI follows a **source-and-dispatch** pattern. `bin/ec2` sources all library files at startup, parses global flags, loads YAML configuration, then routes to the appropriate command function via a `case` statement.

Global state flows through environment variables (`EC2_*` for runtime flags, `CFG_*` for resolved config values, `PRESET_*` for loaded preset data). The custom YAML parser in `core.sh` handles flat and one-level nested structures — sufficient for config and presets but not arbitrary YAML. All destructive operations require confirmation prompts unless `--yes` is passed, and `--dry-run` previews any mutation without executing.

```
bin/ec2 (entrypoint)
  ├── lib/core.sh         → config, logging, YAML parser, AWS helpers
  ├── lib/cmd_instances.sh → list/info/up/start/stop/terminate
  ├── lib/cmd_network.sh   → ssh/eip
  ├── lib/cmd_spot.sh      → spot pricing/history/cancel
  └── lib/cmd_cleanup.sh   → orphan resource scanner
        │
        ├── presets/*.yaml  → instance templates (type, AMI, volume, cost)
        └── config.yaml     → user config (AWS profile, SSH, tags, defaults)
```

### Key Modules

| Module | Location | Purpose |
|--------|----------|---------|
| YAML Parser | `lib/core.sh:57` | Regex-based parser for config and presets (1-level nesting) |
| Config Loader | `lib/core.sh:111` | Reads config.yaml, sets `CFG_*` globals, applies CLI overrides |
| Instance Resolver | `lib/core.sh:287` | Maps name/ID → AWS query → tab-separated fields, filters by Project tag |
| AMI Resolver | `lib/core.sh:359` | Auto-detects latest AMI by pattern or uses explicit ID |
| Tag Builder | `lib/core.sh:398` | Generates Name, Project, Owner, ManagedBy, TTL, ExpiresAt tags |
| Cost Estimator | `lib/core.sh:457` | Hourly rate lookup from config with hardcoded fallbacks |
| Instance Up | `lib/cmd_instances.sh:184` | Full launch flow: idempotency, spot, volumes, tags, wait for IP |
| SSH | `lib/cmd_network.sh:6` | Auto-start stopped instances, user detection, bastion/ProxyJump |
| Cleanup | `lib/cmd_cleanup.sh` | Scans orphan EIPs, unattached volumes, stopped/expired instances |

## Development Guidelines

### Naming Conventions

**File naming:**
- Library files: `snake_case.sh` with `cmd_` prefix for command modules (`cmd_instances.sh`, `core.sh`)
- Presets: `kebab-case.yaml` (`cpu-small.yaml`, `gpu-t4.yaml`)
- Tests: `test_<module>.sh` (`test_cli.sh`, `test_config.sh`)
- CLI entrypoint: bare name (`ec2`)

**Code naming:**
- Exported globals: `EC2_*` screaming snake (`EC2_ROOT`, `EC2_DRY_RUN`, `EC2_MOCK`)
- Config variables: `CFG_*` screaming snake (`CFG_AWS_REGION`, `CFG_SSH_KEY_PATH`)
- Preset variables: `PRESET_*` screaming snake (`PRESET_INSTANCE_TYPE`, `PRESET_VOLUME_SIZE`)
- Public functions: `cmd_<name>` for commands (`cmd_list`, `cmd_up`, `cmd_ssh`)
- Private functions: `_<prefix>_<name>` for subcommands (`_eip_list`, `_spot_prices`)
- Help functions: `_<cmd>_help` (`_up_help`, `_eip_help`)
- Utility functions: `snake_case` (`load_config`, `resolve_instance`, `build_tags`)
- Local variables: `snake_case` with `local` keyword (`local instance_id`, `local public_ip`)

### Code Style

- **Shell dialect**: Bash 4+ with `set -euo pipefail` in every script
- **Quoting**: Always `"$var"`, never bare `$var`; single quotes for non-interpolated strings
- **Local variables**: Always declare with `local` inside functions
- **Logging**: Use `log`/`warn`/`err`/`die`/`info`/`debug` from `core.sh` — never raw `echo` for user output
- **Color output**: Gated on `[[ -t 1 ]]` (TTY detection) — no colors in piped output
- **Shellcheck**: All scripts must pass `shellcheck -S warning`; use `# shellcheck source=` directives for sourced files
- **Comments**: Section dividers use `# ── Section Name ──────` pattern

### Error Handling

- `set -euo pipefail` at the top of every script — do not remove
- `die "message"` for fatal errors (prints `[error]` to stderr, exits 1)
- `warn "message"` for non-fatal warnings (stderr)
- `dry_run_guard "action description"` prevents execution in `--dry-run` mode
- `confirm "prompt"` requires `[y/N]` input (skipped when `EC2_YES=true`)
- `terminate` requires typing the instance name/ID to confirm (not just y/n)
- Always check instance state before operations (prevent double-start, stop on terminated)

### Global State Variables

| Prefix | Meaning | Set By |
|--------|---------|--------|
| `EC2_*` | Runtime flags | CLI flag parsing in `bin/ec2` |
| `CFG_*` | Resolved config | `load_config()` in `core.sh` |
| `PRESET_*` | Loaded preset data | `load_preset()` in `core.sh` |

Key runtime variables: `EC2_ROOT`, `EC2_DRY_RUN`, `EC2_YES`, `EC2_PROFILE`, `EC2_REGION`, `EC2_MOCK`, `EC2_DEBUG`

### Adding a New Command

1. Create `cmd_<name>()` function in the appropriate `lib/cmd_*.sh` file
2. Add a `_<name>_help()` function with usage, options, and examples
3. Add routing entry in `bin/ec2` case statement (line 137+), including aliases
4. Add to `show_help()` in `bin/ec2`
5. Add tests in `tests/test_cli.sh`

### Adding a New Preset

Create `presets/<name>.yaml` with these required fields:
```yaml
name: my-preset
description: "What this preset is for"
instance_type: m5.xlarge
ami_pattern: "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
ami_owner: "099720109477"
ami_id: ""                  # Leave empty to auto-detect from pattern
volume_size: 50
root_device: /dev/sda1
ssh_user: ubuntu
spot_friendly: true
cost_per_hour: 0.192
```

## Available Commands

| Command | Description |
|---------|-------------|
| `ec2 list [--state S] [--tag T]` | List instances with optional filters |
| `ec2 info <name\|id>` | Detailed instance info with cost estimate |
| `ec2 up --preset <p> --name <n> [--spot] [--ttl-hours H] [--volume V]` | Create instance from preset |
| `ec2 start <name\|id>` | Start stopped instance, wait for IP |
| `ec2 stop <name\|id>` | Stop instance (preserves EBS) |
| `ec2 terminate <name\|id>` | Terminate (requires name confirmation) |
| `ec2 ssh <name\|id> [--print] [-L port:host:port]` | SSH with auto-start, bastion support |
| `ec2 eip list\|alloc\|assoc\|disassoc\|release` | Elastic IP lifecycle |
| `ec2 spot list\|prices\|history\|cancel\|interruption` | Spot instance management |
| `ec2 cleanup [--days N] [--release-eips] [--delete-volumes] [--terminate]` | Orphan scanner |
| `ec2 presets` | List available instance presets |

### Global Flags

`--profile PROF`, `--region REG`, `--dry-run`, `--yes`/`-y`, `--config FILE`, `--debug`, `--mock`

## Configuration

Copy `config.example.yaml` to `config.yaml` (gitignored). Required fields:

| Field | Example | Notes |
|-------|---------|-------|
| `ssh.key_path` | `~/.ssh/my-key.pem` | Path to your EC2 SSH private key |
| `ssh.key_name` | `my-key` | Key pair name registered in AWS |
| `security.group_id` | `sg-xxxxxxxx` | Security group allowing SSH (port 22) |

Optional: `aws.profile`, `aws.region`, `security.subnet_id`, `ssh.bastion_*`, `tags.*`, `defaults.*`, `costs.*`

## Testing

```bash
./tests/run_tests.sh
```

Runs four test suites in mock mode (no AWS API calls):
1. **Lint** — shellcheck on `bin/ec2` and all `lib/*.sh`
2. **Config parsing** — YAML parser unit tests (basic, nested, comments, quotes, defaults)
3. **Preset loading** — Validates all preset files load correctly
4. **CLI parsing** — Command routing, flag parsing, tag builder, cost estimation

Tests use a simple `pass()`/`fail()` assert pattern with final pass/fail counters.

## Safety Features

- `terminate` requires typing the instance name/ID to confirm
- `stop` requires `[y/N]` confirmation
- `--dry-run` previews any destructive operation
- Every command prints active AWS profile and region
- All resources tagged with `Project`, `Owner`, `ManagedBy`
- TTL tags enable automatic expiration detection via `cleanup`

## Known Limitations

- YAML parser handles flat and one-level nested structures only
- Cost estimates are approximate (on-demand us-west-2 rates)
- `cleanup` uses launch time as proxy for stop time
- `--gen-config` SSH generates a point-in-time snapshot; IPs change on restart
- Bastion with different keys requires ProxyCommand instead of ProxyJump

## Additional Resources

- @README.md — Full command cheatsheet with 70+ examples
- @docs/setup-guide.md — Comprehensive setup guide for data scientists
- @config.example.yaml — Configuration template with all options
- `scripts/` — Legacy v1.0 scripts (preserved for reference, superseded by `bin/ec2`)


## Skill Usage Guide

When working on tasks involving these technologies, invoke the corresponding skill:

| Skill | Invoke When |
|-------|-------------|
| aws-cli | Wraps AWS CLI v2 commands for EC2, EIP, and spot instance operations |
| bash | Manages Bash 4+ scripting, shell functions, error handling, and CLI patterns |
| yaml | Parses and generates YAML configuration files for presets and config management |
| aws-ec2 | Manages EC2 instance lifecycle, launching, stopping, and terminating instances |
| aws-spot | Handles spot instance pricing, history, requests, and interruption handling |
| jq | Parses and transforms JSON output from AWS CLI responses |
| aws-eip | Manages Elastic IP allocation, association, and lifecycle operations |
| shellcheck | Lints Bash scripts for syntax errors and style violations |
