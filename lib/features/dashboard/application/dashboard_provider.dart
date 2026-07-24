import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/dashboard_repository.dart';
import '../domain/dashboard_snapshot.dart';
import '../domain/monthly_amount.dart';
import 'chart_period_provider.dart';

final _log = Logger('DashboardController');

/// Contrôleur AsyncNotifier du dashboard.
///
/// Charge le [DashboardSnapshot] complet en parallèle via records Dart 3
/// (required #4 — remplace le pattern `as dynamic` non type-safe).
/// Si [isLandlordOnboarding] est `true`, les 5 autres requêtes sont court-circuitées.
///
/// Le graphique « Loyers » (montants mensuels) est chargé séparément par
/// [monthlyAmountsProvider] : sa période est sélectionnable par l'utilisateur
/// et un changement de période ne doit PAS recharger les KPI/activité.
///
/// Expose [refresh] pour un pull-to-refresh manuel.
class DashboardController extends AsyncNotifier<DashboardSnapshot> {
  @override
  Future<DashboardSnapshot> build() async {
    final repo = ref.watch(dashboardRepositoryProvider);

    // 1) Test onboarding — court-circuit si vrai.
    final isOnboarding = await repo.isLandlordOnboarding();
    if (isOnboarding) {
      _log.info('Landlord en onboarding — skip KPI queries');
      return DashboardSnapshot.empty(isOnboarding: true);
    }

    // 2) Fan-in parallèle des 5 requêtes — types statiques préservés sans cast.
    _log.info('DashboardController: chargement parallèle KPI + activité');
    final (loyers, retards, renouvellements, docs, activity) = await (
      repo.fetchLoyersMois(),
      repo.fetchRetards(),
      repo.fetchRenouvellements(),
      repo.fetchDocsPending(),
      // 30 : la section n'en montre que 5 repliés, « Voir tout » déplie le
      // reste sur place sans requête supplémentaire.
      repo.fetchRecentActivity(limit: 30),
    ).wait;

    return DashboardSnapshot(
      loyers: loyers,
      retards: retards,
      renouvellements: renouvellements,
      docs: docs,
      activity: activity,
      isOnboarding: false,
    );
  }

  /// Recharge le dashboard depuis Firestore.
  ///
  /// Utilisé par [RefreshIndicator] et le bouton "Réessayer".
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }
}

/// Provider du dashboard.
final dashboardProvider =
    AsyncNotifierProvider<DashboardController, DashboardSnapshot>(
      DashboardController.new,
    );

/// Provider des montants mensuels du graphique « Loyers », indépendant du
/// [dashboardProvider].
///
/// Watch [chartPeriodProvider] : changer la période ne refait QUE cette
/// requête, sans recharger les KPI ni l'activité récente (`autoDispose` —
/// pas de cache persistant nécessaire, le graphique est la seule
/// consommatrice).
final monthlyAmountsProvider = FutureProvider.autoDispose<List<MonthlyAmount>>((
  ref,
) async {
  final repo = ref.watch(dashboardRepositoryProvider);
  final period = ref.watch(chartPeriodProvider);
  _log.info('monthlyAmountsProvider: fetch ${period.months} mois');
  return repo.fetchLastMonthsAmounts(period.months);
});
