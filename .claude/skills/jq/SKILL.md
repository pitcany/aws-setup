All three jq skill files have been created:

**`.claude/skills/jq/SKILL.md`** — Overview of jq usage in the codebase, key operators table, project conventions (always `-r`, always `//` fallback, `printf '%s'` not `echo`, `@tsv` for shell loops), and links to references.

**`.claude/skills/jq/references/patterns.md`** — Six patterns with real code from the codebase:
- Field extraction with null safety (`// "-"`)
- Tag lookup pattern (`map(select(.Key == "Name"))`)
- Array-to-TSV for shell `while read` loops
- Array aggregation with `join()`
- String interpolation with `\(.field)`
- Three anti-patterns: `echo` vs `printf`, multiple jq calls on same object, missing `-r` flag

**`.claude/skills/jq/references/workflows.md`** — Decision guide and workflows:
- When to use jq vs `--query` (JMESPath) decision table
- Step-by-step checklist for adding a new field to instance output
- Debugging jq filters incrementally
- Testing with mock JSON (including stopped/null edge cases)
- Integration patterns: store-and-extract, conditional branching on `length`, post-launch ID validation