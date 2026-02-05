# jq Patterns Reference

## Contents
- Field Extraction with Null Safety
- Tag Lookup Pattern
- Array-to-TSV for Shell Loops
- Array Aggregation
- String Interpolation for Formatted Output
- Anti-Patterns

---

## Field Extraction with Null Safety

Every AWS field can be `null` (stopped instances have no `PublicIpAddress`, terminated instances lose most fields). ALWAYS use `//` fallback.

```bash
# GOOD — null-safe extraction
local lifecycle
lifecycle="$(printf '%s' "$inst" | jq -r '.InstanceLifecycle // "on-demand"')"
```

```bash
# BAD — crashes or prints "null" literal when field is absent
lifecycle="$(printf '%s' "$inst" | jq -r '.InstanceLifecycle')"
```

**Why this matters:** A bare `.InstanceLifecycle` returns the string `null` (not empty) when the field is missing. Your script then compares `"null" == "spot"` and silently does the wrong thing. The `//` operator returns the fallback value when the left side is `null` or `false`.

---

## Tag Lookup Pattern

AWS tags are `[{Key: "...", Value: "..."}]` arrays. The codebase uses a consistent pattern to extract a tag by key with fallback:

```bash
# Extract Name tag, default to "<unnamed>"
(.Tags // [] | map(select(.Key == "Name")) | .[0].Value // "<unnamed>")
```

Breakdown:
- `.Tags // []` — handle missing Tags array
- `map(select(.Key == "Name"))` — filter to matching tags
- `.[0].Value` — take first match
- `// "<unnamed>"` — fallback if no match

This pattern appears in `lib/cmd_instances.sh:59` for list output and `lib/cmd_instances.sh:168` for tag display.

### WARNING: Don't Use `first()` or `limit()`

```bash
# BAD — first() errors on empty array
(.Tags | map(select(.Key == "Name")) | first .Value)

# GOOD — .[0] returns null on empty array, caught by //
(.Tags // [] | map(select(.Key == "Name")) | .[0].Value // "<unnamed>")
```

---

## Array-to-TSV for Shell Loops

The primary pattern for multi-field extraction into bash variables. Used in `lib/cmd_instances.sh:57-67` for instance listing.

```bash
printf '%s' "$result" | jq -r '.[] |
  [
    (.Tags // [] | map(select(.Key == "Name")) | .[0].Value // "<unnamed>"),
    .InstanceId,
    .State.Name,
    .InstanceType,
    (.PublicIpAddress // "-"),
    (.PrivateIpAddress // "-"),
    .Placement.AvailabilityZone,
    (.LaunchTime // "-")
  ] | @tsv' | while IFS=$'\t' read -r name id state itype pip prip az launch; do
  # Process each row
  printf '%-20s %-19s\n' "$name" "$id"
done
```

**Rules:**
1. Array construction `[...]` wraps all fields — required for `@tsv`
2. Field order in `[...]` must match `read` variable order exactly
3. `IFS=$'\t'` is critical — fields may contain spaces
4. `-r` on jq prevents quoted output; `-r` on `read` prevents backslash interpretation

### WARNING: Don't Use `@csv` for Shell Consumption

```bash
# BAD — @csv adds quotes, commas in values break parsing
printf '%s' "$result" | jq -r '.[] | [.Name, .Id] | @csv'

# GOOD — @tsv is clean for shell read
printf '%s' "$result" | jq -r '.[] | [.Name, .Id] | @tsv'
```

**Why:** `@csv` wraps strings in double-quotes and escapes internal quotes. Parsing CSV in bash is fragile. `@tsv` produces clean tab-separated output that `IFS=$'\t' read` handles correctly.

---

## Array Aggregation

Collect array elements into a single string. Used in `lib/cmd_instances.sh:134` for security groups.

```bash
# Join all security group IDs with comma
local sg
sg="$(printf '%s' "$inst" | jq -r '[.SecurityGroups[].GroupId] | join(", ") // "-"')"
```

**Pattern:** `[.array[].field] | join(separator)`
- Wrap in `[...]` to collect iterator output into an array
- `join()` concatenates with separator
- `// "-"` handles empty arrays (join returns `""`, not `null`, so this catches empty strings)

---

## String Interpolation for Formatted Output

Used for multi-line formatted display. See `lib/cmd_instances.sh:168` (tags) and `:175` (volumes).

```bash
# Format tags as indented key=value pairs
local tags
tags="$(printf '%s' "$inst" | jq -r '(.Tags // [])[] | "    \(.Key) = \(.Value)"')"

# Format volume mappings
local vols
vols="$(printf '%s' "$inst" | jq -r '(.BlockDeviceMappings // [])[] |
  "    \(.DeviceName)  \(.Ebs.VolumeId // "-")  \(.Ebs.Status // "-")"')"
```

**Key points:**
- `\(expr)` inside a jq string evaluates the expression
- Apply `// fallback` inside the interpolation for nested nullable fields
- Result is multi-line; each array element produces one line

---

## Anti-Patterns

### WARNING: Using `echo` Instead of `printf '%s'`

**The Problem:**

```bash
# BAD — echo interprets escape sequences, adds trailing newline inconsistently
local id
id="$(echo "$json" | jq -r '.InstanceId')"
```

**Why This Breaks:**
1. `echo` interprets `\n`, `\t`, `\\` in some shells — corrupts JSON with backslashes
2. Behavior differs between bash/zsh/dash
3. `echo -n` is not portable

**The Fix:**

```bash
# GOOD — printf '%s' is portable and literal
local id
id="$(printf '%s' "$json" | jq -r '.InstanceId')"
```

### WARNING: Multiple jq Calls on the Same Object

**The Problem:**

```bash
# BAD — 8 separate jq invocations parsing the same JSON
az="$(printf '%s' "$inst" | jq -r '.Placement.AvailabilityZone // "-"')"
launch="$(printf '%s' "$inst" | jq -r '.LaunchTime // "-"')"
ami="$(printf '%s' "$inst" | jq -r '.ImageId // "-"')"
```

**Why This Matters:**
Each `jq` call spawns a new process and re-parses the JSON. For the `cmd_info` function in `lib/cmd_instances.sh:131-138`, this means 8 process spawns for one instance.

**The Fix (if refactoring):**

```bash
# BETTER — single jq call, @tsv output
read -r az launch ami sg subnet vpc key lifecycle < <(
  printf '%s' "$inst" | jq -r '[
    (.Placement.AvailabilityZone // "-"),
    (.LaunchTime // "-"),
    (.ImageId // "-"),
    ([.SecurityGroups[].GroupId] | join(", ") // "-"),
    (.SubnetId // "-"),
    (.VpcId // "-"),
    (.KeyName // "-"),
    (.InstanceLifecycle // "on-demand")
  ] | @tsv'
)
```

**When You Might Be Tempted:** When adding "just one more field" to an existing block of individual extractions. The single-field pattern is simpler to read and modify, which is why the codebase uses it for `cmd_info`. For hot paths (listing hundreds of instances), consolidate into a single `@tsv` call.

### WARNING: Forgetting `-r` Flag

```bash
# BAD — returns "i-0abc123" (with quotes)
id="$(printf '%s' "$json" | jq '.InstanceId')"

# GOOD — returns i-0abc123 (raw string)
id="$(printf '%s' "$json" | jq -r '.InstanceId')"
```

**Consequence:** Your shell variable contains literal quote characters. String comparisons fail, AWS CLI calls fail with `"i-0abc123"` instead of `i-0abc123`.
