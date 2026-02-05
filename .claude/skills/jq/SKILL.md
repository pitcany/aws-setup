---
name: jq
description: |
  Parses JSON output from AWS CLI commands and formats data for shell consumption.
  Use when: writing jq filters in lib/*.sh, building tabular output, handling null fields, or extracting tags.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# jq Skill

`jq` is the primary JSON parser for AWS CLI output in this project. It is used for tag lookups, null-safe field extraction, and tabular output using `@tsv`. Prefer `--query` for simple scalar fields; use `jq` for complex formatting or fallbacks.

## Quick Reference

### Key Operators and Filters

| Operator | Purpose | Example |
|----------|---------|---------|
| `.` | Identity | `.` |
| `.field` | Field access | `.InstanceId` |
| `//` | Null/false fallback | `.PublicIpAddress // "-"` |
| `[]` | Array iteration | `.Tags[]` |
| `map(select())` | Filter array | `map(select(.Key == "Name"))` |
| `join(", ")` | Join array strings | `[.SecurityGroups[].GroupId] | join(", ")` |
| `@tsv` | Tab-separated output | `[.Id, .State] | @tsv` |
| `length` | Count | `(.Tags // []) | length` |

## Project Conventions

1. **Always use raw output:** `jq -r` is required to avoid quoted strings.
2. **Always add null fallbacks:** Use `//` for every nullable field.
3. **Use `printf '%s'` for JSON:** `printf '%s' "$json" | jq ...` (never `echo`).
4. **Prefer `@tsv` for loops:** It pairs cleanly with `IFS=$'\t' read -r`.
5. **Use the tag lookup pattern:** `(.Tags // [] | map(select(.Key == "Name")) | .[0].Value // "<unnamed>")`.

## Common Patterns

### Tag Lookup with Fallback

```bash
name="$(printf '%s' "$inst" | jq -r \
  '(.Tags // [] | map(select(.Key == "Name")) | .[0].Value // "<unnamed>")')"
```

### Multi-Field Extraction for Shell Loops

```bash
printf '%s' "$result" | jq -r '.[] |
  [
    (.Tags // [] | map(select(.Key == "Name")) | .[0].Value // "<unnamed>"),
    .InstanceId,
    .State.Name,
    (.PublicIpAddress // "-")
  ] | @tsv' | while IFS=$'\t' read -r name id state ip; do
  printf '%-20s %-19s %-10s %s\n' "$name" "$id" "$state" "$ip"
done
```

## See Also

- [patterns](references/patterns.md) — Real jq filters from the codebase, anti-patterns
- [workflows](references/workflows.md) — When to use jq vs `--query`, debugging, testing

## Related Skills

- See the **bash** skill for safe shell parsing patterns
- See the **aws-cli** skill for `--query` vs `jq` usage guidance