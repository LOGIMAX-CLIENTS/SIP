---
last_updated: 2026-08-19
source: Synthesized from findings across module brains — not an exhaustive form-field-by-form-field sweep, see "Known Incomplete" below
---

# Validation Gaps

Fields/forms where expected validation is missing, dead, or bypassed — distinct from the encryption gaps in
`_SYSTEM/DANGER_ZONES.md` (those are transport-security gaps; these are input-correctness gaps).

| Gap | Module | Detail |
|---|---|---|
| `core/utils/kyc_validator.dart` is dead code | KYC | Zero importers — whatever validation it was meant to provide isn't happening through this class today. |
| PAN verification screen has no real validation | KYC | `/pan-verification` is a stub with a fake `Future.delayed` success and zero backend call — nothing is actually validated. |
| Nominee ID-proof fields exist in model/payload with no form UI | Nominee | `_buildDropdownField` is dead code — can't even reach the point of validating a value that's never entered. |
| Ticket-type default not in the valid-values map | Support | `'General'` isn't a `kTicketTypes` key — not a missing-validation bug exactly, but a default/allowed-values mismatch with the same practical effect (wrong data saved without user awareness). |
| Document upload claimed but not implemented | KYC | Hand-written doc describes upload capability; live flow is text-fields only, so any validation that would apply to uploaded documents doesn't exist because the upload path itself doesn't exist. |

## Known Incomplete

Module brains were built primarily to trace architecture, business rules, and security surfaces — a
dedicated field-by-field validation audit (checking every form field against `core/utils/validators.dart`
for missing coverage) was not systematically performed across all 24 modules. `/build-system-brain`'s step 6
calls for exactly this; treat this file as a starting point from incidental findings, not a completed sweep.
