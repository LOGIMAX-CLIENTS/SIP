---
module: kyc
---

# KYC — State Analysis

## Riverpod Providers (LIVE — `controllers/kyc_controller.dart`)

| Provider | Type | Line | Shape | Notes |
|---|---|---|---|---|
| `kycDocumentsProvider` | `FutureProvider.autoDispose.family<KycDocumentsResult, String>` (keyed by `requestFrom`) | 8-16 | `KycDocumentsResult` | Re-fetches on every `ref.refresh()` call (used deliberately after every submit to avoid stale state — `screens/kyc_screen.dart:271`). `.family` means a distinct cache entry per `requestFrom` string — switching `requestFrom` mid-session (shouldn't normally happen within one screen instance) would refetch. `.autoDispose` — state is dropped once the hub screen is popped. |
| `kycSubmitProvider` | `StateNotifierProvider<KycSubmitController, AsyncValue<bool>>` | 18-20 | `AsyncValue<bool>` | Not `.autoDispose` — persists after the screen pops until the app/provider container disposes it. Minor: could leak a stale `AsyncValue.error` into a subsequent unrelated KYC attempt in the same session if not reset, though `submit()` always sets `AsyncValue.loading()` first so this is low-risk. |
| `aadhaarProvider` | `StateNotifierProvider.autoDispose<AadhaarNotifier, AadhaarState>` | 104-107 | `AadhaarState` | `.autoDispose` — Aadhaar sub-flow state resets whenever the hub is fully torn down. |

## Riverpod Providers (LEGACY, dead — `providers/kyc_provider.dart`)

| Provider | Type | Line | Notes |
|---|---|---|---|
| `kycStepsProvider` | `StateNotifierProvider<KycNotifier, KycState>` | 68-70 | Backs the unreachable root `kyc_screen.dart`. `KycState` (steps, isLoading, error) is a plain `copyWith` value class; `KycNotifier` hardcodes 3 `KycStep`s at construction and never mutates them again (no API call anywhere in this file). |

## State Shapes

### `KycDocumentsResult` (`models/kyc_document.dart:49-61`)
```
documents: List<KycDocumentType>
aadhaarApproved: bool
aadhaarMaskedNumber: String?
aadhaarName: String?
```

### `KycDocumentType` (`models/kyc_document.dart:1-43`)
```
id: String            // from json['id_document']
name: String           // from json['document_name']
code: String
mandatory: bool
status: String
alreadyUploaded: bool   // from json['already_uploaded']
fields: List<KycField>
images: KycImagesRequirement   // PARSED BUT NEVER RENDERED — see MODULE_BRAIN §5
maskedValue: String?
verifiedName: String?
```

### `KycField` (`models/kyc_document.dart:63-84`)
```
name: String
label: String
type: String    // 'text' | 'number' | ... — drives keyboard type + numeric input-formatter branch
regex: String?  // optional server-driven validation pattern, applied at screens/kyc_screen.dart:964-967
```

### `KycImagesRequirement` (`models/kyc_document.dart:86-101`)
```
front: bool
back: bool
```
No consuming code path exists today (confirmed: no `image_picker`/`image_cropper` import anywhere under
`lib/features/kyc/`). If a future backend response sets `front`/`back` to `true`, the current UI silently
ignores it — no image capture step is offered.

### `AadhaarState` (`controllers/kyc_controller.dart:68-102`)
```
phase: AadhaarPhase   // idle | initiating | awaitingConsent | polling | approved | expired | rejected | failed
verificationId: String?
consentUrl: String?
message: String?        // sanitized, user-safe (see _sanitizeErrorMessage) — never raw exception text
maskedNumber: String?
verifiedName: String?
```
`AadhaarPhase` enum (57-66) is the sub-flow's state machine — see `DATA_FLOW.md` Flow 3 for the full
transition diagram in prose.

### `KycStep` / `KycStatus` (`models/kyc_step.dart`) — legacy only
```
enum KycStatus { pending, submitted, verified, rejected }
KycStep { id, title, description, icon, status, route }
```

## Repository Contract (`KycRepository`)

Not a Riverpod state holder itself — a stateless class (`kycRepositoryProvider = Provider((ref) =>
KycRepository())`, `kyc_repository.dart:7`) that talks to `ApiClient` and either returns a parsed value or
throws `Exception(serverMessage)`. No retry/backoff logic lives here — `pollUntilTerminal`'s retry loop lives
one layer up in `AadhaarNotifier`.

| Method | Returns | Throws |
|---|---|---|
| `getDocumentTypes` | `KycDocumentsResult` | `Exception` with server `message` on `success != true` |
| `uploadKyc` | `bool` (always `true` on success path) | `Exception` with extracted server error message |
| `initiateAadhaar` / `pollAadhaar` | `Map<String, dynamic>` (raw `data` payload — caller branches on `status`) | `Exception` with extracted server error message |
| `updateProfileName` | `void` | `Exception` with extracted server error message |

## Secure-Storage / Local Persistence

**None.** This module does not read or write `flutter_secure_storage` or `shared_preferences` directly —
all KYC status lives server-side and is fetched fresh via `kyc/document-types` each time the hub loads
(`.autoDispose`, no caching layer). The only "cache" is Riverpod's own in-memory provider state for the
lifetime of the screen. `Profile`'s `kycStatus` int (separate module) IS cached in the profile model's
in-memory state via `profileProvider`, refreshed on-demand by `KycVerificationFlow.start()`.

## Form/Controller Lifecycle (`screens/kyc_screen.dart`)

`_docControllers: Map<String, Map<String, TextEditingController>>` and `_docFormKeys: Map<String,
GlobalKey<FormState>>` are keyed by document id, built lazily in `_initControllers()` (96-121) and disposed
in `dispose()` (64-73). `_completedDocIds`/`_submittingDocIds` are plain `Set<String>` local widget state
(not Riverpod) — per-doc UI state (verified banner vs. form vs. spinner) that doesn't need to survive a
screen pop.
