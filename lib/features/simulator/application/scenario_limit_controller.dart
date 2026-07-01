import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_session_provider.dart';
import '../../auth/data/landlord_tier_repository.dart';
import '../../auth/domain/subscription_tier.dart';

/// Nombre live de scénarios sauvegardés par le landlord connecté.
///
/// Utilise `.snapshots()` (stream Firestore) et NON une lecture one-shot :
/// un onglet parallèle qui vient de créer un scénario doit voir la limite
/// enforcer en temps réel sur cet onglet-ci. Sans stream, un utilisateur
/// pouvait rester avec `count=1` en cache et bypass le gate anon en
/// sauvegardant depuis une seconde fenêtre — la scenarioCountProvider
/// précédente réutilisait `investmentScenariosListProvider` qui est un
/// AsyncNotifier one-shot, exactement ce cas.
final scenarioCountProvider = StreamProvider<int>((ref) {
  final user = ref.watch(authStateChangesProvider).valueOrNull;
  if (user == null) return Stream.value(0);
  return FirebaseFirestore.instance
      .collection('investment_scenarios')
      .where('landlordId', isEqualTo: user.uid)
      .where('deletedAt', isEqualTo: null)
      .snapshots()
      .map((snap) => snap.size);
});

/// Limite de scénarios sauvegardables pour le tier courant. `null` = illimité.
///
/// Tant que le tier n'est pas encore résolu (chargement initial), on
/// retombe sur la limite la plus restrictive ([SubscriptionTier.anonymous])
/// — fail-safe : mieux vaut bloquer temporairement un save à tort que
/// laisser un anonyme dépasser sa limite pendant un instant de chargement.
final scenarioLimitForTierProvider = Provider<int?>((ref) {
  final asyncTier = ref.watch(landlordTierProvider);
  final tier = asyncTier.valueOrNull?.tier ?? SubscriptionTier.anonymous;
  return tier.scenarioLimit;
});

/// `true` si le landlord connecté peut encore sauvegarder un nouveau
/// scénario (création — ne s'applique pas à la mise à jour d'un scénario
/// existant, qui ne change pas le compte total).
///
/// Pendant le chargement du compte ou du tier, retourne `true` par défaut
/// (évite un flash de bouton disabled) — le vrai contrôle a lieu au moment
/// du clic dans `SimulatorPage._saveScenario` via une relecture synchrone.
final canSaveAnotherScenarioProvider = Provider<bool>((ref) {
  final limit = ref.watch(scenarioLimitForTierProvider);
  if (limit == null) return true; // illimité (paid)
  final count = ref.watch(scenarioCountProvider).valueOrNull;
  if (count == null) return true;
  return count < limit;
});
