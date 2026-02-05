# AWS CLI Patterns Reference

## Contents
- aws_cmd Wrapper
- JMESPath Query Patterns
- Filter Patterns
- Output Parsing
- Tag Operations
- Error Handling Anti-Patterns

---

## aws_cmd Wrapper

All AWS calls go through `aws_cmd` (`lib/core.sh:226`), which prepends `--profile` and `--region`:

```bash
aws_cmd() {
  local cmd=(aws)
  if [[ -n "$CFG_AWS_PROFILE" ]]; then
    cmd+=(--profile "$CFG_AWS_PROFILE")
  fi
  if [[ -n "$CFG_AWS_REGION" ]]; then
    cmd+=(--region "$CFG_AWS_REGION")
  fi
  "${cmd[@]}" "$@"
}
```

### WARNING: Calling `aws` Directly

```bash
# BAD — ignores user's profile and region config
aws ec2 describe-instances --output json
```

**Why this breaks:** User sets `--profile work` or `--region eu-west-1` on the CLI, and the command silently queries the wrong account or region. Every raw `aws` call is a potential data/billing leak to the wrong account.

```bash
# GOOD — always route through aws_cmd
aws_cmd ec2 describe-instances --output json
```

---

## JMESPath Query Patterns

### Extract a Name Tag

Name tags require a filter expression because Tags is an array of `{Key, Value}` objects:

```bash
# Extract Name tag from Tags array
--query '(Tags[?Key==`Name`].Value)[0]'

# In a multi-field projection
--query 'Reservations[].Instances[].[(Tags[?Key==`Name`].Value)[0], InstanceId, State.Name]'
```

### Sort and Pick Latest

```bash
# Latest AMI by creation date
--query 'Images | sort_by(@, &CreationDate) | [-1].[ImageId, Name]'
```

### Null Coalescing

```bash
# Default to "-" when field is null
--query '(.PublicIpAddress // "-")'
```

### WARNING: Forgetting `[0]` on Tag Filters

```bash
# BAD — returns array ["my-name"], not string "my-name"
--query 'Tags[?Key==`Name`].Value'

# GOOD — unwrap the single-element array
--query '(Tags[?Key==`Name`].Value)[0]'
```

**Why this breaks:** `--output text` prints the value fine, but `--output json` returns `["my-name"]` instead of `"my-name"`, and downstream jq parsing fails.

---

## Filter Patterns

### Exclude Terminated Instances

```bash
# Standard filter used in cmd_list (lib/cmd_instances.sh:24)
--filters "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down"
```

### WARNING: Using `--query` Instead of `--filters`

```bash
# BAD — downloads ALL instances then filters client-side
aws_cmd ec2 describe-instances \
  --query 'Reservations[].Instances[?State.Name==`running`]'

# GOOD — server-side filter, less data transfer
aws_cmd ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId]'
```

**Why this matters:** `--filters` are evaluated server-side by AWS. JMESPath `--query` runs after the full response arrives. For accounts with hundreds of instances, server-side filtering saves bandwidth and latency.

### Combine Multiple Filters

```bash
# Filters are AND-ed. Multiple values in one filter are OR-ed.
--filters "Name=instance-state-name,Values=running" \
          "Name=tag:Project,Values=${CFG_TAG_PROJECT}" \
          "Name=tag-key,Values=TTLHours"
```

---

## Output Parsing

### Tab-Separated Text (preferred for shell)

```bash
aws_cmd ec2 describe-instances \
  --query 'Reservations[].Instances[].[InstanceId, State.Name, PublicIpAddress]' \
  --output text | while IFS=$'\t' read -r id state ip; do
    # $id, $state, $ip are ready to use
  done
```

### JSON via jq (for complex transforms)

```bash
local result
result="$(aws_cmd ec2 describe-instances ... --output json)"
local count
count="$(printf '%s' "$result" | jq 'length')"
```

See the **jq** skill for jq patterns used in this codebase.

### WARNING: Using `--output table` for Script Consumption

```bash
# BAD — table output is for humans, not scripts
result="$(aws_cmd ec2 describe-instances --output table)"
# Parsing table output is fragile and breaks on column width changes

# GOOD — use text or json
result="$(aws_cmd ec2 describe-instances --output text)"
```

---

## Tag Operations

### Build Tag Specifications for run-instances

The codebase uses `build_tag_spec` (`lib/core.sh:429`) to generate the `--tag-specifications` format:

```bash
local tag_spec
tag_spec="$(build_tag_spec "$inst_name" "$ttl" "instance")"
local vol_tag_spec
vol_tag_spec="$(build_tag_spec "$inst_name" "$ttl" "volume")"

aws_cmd ec2 run-instances ... \
  --tag-specifications "$tag_spec" "$vol_tag_spec"
```

### Post-Creation Tagging

```bash
aws_cmd ec2 create-tags --resources "$alloc_id" \
  --tags "Key=Project,Value=${CFG_TAG_PROJECT}" \
         "Key=Owner,Value=${CFG_TAG_OWNER}" \
         "Key=ManagedBy,Value=ec2-ops-kit"
```

---

## Error Handling Anti-Patterns

### WARNING: Missing `2>/dev/null` on Non-Critical Queries

```bash
# BAD — set -e kills the script if instance doesn't exist
local ip
ip="$(aws_cmd ec2 describe-instances --instance-ids "$id" \
  --query '...' --output text)"

# GOOD — graceful fallback
ip="$(aws_cmd ec2 describe-instances --instance-ids "$id" \
  --query '...' --output text 2>/dev/null || echo "None")"
```

### WARNING: Not Capturing stderr on Mutations

```bash
# BAD — error message lost
aws_cmd ec2 run-instances ... --output json || die "Failed"

# GOOD — capture stderr for diagnostics (lib/cmd_instances.sh:371)
local output
output="$(aws_cmd ec2 run-instances ... --output json 2>&1)" \
  || die "Failed to launch instance:\n$output"
```

See the **bash** skill for `set -euo pipefail` error handling patterns.