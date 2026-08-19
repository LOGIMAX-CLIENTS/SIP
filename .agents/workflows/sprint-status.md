---
description: Summarize in-flight work across modules for a status update
version: 1.0.0
last_updated: 2026-08-19
---

# /sprint-status

## Purpose
Quick cross-module status roll-up, sourced from brain `COVERAGE_TRACKER.md` round history and any
uncommitted/recent changes (`git status`/`git log` if this becomes a git repo).

## Steps
1. Read every module's `COVERAGE_TRACKER.md` — note last-touched date and coverage trend.
2. If under git, summarize commits since the last status report per module.
3. Note any module flagged with open risks in its `MODULE_BRAIN.md` risks section.
4. Produce a short table: module, brain coverage, last activity, open risks.

## Completion Report Template
```
| Module | Coverage | Last Activity | Open Risks |
|---|---|---|---|
| ... | ... | ... | ... |
```
