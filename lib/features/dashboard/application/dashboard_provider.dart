import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/dashboard_repository.dart';
import '../domain/dashboard_snapshot.dart';

final _log = Logger('DashboardController');

/// Contrôleur AsyncNotifier du dashboard.
///
/// Charge le [DashboardSnapshot] complet en parallèle via records Dart 3
/// (required #4 — remplace le pattern `as dynamic` non type-safe).
/// Si [isLandlordOnboarding] est `true`, les 6 autres requêtes sont court-circuitées.
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

    // 2) Fan-in parallèle des 6 requêtes — types statiques préservés sans cast.
    _log.info('DashboardController: chargement parallèle KPI + activité');
    final (loyers, retards, renouvellements, docs, monthly, activity) = await (
      repo.fetchLoyersMois(),
      repo.fetchRetards(),
      repo.fetchRenouvellements(),
      repo.fetchDocsPending(),
      repo.fetchLast6MonthsAmounts(),
      // 30 : la section n'en montre que 5 repliés, « Voir tout » déplie le
      // reste sur place sans requête supplémentaire.
      repo.fetchRecentActivity(limit: 30),
    ).wait;

    return DashboardSnapshot(
      loyers: loyers,
      retards: retards,
      renouvellements: renouvellements,
      docs: docs,
      monthly: monthly,
      activity: activity,
      isOnboarding: false,
    );
  }

  /// Recharge le dashboard depuis Supabase.
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
