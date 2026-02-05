---
name: aws-cli
description: |
  Wraps AWS CLI v2 commands for EC2, EIP, and spot instance operations.
  Use when: writing or modifying aws_cmd calls, building AWS CLI queries with --query/--filter, parsing AWS JSON output with jq, or adding new AWS API interactions to lib/*.sh
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# AWS CLI Skill

This project wraps every AWS API call through the `aws_cmd` helper in `lib/core.sh:226`, which injects `--profile` and `--region` from resolved config. All AWS output parsing uses **jq** (see the **jq** skill) and JMESPath `--query` expressions. The CLI never calls `aws` directly — always `aws_cmd`.

## Quick Start

### Calling AWS Through aws_cmd

```bash
# GOOD — always use aws_cmd, never bare aws
aws_cmd ec2 describe-instances \
  --filters "Name=tag:Name,Values=${identifier}" \
  --query 'Reservations[].Instances[].[InstanceId, State.Name]' \
  --output text

# BAD — bypasses profile/region injection
aws ec2 describe-instances --filters ...
```

### JMESPath Query Patterns

```bash
# Single scalar value
aws_cmd ec2 describe-instances \
  --instance-ids "$id" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text

# Tab-separated columns for shell parsing
aws_cmd ec2 describe-instances \
  --query 'Reservations[].Instances[].[InstanceId, (Tags[?Key==`Name`].Value)[0], State.Name]' \
  --output text

# Sort in JMESPath
--query 'Images | sort_by(@, &CreationDate) | [-1].ImageId'
```

## Key Concepts

| Concept | Usage | Example |
|---------|-------|---------|
| `aws_cmd` | Profile/region-aware wrapper | `aws_cmd ec2 describe-instances ...` |
| `--output text` | Tab-separated for `read -r` parsing | `IFS=$'\t' read -r id name state` |
| `--output json` | Pipe to jq for complex transforms | `jq -r '.Instances[0].InstanceId'` |
| `--query` | JMESPath server-side filtering | `'Reservations[].Instances[].[InstanceId]'` |
| `--filters` | AWS-side filtering (reduces data transfer) | `"Name=instance-state-name,Values=running"` |
| `--dry-run` (AWS) | AWS-native dry run (distinct from CLI `--dry-run`) | Only for `run-instances`, not all commands |
| `2>/dev/null \|\| echo ""` | Graceful AWS error handling | Prevents `set -e` from killing the script |

## Common Patterns

### Filter by Project Tag

Every `describe-*` call in this codebase scopes to the configured project tag:

```bash
--filters "Name=tag:Project,Values=${CFG_TAG_PROJECT}"
```

### Parse Tab-Separated Output

```bash
aws_cmd ec2 describe-instances ... --output text | \
  while IFS=$'\t' read -r id name state itype pip prip; do
    printf '%-19s %-20s %s\n' "$id" "$name" "$state"
  done
```

### Error Handling for AWS Calls

```bash
local result
result="$(aws_cmd ec2 run-instances ... --output json 2>&1)" \
  || die "Failed to launch instance:\n$result"
```

## See Also

- [patterns](references/patterns.md)
- [workflows](references/workflows.md)

## Related Skills

- See the **bash** skill for shell patterns (`set -euo pipefail`, quoting, local vars)
- See the **jq** skill for JSON output parsing
- See the **yaml** skill for config and preset parsing
- See the **shellcheck** skill for linting AWS CLI wrapper scripts