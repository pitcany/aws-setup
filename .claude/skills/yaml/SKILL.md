---
name: yaml
description: |
  Parses and generates YAML configuration files for EC2 Ops Kit presets and config management.
  Use when: creating or editing config.yaml, preset YAML files, modifying the custom YAML parser in core.sh, or debugging config loading issues.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# YAML Skill

EC2 Ops Kit uses a **custom regex-based YAML parser** in `lib/core.sh:57` — not a standard library. It handles flat key-value pairs and one-level nesting only. All YAML in this project must conform to the parser's constraints.

## Quick Start

### Config File (one-level nesting)

```yaml
# config.yaml — sections with indented key: value pairs
aws:
  profile: default
  region: us-west-2

ssh:
  key_path: ~/.ssh/my-ec2-key.pem
  key_name: my-ec2-key
```

Parser output: `aws_profile=default`, `aws_region=us-west-2`, `ssh_key_path=~/.ssh/my-ec2-key.pem`

### Preset File (flat, no nesting)

```yaml
# presets/cpu-small.yaml — top-level key: value only
name: cpu-small
description: "Small CPU instance for light data science work"
instance_type: t3.medium
volume_size: 20
spot_friendly: true
cost_per_hour: 0.0416
```

Parser output: `name=cpu-small`, `instance_type=t3.medium`, etc.

## Key Concepts

| Concept | Rule | Example |
|---------|------|---------|
| Key names | `[a-zA-Z_][a-zA-Z0-9_]*` only — NO hyphens | `ami_pattern` not `ami-pattern` |
| Nesting | One level max — `section:` then indented `key: value` | `aws:\n  region: us-west-2` |
| Output format | `section_key=value` for nested, `key=value` for flat | `ssh_key_name=my-key` |
| Quotes | `"..."` and `'...'` are stripped from values | `"hello world"` → `hello world` |
| Empty values | Use `key: ""` — bare `key:` is treated as a section header | `ami_id: ""` |
| Comments | Full-line `# comment` works; inline `# comment` only works on unquoted lines | See patterns |

## Common Patterns

### Reading config values in Bash

```bash
# Inside load_config() — uses _cfg_get helper
CFG_AWS_REGION="$(_cfg_get aws_region "us-west-2")"
CFG_SSH_KEY_PATH="$(_cfg_get ssh_key_path "")"
```

### Reading preset values in Bash

```bash
# Inside load_preset() — uses _preset_get helper
PRESET_INSTANCE_TYPE="$(_preset_get instance_type "t3.medium")"
PRESET_VOLUME_SIZE="$(_preset_get volume_size "20")"
```

### Adding a new preset

```yaml
# presets/gpu-h100.yaml
name: gpu-h100
description: "H100 GPU for large-scale training"
instance_type: p5.48xlarge
ami_pattern: "Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*"
ami_owner: amazon
ami_id: ""
volume_size: 500
root_device: /dev/sda1
ssh_user: ubuntu
spot_friendly: true
cost_per_hour: 32.77
```

## Critical Constraints

1. **No arrays/lists** — dash-prefixed items (`- item`) are silently dropped
2. **No multiline values** — block scalars (`|`, `>`) are not parsed
3. **No deep nesting** — only `section:\n  key: value`, not three levels
4. **Keys must use underscores** — `ami_pattern` works, `ami-pattern` is silently ignored
5. **Case-sensitive tag keys** — `tags_Project` ≠ `tags_project`

## See Also

- [patterns](references/patterns.md) — Parser internals, DO/DON'T pairs, edge cases
- [workflows](references/workflows.md) — Adding config fields, creating presets, testing

## Related Skills

- See the **bash** skill for shell scripting patterns used in the parser
- See the **shellcheck** skill for linting YAML-consuming scripts
- See the **aws-cli** skill for how parsed config drives AWS CLI calls