import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firestore_provider.dart';
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
  const LandlordTierSnapshot({
    required this.tier,
    this.anonExpiresAt,
    this.proWillRenew,
    this.proExpiresAt,
    this.proStore,
    this.proEntitlementActive,
  });

  final SubscriptionTier tier;

  /// `null` pour un compte non-anonyme. Pour un anonyme, date d'expiration
  /// glissante (14 jours depuis la dernière activité).
  final DateTime? anonExpiresAt;

  /// FEAT-044f — `true` si l'abonnement Pro se renouvellera automatiquement
  /// à `proExpiresAt`, `false` si une résiliation est programmée (l'accès
  /// Pro court jusqu'à `proExpiresAt` puis repasse Gratuit), `null` si le
  /// champ n'a jamais été écrit (compte non-Pro, ou Pro antérieur à
  /// FEAT-044c). Écrit par `revenuecat_webhook.ts` / `reconcile_entitlements.ts`
  /// — jamais par le client.
  final bool? proWillRenew;

  /// FEAT-044f — date de fin d'accès Pro courante (fin de la période payée
  /// en cours, que l'abonnement se renouvelle ou non). `null` si jamais
  /// écrit.
  final DateTime? proExpiresAt;

  /// FEAT-044f — origine de l'abonnement Pro (`'web'`, `'app_store'`,
  /// `'play_store'`, ou `null` si inconnu/non applicable). Détermine si
  /// `/profile` propose la résiliation in-app (web) ou un simple message
  /// (mobile — géré par le store, hors périmètre v1).
  final String? proStore;

  /// FEAT-044f — miroir brut de `proEntitlementActive` (Firestore) : `true`
  /// tant que l'accès Pro court (indépendamment de `proWillRenew`), `null`
  /// si jamais écrit. Le [tier] (`subscriptionTier`) reste la source de
  /// vérité pour le gating — ce champ n'est exposé que pour un usage futur
  /// diagnostique/affichage, non consommé par [SubscriptionSection] v1.
  final bool? proEntitlementActive;
}

/// Contrat testable — wrappe l'accès Firestore brut. Séparé pour permettre
/// l'injection d'un stream déterministe en test sans dépendre de
/// [firestoreProvider] (qui nécessite `Firebase.initializeApp()`).
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
      final proExpiresAtTs = data['proExpiresAt'] as Timestamp?;
      return LandlordTierSnapshot(
        tier: SubscriptionTier.fromRaw(rawTier),
        anonExpiresAt: anonExpiresAtTs?.toDate(),
        proWillRenew: data['proWillRenew'] as bool?,
        proExpiresAt: proExpiresAtTs?.toDate(),
        proStore: data['proStore'] as String?,
        proEntitlementActive: data['proEntitlementActive'] as bool?,
      );
    });
  }
}

final landlordTierRepositoryProvider = Provider<LandlordTierRepository>(
  (ref) => FirestoreLandlordTierRepository(ref.watch(firestoreProvider)),
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
