# YAML Patterns Reference

## Contents
- Parser Architecture
- Value Handling Patterns
- Config Structure Pattern
- Preset Structure Pattern
- Anti-Patterns and Gotchas
- Edge Cases

## Parser Architecture

The parser (`lib/core.sh:57-109`) is a line-by-line state machine with three regex branches:

```
Line → strip \r → skip blank/comment → strip inline comment → match:
  1. Section header:  ^([a-zA-Z_][a-zA-Z0-9_]*):$     → set section
  2. Indented pair:   ^[[:space:]]+([key]):(.+)$        → emit section_key=value
  3. Top-level pair:  ^([key]):(.+)$                    → emit key=value, reset section
```

All emitted values go through: left-trim → right-trim → outer-quote-strip.

## Value Handling Patterns

### DO: Use explicit empty strings

```yaml
# GOOD — ami_id: "" parses as empty string, triggers auto-detect
ami_id: ""
bastion_host: ""
```

### WARNING: Bare colon creates a section header

```yaml
# BAD — treated as section header, not empty value
ami_id:

# GOOD — explicit empty string
ami_id: ""
```

**Why this breaks:** The regex `^([a-zA-Z_][a-zA-Z0-9_]*):$` matches before the key-value regex. Subsequent keys would be prefixed with `ami_id_` as if it were a section.

### DO: Use underscores in key names

```yaml
# GOOD — matches [a-zA-Z_][a-zA-Z0-9_]*
cost_per_hour: 0.192
ami_pattern: "ubuntu/images/hvm-ssd/*"

# BAD — silently dropped, hyphens not in character class
cost-per-hour: 0.192
ami-pattern: "ubuntu/images/hvm-ssd/*"
```

### DO: Quote values containing special characters

```yaml
# GOOD — quotes stripped, value preserved
description: "Small CPU instance for light data science work"
ami_pattern: "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"

# ALSO GOOD — unquoted values without # work fine
instance_type: t3.medium
volume_size: 20
```

### WARNING: Inline comments with quoted values

```yaml
# BAD — inline comment NOT stripped when line contains quotes
description: "my instance" # this stays in the value

# GOOD — no inline comments on quoted lines
description: "my instance"
```

**Why this breaks:** The parser disables inline comment stripping for any line containing `"` or `'` (core.sh:66-68). The value becomes `"my instance" # this stays in the value`, and the outer-quote regex `^\"(.*)\"$` fails to match because the string doesn't end with a quote.

## Config Structure Pattern

Config uses one-level nesting. Each section becomes a prefix:

```yaml
aws:                          # section="aws"
  profile: default            # → aws_profile=default
  region: us-west-2           # → aws_region=us-west-2

ssh:                          # section="ssh"
  key_path: ~/.ssh/key.pem    # → ssh_key_path=~/.ssh/key.pem
  key_name: my-key            # → ssh_key_name=my-key

security:                     # section="security"
  group_id: sg-xxxxxxxx       # → security_group_id=sg-xxxxxxxx
  subnet_id: ""               # → security_subnet_id=

tags:                         # section="tags"
  Project: aws-setup          # → tags_Project=aws-setup  (case-sensitive!)
  Owner: me                   # → tags_Owner=me
```

### WARNING: Case sensitivity in tag keys

```yaml
# The parser preserves case. load_config looks up tags_Project (capital P).
# BAD — silent fallback to default
tags:
  project: aws-setup

# GOOD — matches _cfg_get lookup
tags:
  Project: aws-setup
```

## Preset Structure Pattern

Presets are flat — no sections, no nesting:

```yaml
name: gpu-t4
description: "NVIDIA T4 GPU instance"
instance_type: g4dn.xlarge
ami_pattern: "Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*"
ami_owner: amazon
ami_id: ""
volume_size: 100
root_device: /dev/sda1
ssh_user: ubuntu
spot_friendly: true
cost_per_hour: 0.526
post_launch_hint: "Run: nvidia-smi"
```

Required fields with defaults in `load_preset()`:

| Field | Default | Notes |
|-------|---------|-------|
| `instance_type` | `t3.medium` | Silently defaults if missing |
| `volume_size` | `20` | String, not integer |
| `ssh_user` | `ubuntu` | Used for SSH connections |
| `spot_friendly` | `false` | Must be `true` or `false` |
| `ami_owner` | `099720109477` | Canonical Ubuntu; use `amazon` for DL AMIs |

## Anti-Patterns and Gotchas

### WARNING: Multiline values are silently ignored

```yaml
# BAD — block scalar lines after | are dropped
gpu_setup_userdata: |
  #!/bin/bash
  apt-get update
  apt-get install -y nvidia-driver

# The gpu_setup_userdata key itself is parsed (value: empty after |)
# but all continuation lines are silently dropped.
```

**Real impact:** The `gpu_setup_userdata` field in `presets/gpu-t4.yaml` and `presets/gpu-a10.yaml` is dead data — never consumed by `load_preset()`.

### WARNING: No validation of required fields

```yaml
# This preset will silently use defaults for everything
name: broken-preset
# No instance_type → defaults to t3.medium
# No volume_size → defaults to 20
# No ssh_user → defaults to ubuntu
```

**Why this matters:** A typo like `instnace_type: g4dn.xlarge` silently falls through to the default `t3.medium`. The parser does not warn about unrecognized keys.

## Edge Cases

| Input | Parser Output | Notes |
|-------|--------------|-------|
| `key: value with spaces` | `key=value with spaces` | Spaces preserved |
| `key: "quoted value"` | `key=quoted value` | Outer quotes stripped |
| `key: 'single quoted'` | `key=single quoted` | Single quotes stripped |
| `key: val=ue` | `key=val=ue` | `=` in value preserved correctly |
| `key: 0.0416` | `key=0.0416` | Numbers are strings |
| `key: true` | `key=true` | Booleans are strings |
| `key: ""` | `key=` | Empty after quote strip |
| Windows CRLF | Handled | `\r` stripped on every line |