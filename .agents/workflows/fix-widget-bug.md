---
description: Fix UI/widget-layer bugs — layout, state binding, navigation, rendering
version: 1.0.0
last_updated: 2026-08-19
---

# /fix-widget-bug

## Purpose
Fix bugs confined to the presentation layer — the underlying data/state is correct but the widget tree
doesn't reflect or handle it properly.

## Steps
1. Read the screen file and the provider(s) it watches (`ref.watch`) — confirm the state itself is correct
   (add a temporary debug print / use the Riverpod inspector mentally by tracing the notifier) before
   assuming it's a widget bug.
2. Check for common causes: wrong `ref.watch` vs `ref.read` (missing rebuild), `const` widget capturing
   stale data, missing `mounted`/`context.mounted` guard after an async gap, `PopScope`/back-navigation
   misconfiguration, missing loading/error/empty state branch.
3. Apply the minimal fix — don't refactor surrounding widgets beyond what's needed.
4. Verify no regression to the security behaviors listed in `AGENTS.md` §3 if the screen is
   auth/OTP/MPIN/payment-adjacent (screenshot block, app-lock suppression, `PopScope`).

## Completion Report Template
```
File(s) changed: ...
Root cause: ...
Fix: ...
Security-adjacent screen: Yes/No — if yes, confirmed no regression to: [list]
```
