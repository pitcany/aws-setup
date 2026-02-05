# YAML Workflows Reference

## Contents
- Adding a Config Field
- Creating a New Preset
- Testing YAML Changes
- Debugging Parser Issues
- Config-to-Variable Flow

## Adding a Config Field

### Checklist

Copy this checklist and track progress:
- [ ] Step 1: Add the field to `config.example.yaml` under the correct section
- [ ] Step 2: Add a `CFG_*` global variable with default in `lib/core.sh` (around line 36-52)
- [ ] Step 3: Add a `_cfg_get` call inside `load_config()` (around line 137-153)
- [ ] Step 4: Use `CFG_*` in the relevant command module
- [ ] Step 5: Add a test in `tests/test_config.sh`
- [ ] Step 6: Run `./tests/run_tests.sh` and verify

### Example: Adding a `defaults.max_instances` field

**Step 1 — config.example.yaml:**
```yaml
defaults:
  ttl_hours: 0
  volume_type: gp3
  max_instances: 10        # new field
```

**Step 2 — lib/core.sh globals:**
```bash
# ── Config defaults ──────
CFG_MAX_INSTANCES="10"
```

**Step 3 — load_config():**
```bash
CFG_MAX_INSTANCES="$(_cfg_get defaults_max_instances "10")"
```

Note the naming: YAML `defaults:\n  max_instances:` becomes parsed key `defaults_max_instances`, looked up by `_cfg_get`.

**Step 5 — tests/test_config.sh:**
```bash
test_max_instances() {
    local parsed
    parsed="$(parse_yaml "$test_config")"
    local val
    val="$(printf '%s\n' "$parsed" | while IFS='=' read -r k v; do
        [[ "$k" == "defaults_max_instances" ]] && printf '%s' "$v" && break
    done)"
    [[ "$val" == "10" ]] && pass "max_instances parsed" || fail "max_instances: got '$val'"
}
```

## Creating a New Preset

### Checklist

Copy this checklist and track progress:
- [ ] Step 1: Create `presets/<name>.yaml` with all required fields
- [ ] Step 2: Use underscores in all key names
- [ ] Step 3: Verify with `./bin/ec2 presets` (shows in list)
- [ ] Step 4: Add a test case in `tests/test_presets.sh`
- [ ] Step 5: Run `./tests/run_tests.sh` and verify
- [ ] Step 6: Test with `./bin/ec2 --mock up --preset <name> --name test`

### Template

```yaml
name: my-preset
description: "What this preset is for"
instance_type: m5.xlarge
ami_pattern: "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
ami_owner: "099720109477"
ami_id: ""
volume_size: 50
root_device: /dev/sda1
ssh_user: ubuntu
spot_friendly: true
cost_per_hour: 0.192
```

### Validation — iterate until pass

1. Create the preset file
2. Run: `EC2_MOCK=true ./bin/ec2 presets`
3. Verify your preset appears with correct description and instance type
4. Run: `./tests/run_tests.sh`
5. If tests fail, fix the YAML and repeat from step 2

### WARNING: Common preset mistakes

```yaml
# BAD — hyphenated key, silently dropped
ami-pattern: "ubuntu/images/*"

# BAD — bare colon, becomes section header
ami_id:

# BAD — multiline value, continuation lines dropped
user_data: |
  #!/bin/bash
  echo hello

# GOOD
ami_pattern: "ubuntu/images/*"
ami_id: ""
```

## Testing YAML Changes

Tests run in mock mode with no AWS calls. See the **shellcheck** skill for lint requirements.

### Running specific test suites

```bash
# All tests
./tests/run_tests.sh

# The test runner calls individual test functions.
# To debug a specific test, source the test file in mock mode:
EC2_MOCK=true source lib/core.sh
source tests/test_config.sh
test_nested    # run one test
```

### Writing a config parser test

```bash
test_my_feature() {
    local tmpfile
    tmpfile="$(mktemp)"
    cat > "$tmpfile" <<'EOF'
mysection:
  mykey: myvalue
  otherkey: "quoted value"
EOF
    local parsed
    parsed="$(parse_yaml "$tmpfile")"
    rm -f "$tmpfile"

    # Verify parsed output
    local val
    val="$(printf '%s\n' "$parsed" | while IFS='=' read -r k v; do
        [[ "$k" == "mysection_mykey" ]] && printf '%s' "$v" && break
    done)"
    [[ "$val" == "myvalue" ]] && pass "mykey parsed" || fail "mykey: got '$val'"
}
```

### Writing a preset loader test

```bash
test_my_preset() {
    load_preset "my-preset"
    [[ "$PRESET_INSTANCE_TYPE" == "m5.xlarge" ]] && pass "instance type" || fail "instance type: $PRESET_INSTANCE_TYPE"
    [[ "$PRESET_VOLUME_SIZE" == "50" ]] && pass "volume size" || fail "volume size: $PRESET_VOLUME_SIZE"
}
```

## Debugging Parser Issues

### Inspect raw parser output

```bash
# See exactly what parse_yaml produces
source lib/core.sh
parse_yaml config.yaml
# Output: one key=value per line
```

```bash
# Check a specific key
parse_yaml presets/gpu-t4.yaml | grep instance_type
# Output: instance_type=g4dn.xlarge
```

### Common debugging scenarios

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Key missing from output | Hyphen in key name | Replace with underscore |
| Value includes `# comment` | Inline comment on quoted line | Remove inline comment |
| Key treated as section | Bare `key:` with no value | Add `""` after colon |
| Wrong default used | Typo in key name | Check exact spelling and case |
| Empty value unexpected | `key: ""` vs missing key | Both produce empty; check `_cfg_get` default |

## Config-to-Variable Flow

```
config.yaml                    parse_yaml()              load_config()
─────────────                  ──────────                ─────────────
aws:                     →     aws_profile=default  →    CFG_AWS_PROFILE="default"
  profile: default             aws_region=us-west-2      CFG_AWS_REGION="us-west-2"
  region: us-west-2
                                                         _apply_defaults()
ssh:                     →     ssh_key_path=~/.ssh/...   ──────────────────
  key_path: ~/.ssh/...         ssh_key_name=my-key       EC2_PROFILE overrides CFG_AWS_PROFILE
                                                         EC2_REGION overrides CFG_AWS_REGION
```

```
presets/gpu-t4.yaml            parse_yaml()              load_preset()
───────────────────            ──────────                ─────────────
instance_type: g4dn.xlarge  →  instance_type=g4dn.xlarge → PRESET_INSTANCE_TYPE="g4dn.xlarge"
volume_size: 100               volume_size=100            PRESET_VOLUME_SIZE="100"
spot_friendly: true            spot_friendly=true         PRESET_SPOT_FRIENDLY="true"
```

All values are strings. Numeric comparisons in Bash require `(( ))` or `-eq`. Boolean checks use string comparison: `[[ "$PRESET_SPOT_FRIENDLY" == "true" ]]`.