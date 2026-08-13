import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../expenses/data/expenses_repository.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/domain/expense_category.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_snapshot.dart';
import '../domain/monthly_cashflow.dart';
import 'chart_period_provider.dart';

final _log = Logger('DashboardController');

/// Contrôleur AsyncNotifier du dashboard.
///
/// Charge le [DashboardSnapshot] complet en parallèle via records Dart 3
/// (required #4 — remplace le pattern `as dynamic` non type-safe).
/// Si [isLandlordOnboarding] est `true`, les 5 autres requêtes sont court-circuitées.
///
/// Le graphique « Cash-flow mensuel » est chargé séparément par
/// [monthlyCashflowProvider] : sa période est sélectionnable par l'utilisateur
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

/// Provider du cash flow mensuel réel du graphique « Cash-flow mensuel »,
/// indépendant du [dashboardProvider].
///
/// Watch [chartPeriodProvider] : changer la période ne refait QUE cette
/// requête, sans recharger les KPI ni l'activité récente (`autoDispose` —
/// pas de cache persistant nécessaire, le graphique est la seule
/// consommatrice).
///
/// Combine 2 sources indépendantes pour la période affichée :
/// - loyers encaissés, mois par mois (`DashboardRepository`, requête
///   Firestore bornée à la fenêtre de [ChartPeriod]) ;
/// - dépenses réelles **non récupérables** du landlord, **une seule requête
///   landlord-wide** (`ExpensesRepository.listAllForLandlord`, déjà cappée à
///   500 documents) filtrée et regroupée par mois côté client — jamais une
///   requête par mois affiché (coût de lecture).
///
/// Une dépense **récurrente** (FEAT-041d) compte dans CHAQUE mois où tombe
/// une de ses échéances, sans qu'aucun document supplémentaire n'existe en
/// base : l'expansion est purement locale (`Expense.occurrencesBetween`).
/// Elle est bornée des deux côtés — jamais avant la date de la dépense
/// (pas de réécriture rétroactive du graphique, cf.
/// `core/finance/expense_recurrence.dart`), jamais après sa date de fin ni
/// après le dernier mois affiché (pas de projection dans le futur).
///
/// Si la lecture des dépenses échoue (ex. environnement de test sans
/// Firebase initialisé, erreur réseau ponctuelle), le cash flow retombe
/// gracieusement sur le seul encaissé (dépenses = 0) plutôt que de faire
/// échouer tout le graphique — même compromis que `portfolioYieldProvider`
/// (`PortfolioYieldSection`), les loyers encaissés restant la donnée
/// principale et bloquante.
final monthlyCashflowProvider =
    FutureProvider.autoDispose<List<MonthlyCashflow>>((ref) async {
      final repo = ref.watch(dashboardRepositoryProvider);
      final period = ref.watch(chartPeriodProvider);
      final months = period.months;
      _log.info('monthlyCashflowProvider: fetch $months mois');

      final rent = await repo.fetchLastMonthsCollectedRent(months);

      var expenseCentsByMonth = const <String, int>{};
      var expenseCountByMonth = const <String, int>{};
      try {
        final now = DateTime.now();
        final startMonth = DateTime(now.year, now.month - (months - 1), 1);
        // Borne haute de l'expansion : le premier instant du mois suivant.
        // Les échéances au-delà ne peuvent de toute façon alimenter aucune
        // barre (le graphique s'arrête au mois courant), mais borner
        // explicitement évite de dérouler une récurrence sans fin.
        final endMonth = DateTime(now.year, now.month + 1, 1);
        final expenses = await ref
            .watch(expensesRepositoryProvider)
            .listAllForLandlord();
        final cents = <String, int>{};
        final counts = <String, int>{};
        for (final expense in expenses) {
          if (expense.category != ExpenseCategory.nonRecoverable) continue;
          for (final occurrence in expense.occurrencesBetween(
            startMonth,
            endMonth,
          )) {
            final key = _monthKey(occurrence.year, occurrence.month);
            cents[key] = (cents[key] ?? 0) + expense.amountCents;
            counts[key] = (counts[key] ?? 0) + 1;
          }
        }
        expenseCentsByMonth = cents;
        expenseCountByMonth = counts;
      } catch (e, st) {
        _log.warning(
          'monthlyCashflowProvider: dépenses non récupérables '
          'indisponibles, repli sur le seul encaissé',
          e,
          st,
        );
      }

      return [
        for (final r in rent)
          MonthlyCashflow(
            year: r.year,
            month: r.month,
            collectedRentCents: r.collectedCents,
            nonRecoverableExpenseCents:
                expenseCentsByMonth[_monthKey(r.year, r.month)] ?? 0,
            hasData:
                r.hasPayments ||
                (expenseCountByMonth[_monthKey(r.year, r.month)] ?? 0) > 0,
          ),
      ];
    });

/// Clé `"YYYY-MM"` — même format que `dashboard_repository.dart` (fichiers
/// distincts, pas de partage d'utilitaire pour une fonction d'une ligne).
String _monthKey(int year, int month) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
