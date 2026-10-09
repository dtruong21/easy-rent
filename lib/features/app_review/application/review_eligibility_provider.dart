import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_session_provider.dart';
import '../../auth/domain/session_state.dart';
import '../../profile/application/landlord_profile_provider.dart';
import '../../properties/application/properties_list_provider.dart';
import '../data/review_solicitation_storage.dart';
import '../domain/review_eligibility.dart';

/// Horloge injectable (tests).
final reviewClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Éligibilité à la sollicitation d'avis (FEAT-060). Faux en cas d'erreur
/// de chargement (jamais de sollicitation sur une donnée incertaine).
final reviewEligibilityProvider = FutureProvider.autoDispose<bool>((ref) async {
  final full =
      ref.watch(sessionStateProvider) == SessionState.fullyAuthenticated;
  if (!full) return false;
  try {
    final profile = await ref.watch(landlordProfileProvider.future);
    final items = await ref.watch(propertiesListItemsProvider.future);
    final last = await ref
        .watch(reviewSolicitationStorageProvider)
        .readLastSolicitedAt();
    return isReviewSolicitationEligible(
      fullyAuthenticated: full,
      accountCreatedAt: profile.createdAt,
      hasProperty: items.isNotEmpty,
      lastSolicitedAt: last,
      now: ref.watch(reviewClockProvider)(),
    );
  } catch (_) {
    return false;
  }
});
