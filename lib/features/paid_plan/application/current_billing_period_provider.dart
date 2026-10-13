import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/subscription_repository.dart';

/// Périodicité (`'monthly'` | `'annual'`) facturée à l'abonné web, lue côté
/// serveur (`manageSubscription('current_plan')`, lecture seule).
///
/// À ne surveiller (`watch`) que pour un abonné web payant avec la vente
/// ouverte : chaque lecture interroge Stripe. `null` = inconnue (prix
/// historique, promo) ; l'erreur et le chargement sont traités comme
/// « inconnue » par la page, qui masque alors le bouton de passage mensuel ↔
/// annuel plutôt que d'en proposer un qui pourrait ne rien changer.
/// `autoDispose` : relu à chaque visite de `/pro`, donc juste après un
/// changement (le serveur applique le prix tout de suite).
final currentBillingPeriodProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.read(subscriptionRepositoryProvider).currentBillingPeriod(),
);
