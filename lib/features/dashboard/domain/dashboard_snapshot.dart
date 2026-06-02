import 'package:freezed_annotation/freezed_annotation.dart';

import 'activity_item.dart';
import 'dashboard_kpi.dart';
import 'monthly_amount.dart';

part 'dashboard_snapshot.freezed.dart';

/// Snapshot complet du dashboard bailleur.
///
/// Agrège les 4 KPI, les montants mensuels (6 mois), l'activité récente (5 items)
/// et l'indicateur d'onboarding.
///
/// [isOnboarding] est `true` quand le bailleur n'a aucun bien, locataire ni bail.
/// Dans ce cas, les 4 KPI et le barchart sont vides — on affiche l'onboarding.
@freezed
class DashboardSnapshot with _$DashboardSnapshot {
  const factory DashboardSnapshot({
    required LoyersMoisKpi loyers,
    required RetardsKpi retards,
    required RenouvellementsKpi renouvellements,
    required DocsPendingKpi docs,
    required List<MonthlyAmount> monthly,
    required List<ActivityItem> activity,
    required bool isOnboarding,
  }) = _DashboardSnapshot;

  /// Factory "vide" pour l'état onboarding.
  ///
  /// Évite de passer des zéros partout depuis le provider.
  factory DashboardSnapshot.empty({required bool isOnboarding}) =>
      DashboardSnapshot(
        loyers: const LoyersMoisKpi(encaissedCents: 0, dueCents: 0),
        retards: const RetardsKpi(count: 0),
        renouvellements: const RenouvellementsKpi(count: 0),
        docs: const DocsPendingKpi(count: 0),
        monthly: const [],
        activity: const [],
        isOnboarding: isOnboarding,
      );
}
