# jq Workflows Reference

## Contents
- When to Use jq vs AWS CLI --query
- Adding a New Field to Instance Output
- Debugging jq Filters
- Testing jq Filters Without AWS Calls
- Integration with Shell Functions

---

## When to Use jq vs AWS CLI --query

This codebase uses **two** JSON extraction methods. Choose the right one:

| Scenario | Use | Why |
|----------|-----|-----|
| Single field extraction | `--query` + `--output text` | One process, cleaner syntax |
| Multiple fields for shell variables | `--query` + `--output text` | Tab-separated, no jq needed |
| Complex formatting (tags, fallbacks) | `jq` | JMESPath can't do `map(select())` with fallbacks |
| Tabular output with column alignment | `jq` + `@tsv` | Better control over null handling per field |
| Count/length | `jq 'length'` | `--query 'length(...)'` is verbose |
| Iterating + string interpolation | `jq` | JMESPath has no string interpolation |

**Rule of thumb:** If every field has a simple path and no null-coalescing, use `--query`. If you need tag lookups, conditional defaults, or formatted strings, use `jq`.

### Example: --query is sufficient

```bash
# Single field — use --query
current="$(aws_cmd ec2 describe-instances \
  --instance-ids "$instance_id" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text 2>/dev/null || echo "unknown")"
```

See the **aws-cli** skill for full `--query` patterns.

### Example: jq is needed

```bash
# Tag lookup with fallback — --query can't do this cleanly
printf '%s' "$result" | jq -r '.[] |
  [
    (.Tags // [] | map(select(.Key == "Name")) | .[0].Value // "<unnamed>"),
    .InstanceId
  ] | @tsv'
```

---

## Adding a New Field to Instance Output

When adding a field to `cmd_list` or `cmd_info`:

### For `cmd_list` (tabular output)

Copy this checklist and track progress:
- [ ] Step 1: Add field to jq array in `lib/cmd_instances.sh:57-67`
- [ ] Step 2: Add matching variable to `while read` on the same line (:67)
- [ ] Step 3: Add column to `printf` format string (:73)
- [ ] Step 4: Add column header in the header line (:53-54)
- [ ] Step 5: Test with `./bin/ec2 --mock list`

**Example — adding SubnetId:**

```bash
# Step 1: Add to jq array (after .Placement.AvailabilityZone)
printf '%s' "$result" | jq -r '.[] |
  [
    (.Tags // [] | map(select(.Key == "Name")) | .[0].Value // "<unnamed>"),
    .InstanceId,
    .State.Name,
    .InstanceType,
    (.PublicIpAddress // "-"),
    (.PrivateIpAddress // "-"),
    .Placement.AvailabilityZone,
    (.SubnetId // "-"),
    (.LaunchTime // "-")
  ] | @tsv' | while IFS=$'\t' read -r name id state itype pip prip az subnet launch; do
  # Step 3: Add subnet to printf
  printf '%-20s %-19s %-12s %-14s %-15s %-15s %-12s %-24s %s\n' \
    "$name" "$id" "$state" "$itype" "$pip" "$prip" "$az" "$subnet" "$launch"
done
```

### For `cmd_info` (single instance detail)

```bash
# Add after existing field extractions in lib/cmd_instances.sh:131-138
local platform
platform="$(printf '%s' "$inst" | jq -r '.PlatformDetails // "Linux/UNIX"')"
```

Then add a display line in the info output section.

---

## Debugging jq Filters

### Step 1: Capture raw JSON

```bash
# Save AWS output to file for testing
aws ec2 describe-instances --output json > /tmp/instances.json
```

### Step 2: Test filter incrementally

```bash
# Start broad, then narrow
cat /tmp/instances.json | jq '.Reservations'
cat /tmp/instances.json | jq '.Reservations[].Instances[]'
cat /tmp/instances.json | jq '.Reservations[].Instances[] | .Tags'
cat /tmp/instances.json | jq '.Reservations[].Instances[] | (.Tags // [] | map(select(.Key == "Name")))'
```

### Step 3: Check for null fields

```bash
# Show which fields are null — critical for building // fallbacks
cat /tmp/instances.json | jq '.Reservations[].Instances[0] | to_entries | map(select(.value == null)) | from_entries'
```

