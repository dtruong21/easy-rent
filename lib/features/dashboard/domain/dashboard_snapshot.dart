import 'package:freezed_annotation/freezed_annotation.dart';

import 'activity_item.dart';
import 'dashboard_kpi.dart';
import 'onboarding_progress.dart';

part 'dashboard_snapshot.freezed.dart';

/// Snapshot complet du dashboard bailleur.
///
/// Agrège les 3 KPI, l'activité récente (5 items) et l'indicateur
/// d'onboarding.
///
/// Le cash flow mensuel du graphique « Cash-flow mensuel » ne fait PAS
/// partie de ce snapshot : il est chargé indépendamment par
/// `monthlyCashflowProvider` (dashboard_provider.dart) pour que changer la
/// période du graphique ne recharge pas les KPI/activité.
///
/// [onboarding] est non-null quand le bailleur est en mode onboarding
/// (progression incomplète et non masquée, cf. `dashboard_provider.dart`).
/// Dans ce cas, les 3 KPI sont vides — on affiche l'onboarding.
@freezed
class DashboardSnapshot with _$DashboardSnapshot {
  const DashboardSnapshot._();

  const factory DashboardSnapshot({
    required LoyersMoisKpi loyers,
    required RetardsKpi retards,
    required DocsPendingKpi docs,
    required List<ActivityItem> activity,
    OnboardingProgress? onboarding,
  }) = _DashboardSnapshot;

  bool get isOnboarding => onboarding != null;

  /// Factory pour l'état onboarding.
  ///
  /// Évite de passer des zéros partout depuis le provider.
  factory DashboardSnapshot.onboarding(OnboardingProgress progress) =>
      DashboardSnapshot(
        loyers: const LoyersMoisKpi(encaissedCents: 0, dueCents: 0),
        retards: const RetardsKpi(count: 0),
        docs: const DocsPendingKpi(count: 0),
        activity: const [],
        onboarding: progress,
      );
}
