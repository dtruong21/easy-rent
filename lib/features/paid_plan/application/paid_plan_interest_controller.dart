import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/paid_plan_interest_repository.dart';

final _log = Logger('PaidPlanInterestController');

/// Clé enregistrée dans `paid_plan_interest.features` quand l'utilisateur
/// se dit intéressé pour participer au financement du produit (bouton
/// « Participer au financement » du footer simulateur). Agrégée dans le
/// même doc que les features Plan Pro (merge côté repository).
const String fundingInterestKey = 'soutien_investisseur';

/// Clé enregistrée quand l'utilisateur clique « Me prévenir du lancement »
/// directement depuis la page `/pro` (`ProPricingPage`) — checkout Stripe
/// masqué tant que [Env.subscriptionsEnabled] (freemium MVP, cf.
/// `lib/core/config/env.dart`) vaut `false`. Utilisée pour le palier Pro
/// (seul palier réellement destiné à ouvrir avec ce gate global) — les
/// paliers Max/Ultra utilisent [proPricingInterestKeyFor], taguée par
/// palier (FEAT-056 §6/§8.1), indépendante de [Env.subscriptionsEnabled].
const String proPricingInterestKey = 'pro_pricing_page';

/// Clé de capture d'intérêt taguée par palier (FEAT-056) — enregistrée
/// quand l'utilisateur clique « Me prévenir à l'ouverture » sur une carte
/// `/pro` dont le palier n'est pas encore `purchasable` (Max/Ultra au
/// lancement, cf. `plan_matrix.g.dart#PlanLevelSpec.purchasable`). Un tag par
/// palier (`pro_pricing_max`, `pro_pricing_ultra`) permet de distinguer
/// l'intérêt pour chaque palier haut dans `paid_plan_interest.features`,
/// contrairement à [proPricingInterestKey] qui reste globale au gate
/// [Env.subscriptionsEnabled].
String proPricingInterestKeyFor(String levelId) => 'pro_pricing_$levelId';

/// Gère le clic « M'avertir du lancement » (footer simulateur + modal limite
/// atteinte tier FREE) et le signal d'intérêt de financement.
/// `AsyncValue<void>` — `data` = succès, `error` = échec affichable en
/// snackbar.
class PaidPlanInterestController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> notifyMe({required List<String> features, String? email}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(paidPlanInterestRepositoryProvider)
          .markInterest(features: features, email: email);
      _log.info('markInterest OK (features=$features)');
    });
  }

  /// Clic « Participer au financement m'intéresse » — même mécanisme que
  /// [notifyMe], sous la clé [fundingInterestKey] (aucun montant, aucun
  /// engagement : simple signal à recontacter).
  Future<void> expressFundingInterest({String? email}) =>
      notifyMe(features: const [fundingInterestKey], email: email);
}

final paidPlanInterestControllerProvider =
    AsyncNotifierProvider<PaidPlanInterestController, void>(
      PaidPlanInterestController.new,
    );