### Step 4: Validate @tsv output

```bash
# Pipe through cat -A to see tabs (shown as ^I)
cat /tmp/instances.json | jq -r '.Reservations[].Instances[] | [.InstanceId, .State.Name] | @tsv' | cat -A
```

1. Run filter
2. Validate: Check output has correct number of tab-separated fields
3. If field count is wrong, check for missing `//` fallbacks causing null entries
4. Only proceed when field count matches your `read` variable count

---

## Testing jq Filters Without AWS Calls

Create test JSON matching AWS structure. The test suite (`tests/`) doesn't currently test jq filters — consider adding inline tests.

```bash
# Mock instance JSON for testing
local mock_json='{"Reservations":[{"Instances":[{
  "InstanceId":"i-mock123",
  "State":{"Name":"running"},
  "InstanceType":"t3.medium",
  "PublicIpAddress":"1.2.3.4",
  "PrivateIpAddress":"10.0.0.1",
  "Placement":{"AvailabilityZone":"us-west-2a"},
  "LaunchTime":"2026-01-15T10:30:00Z",
  "Tags":[{"Key":"Name","Value":"test-box"}],
  "SecurityGroups":[{"GroupId":"sg-abc"},{"GroupId":"sg-def"}],
  "BlockDeviceMappings":[{"DeviceName":"/dev/sda1","Ebs":{"VolumeId":"vol-123","Status":"attached"}}]
}]}]}'

# Test your filter
printf '%s' "$mock_json" | jq -r '.Reservations[].Instances[] |
  [.InstanceId, .State.Name, (.PublicIpAddress // "-")] | @tsv'
# Expected: i-mock123	running	1.2.3.4
```

### Edge case: Instance with null fields (stopped, no public IP)

```bash
local stopped_json='{"Reservations":[{"Instances":[{
  "InstanceId":"i-stopped456",
  "State":{"Name":"stopped"},
  "InstanceType":"t3.medium",
  "PublicIpAddress":null,
  "PrivateIpAddress":"10.0.0.2",
  "Tags":null,
  "SecurityGroups":[]
}]}]}'

# Verify fallbacks work
printf '%s' "$stopped_json" | jq -r '.Reservations[].Instances[] |
  [
    (.Tags // [] | map(select(.Key == "Name")) | .[0].Value // "<unnamed>"),
    (.PublicIpAddress // "-")
  ] | @tsv'
# Expected: <unnamed>	-
```

---

## Integration with Shell Functions

### Pattern: Store JSON, extract multiple times

Used in `cmd_info` (`lib/cmd_instances.sh:120+`):

```bash
# Fetch once, store in variable
local detail
detail="$(aws_cmd ec2 describe-instances --instance-ids "$id" --output json)"

# Extract root object once
local inst
inst="$(printf '%s' "$detail" | jq '.Reservations[0].Instances[0]')"

# Then extract individual fields from the stored object
local az launch ami
az="$(printf '%s' "$inst" | jq -r '.Placement.AvailabilityZone // "-"')"
launch="$(printf '%s' "$inst" | jq -r '.LaunchTime // "-"')"
ami="$(printf '%s' "$inst" | jq -r '.ImageId // "-"')"
```

**Key rule:** Extract the nested object (`.Reservations[0].Instances[0]`) into a variable first. Then all subsequent jq calls are simpler and faster — they parse a smaller JSON document.

### Pattern: Conditional logic on jq output

```bash
# Count instances, branch on result
local count
count="$(printf '%s' "$result" | jq 'length')"
if [[ "$count" -eq 0 ]]; then
  info "No instances found."
  return 0
fi
```

NEVER parse jq output with grep or regex. Use jq's own `select()`, `length`, or comparison operators to filter, then check the shell variable.

### Pattern: Extract instance ID after launch

```bash
# lib/cmd_instances.sh:374
local instance_id
instance_id="$(printf '%s' "$output" | jq -r '.Instances[0].InstanceId')"
if [[ -z "$instance_id" || "$instance_id" == "null" ]]; then
  die "Failed to extract instance ID from launch response"
fi
```

**Always validate:** Even with `-r`, a missing field returns the string `"null"`. Check for both empty and `"null"` values after extraction.
