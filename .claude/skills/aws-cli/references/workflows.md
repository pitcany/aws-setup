# AWS CLI Workflows Reference

## Contents
- Instance Launch Workflow
- Instance Resolution
- AMI Auto-Detection
- Spot Instance Workflow
- Cleanup Scan Workflow
- Adding a New AWS Command

---

## Instance Launch Workflow

`cmd_up` (`lib/cmd_instances.sh:184`) follows this sequence:

1. Parse flags, load preset via `load_preset`
2. Resolve AMI (explicit ID or auto-detect from pattern)
3. **Idempotency check** — resolve existing instance by name
4. Build block device mapping JSON
5. Build `--tag-specifications` for both `instance` and `volume`
6. Call `aws_cmd ec2 run-instances`
7. Wait for public IP with `wait_for_ip`
8. Optionally create and attach extra volume

```bash
# Block device mapping built with printf to avoid nested quoting issues
local bdm
printf -v bdm '[{"DeviceName":"%s","Ebs":{"VolumeSize":%s,"VolumeType":"%s"}}]' \
  "$PRESET_ROOT_DEVICE" "$vol_size" "$CFG_DEFAULT_VOLUME_TYPE"

aws_cmd ec2 run-instances \
  --instance-type "$itype" \
  --image-id "$ami_id" \
  --key-name "$CFG_SSH_KEY_NAME" \
  --security-group-ids "$CFG_SECURITY_GROUP_ID" \
  --block-device-mappings "$bdm" \
  --tag-specifications "$tag_spec" "$vol_tag_spec"
```

### WARNING: Nested JSON Quoting in Bash Arrays

```bash
# BAD — shell splits and misquotes the JSON
run_args+=(--block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":100}}]')

# GOOD — build JSON in a variable first, then reference it
local bdm
printf -v bdm '[{"DeviceName":"%s","Ebs":{"VolumeSize":%s,"VolumeType":"%s"}}]' \
  "$device" "$size" "$vtype"
run_args+=(--block-device-mappings "$bdm")
```

**Why this breaks:** Bash word splitting corrupts JSON when it contains spaces or special characters inside array expansions.

---

## Instance Resolution

`resolve_instance` (`lib/core.sh:291`) accepts a name or `i-*` instance ID:

```bash
# Name-based lookup
--filters "Name=tag:Name,Values=${identifier}"

# ID-based lookup
--filters "Name=instance-id,Values=${identifier}"
```

`resolve_one_instance` wraps this to enforce exactly one match:

```bash
local line
line="$(resolve_one_instance "$identifier")"
local id name state itype pip prip
IFS=$'\t' read -r id name state itype pip prip <<< "$line"
```

### WARNING: Not Checking Instance State Before Operations

```bash
# BAD — start a running instance or stop a terminated one
aws_cmd ec2 start-instances --instance-ids "$id"

# GOOD — check state first (lib/cmd_instances.sh:493)
if [[ "$state" == "running" ]]; then
  info "$name ($id) is already running."
  return 0
fi
if [[ "$state" != "stopped" ]]; then
  die "Cannot start instance in state: $state"
fi
```

---

## AMI Auto-Detection

`resolve_ami` (`lib/core.sh:360`) uses describe-images with pattern matching:

```bash
aws_cmd ec2 describe-images \
  --owners "${owner_list[@]}" \
  --filters "Name=name,Values=${pattern}" "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text
```

The `sort_by + [-1]` JMESPath pattern picks the most recently published AMI matching the glob. Preset files define `ami_pattern` and `ami_owner`; explicit `ami_id` takes precedence.

---

## Spot Instance Workflow

### Creating a Spot Instance

```bash
# Spot market options JSON (lib/cmd_instances.sh:283)
--instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time"}}'
```

### Checking Spot Prices

```bash
aws_cmd ec2 describe-spot-price-history \
  --instance-types "$itype" \
  --product-descriptions "Linux/UNIX" \
  --start-time "$(date -u '+%Y-%m-%dT%H:%M:%S')" \
  --query 'SpotPriceHistory[].[AvailabilityZone, SpotPrice]' \
  --output text
```

See the **aws-spot** skill for detailed spot instance patterns.

### Cancellation Gotcha

Cancelling a spot request does NOT terminate the running instance:

```bash
aws_cmd ec2 cancel-spot-instance-requests --spot-instance-request-ids "$request_id"
# Instance still running! Must separately:
aws_cmd ec2 terminate-instances --instance-ids "$instance_id"
```

---

## Cleanup Scan Workflow

`cmd_cleanup` (`lib/cmd_cleanup.sh`) runs four scans:

1. **Orphan EIPs** — `describe-addresses` where `AssociationId==null`
2. **Unattached volumes** — `describe-volumes` with `status=available`
3. **Old stopped instances** — parses `StateTransitionReason` for stop timestamp
4. **TTL-expired instances** — compares `ExpiresAt` tag against current time

```bash
# Parsing stop time from StateTransitionReason (lib/cmd_cleanup.sh:137)
# Format: "User initiated (2024-01-15 10:30:00 GMT)"
if [[ "$reason" =~ \(([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
  local stop_ts="${BASH_REMATCH[1]}"
  stop_ts="${stop_ts/ /T}"
  ref_epoch="$(parse_iso_date "$stop_ts" 2>/dev/null || echo "0")"
fi
```

Copy this checklist when implementing cleanup changes:
- [ ] Scan runs without `--release-eips`/`--delete-volumes`/`--terminate` (read-only by default)
- [ ] Each destructive action is gated by `confirm` and `dry_run_guard`
- [ ] Untagged resources are included in scans (orphans often lack Project tags)
- [ ] Date parsing works on both macOS (BSD date) and Linux (GNU date)

---

## Adding a New AWS Command

1. Identify which `lib/cmd_*.sh` file the command belongs in
2. Create the function using `aws_cmd` for all API calls
3. Use `--query` and `--output text` for tabular display
4. Gate destructive operations with `dry_run_guard` and `confirm`
5. Add routing in `bin/ec2` case statement

Feedback loop for new commands:
1. Write the command function
2. Validate: `shellcheck -S warning lib/cmd_*.sh`
3. If shellcheck fails, fix issues and repeat step 2
4. Add test case in `tests/test_cli.sh`
5. Validate: `./tests/run_tests.sh`
6. If tests fail, fix and repeat step 5

See the **bash** skill for function naming conventions and the **shellcheck** skill for lint requirements.