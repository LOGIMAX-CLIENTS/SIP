# startGOLD Mobile (SIP) — Always-On Rules

> Condensed pointer, auto-loaded every session. Full rulebook: `.agents/AGENTS.md`. Path variables and the
> 23-module registry (+ brain-build status): `.agents/config.md`.

**Step Zero (mandatory before any code investigation or edit):** identify which feature module(s) under
`lib/features/` the task touches, then read that module's `knowledge_brain/{Module}/MODULE_BRAIN.md` in
full. For bug fixes, also read `knowledge_brain/_SYSTEM/DIAGNOSTIC_PLAYBOOK.md` and
`knowledge_brain/_SYSTEM/DANGER_ZONES.md` first. If a module's brain doesn't exist yet or looks stale,
say so before proceeding on assumptions. Full detail: `.agents/AGENTS.md` §0.

**Non-negotiables** (full detail in `.agents/AGENTS.md`):
- Screens never call `ApiClient` directly — go through a Controller/Notifier → Service → ApiClient.
- Sensitive fields (password, otp, mpin, pan, aadhaar_number, bank_account_number, upi_id, amounts) are
  RSA-encrypted via `core/security/encryption_service.dart` before leaving the device — never add a new
  sensitive field to a request without routing it through the existing encryption path.
- Tokens/MPIN/biometric flags live only in `flutter_secure_storage`, never `shared_preferences`.
- A `409` response always triggers `SessionManager`'s force-logout path — never swallow it.
- All routes are named constants on `AppRouter` (`lib/routes/app_router.dart`) — no hardcoded route
  strings.
- Don't invent business-rule specifics (rate-lock seconds, KYC thresholds, min/max amounts) — cite the
  actual config/constant or the module's `BUSINESS_RULES.md`.

**After any non-trivial fix**: update the touched module's `MODULE_BRAIN.md` /`METHOD_INDEX.md`/
`BUSINESS_RULES.md` so the brain doesn't go stale (`.agents/AGENTS.md` §9).

This project's `.agents/` + `knowledge_brain/` system mirrors the pattern used in the sibling
`fintect_application` repo — plain Markdown knowledge base read via normal file tools, not a vector store.
