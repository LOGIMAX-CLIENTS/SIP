import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nominee_model.dart';
import '../services/nominee_service.dart';

// ─── Service Provider ───────────────────────────────────────────────────────
final nomineeServiceProvider = Provider((ref) => NomineeService());

// ─── Nominee Details Provider ───────────────────────────────────────────────
/// Global nominee provider — cached for the session lifetime.
/// Use `ref.invalidate(nomineeDetailsProvider)` to force refresh.
final nomineeDetailsProvider = FutureProvider<NomineeDetails?>((ref) async {
  final service = ref.watch(nomineeServiceProvider);
  return service.getNomineeDetails();
});

/// Quick check: returns `true` if nominee has been added.
final hasNomineeProvider = Provider<bool>((ref) {
  final nomineeAsync = ref.watch(nomineeDetailsProvider);
  return nomineeAsync.maybeWhen(
    data: (nominee) => nominee != null && nominee.isValid,
    orElse: () => false,
  );
});

// --- Form Options Provider ----------------------------------------------
/// Fetches the relationship list and the email-mandatory setting in one call.
/// Use `ref.invalidate(nomineeFormOptionsProvider)` to force refresh.
final nomineeFormOptionsProvider =
    FutureProvider<NomineeFormOptions>((ref) async {
  final service = ref.watch(nomineeServiceProvider);
  return service.fetchFormOptions();
});

// --- Dynamic Relationship List Provider ---------------------------------
/// Relationship list from the API.
/// Falls back to the hardcoded [nomineeRelationships] list on failure.
final nomineeRelationshipsProvider =
    FutureProvider<List<NomineeRelationship>>((ref) async {
  final options = await ref.watch(nomineeFormOptionsProvider.future);
  return options.relationships;
});

/// Whether Email ID is mandatory (NOMINEE_FORM_VALIDATION). Mandatory while
/// loading or on error, so the form never starts out more lenient than the server.
final nomineeEmailMandatoryProvider = Provider<bool>((ref) {
  return ref.watch(nomineeFormOptionsProvider).maybeWhen(
        data: (options) => options.emailMandatory,
        orElse: () => true,
      );
});
