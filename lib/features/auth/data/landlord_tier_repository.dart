import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_session_provider.dart';
import '../domain/subscription_tier.dart';

/// Snapshot minimal des champs `landlords/{uid}` pertinents pour le tier et
/// l'expiration anonyme — délibérément séparé de [LandlordProfile]
/// (`lib/features/profile/domain/landlord_profile.dart`) car ce dernier a
/// `email`, `rgpdConsentAt` et `rgpdConsentVersion` **required**, or un doc
/// anonyme les a à `null` (aucun consentement RGPD n'a de sens pour un
/// essai sans compte). Utiliser [LandlordProfile] pour un anon ferait
/// planter la désérialisation JSON.
class LandlordTierSnapshot {
  const LandlordTierSnapshot({required this.tier, this.anonExpiresAt});

  final SubscriptionTier tier;

  /// `null` pour un compte non-anonyme. Pour un anonyme, date d'expiration
  /// glissante (14 jours depuis la dernière activité).
  final DateTime? anonExpiresAt;
}

/// Contrat testable — wrappe l'accès Firestore brut. Séparé pour permettre
/// l'injection d'un stream déterministe en test sans dépendre de
/// `FirebaseFirestore.instance` (qui nécessite `Firebase.initializeApp()`).
abstract interface class LandlordTierRepository {
  Stream<LandlordTierSnapshot?> watch(String uid);
}

class FirestoreLandlordTierRepository implements LandlordTierRepository {
  FirestoreLandlordTierRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<LandlordTierSnapshot?> watch(String uid) {
    return _firestore.doc('landlords/$uid').snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      final rawTier = data['subscriptionTier'] as String?;
      final anonExpiresAtTs = data['anonExpiresAt'] as Timestamp?;
      return LandlordTierSnapshot(
        tier: SubscriptionTier.fromRaw(rawTier),
        anonExpiresAt: anonExpiresAtTs?.toDate(),
      );
    });
  }
}

final landlordTierRepositoryProvider = Provider<LandlordTierRepository>(
  (ref) => FirestoreLandlordTierRepository(FirebaseFirestore.instance),
);

/// Flux live du tier + expiration du landlord connecté.
///
/// `null` tant qu'aucun utilisateur n'est connecté (anonyme ou non). Dérive
/// l'UID depuis [authStateChangesProvider] (et non `FirebaseAuth.instance`
/// directement) pour que ce provider soit testable via
/// `authRepositoryProvider.overrideWithValue(fake)` — même convention que
/// [sessionStateProvider] dans `auth_session_provider.dart`.
final landlordTierProvider = StreamProvider<LandlordTierSnapshot?>((ref) {
  final asyncUser = ref.watch(authStateChangesProvider);
  final uid = asyncUser.valueOrNull?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(landlordTierRepositoryProvider).watch(uid);
});
