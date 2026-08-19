---
description: Self-check that every workflow file is well-formed and every {TOKEN} resolves in config.md
version: 1.0.0
last_updated: 2026-08-19
---

# /validate-workflows

## Purpose
Meta-check on the `.agents/` system itself — catch broken references before they waste a session.

## Steps
1. For every `.md` file under `.agents/workflows/`, confirm it has: YAML frontmatter with `description`,
   `version`, `last_updated`; a `## Purpose` section; numbered `## Steps`; a Completion Report template.
2. Grep every workflow + `AGENTS.md` + `CLAUDE.md` for `{TOKEN}`-style placeholders; confirm each one is
   defined in `.agents/config.md`'s Path Variables table.
3. Confirm `00-INDEX.md` links to every workflow file present on disk and vice versa (no orphaned files, no
   dead links).
4. Confirm the Module Registry in `config.md` matches the actual folders under `lib/features/` (catches
   new/removed feature folders that haven't been registered).

## Completion Report Template
```
Workflows checked: N
Malformed (missing required section): [list or none]
Unresolved {TOKEN} references: [list or none]
Index/file mismatch: [list or none]
Module Registry drift vs lib/features/: [list or none]
```
