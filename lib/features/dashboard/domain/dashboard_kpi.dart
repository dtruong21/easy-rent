import 'package:freezed_annotation/freezed_annotation.dart';

part 'dashboard_kpi.freezed.dart';

/// KPI "Loyers du mois" : encaissé vs dû.
///
/// [encaissedCents] : somme des paiements enregistrés ce mois-ci.
/// [dueCents]       : somme théorique (loyer+charges) des baux actifs.
@freezed
class LoyersMoisKpi with _$LoyersMoisKpi {
  const factory LoyersMoisKpi({
    required int encaissedCents,
    required int dueCents,
  }) = _LoyersMoisKpi;
}

/// KPI "Locataires en retard" : nombre de baux actifs sans paiement depuis >35j.
@freezed
class RetardsKpi with _$RetardsKpi {
  const factory RetardsKpi({required int count}) = _RetardsKpi;
}

/// KPI "Baux à renouveler" : baux actifs dont l'échéance est dans 30j.
@freezed
class RenouvellementsKpi with _$RenouvellementsKpi {
  const factory RenouvellementsKpi({required int count}) = _RenouvellementsKpi;
}

/// KPI "Documents en attente" : documents de catégorie 'autre'.
///
/// Proxy MVP — à raffiner P1 via un workflow d'attente explicite.
@freezed
class DocsPendingKpi with _$DocsPendingKpi {
  const factory DocsPendingKpi({required int count}) = _DocsPendingKpi;
}

/// Loyers encaissés pour un mois donné — brique de calcul du graphique
/// « Cash-flow mensuel » (voir `MonthlyCashflow`, dashboard/domain).
///
/// Volontairement séparé des dépenses : `DashboardRepository` ne dépend pas
/// de `ExpensesRepository` (même séparation que `PortfolioYieldSection`, qui
/// combine `propertiesListItemsProvider` et `expensesRepositoryProvider`
/// dans la couche application plutôt que dans un repository unique).
///
/// [hasPayments] : `true` si au moins un paiement a été enregistré ce
/// mois-ci — distingue "aucun paiement" de "paiements pour un total de 0 €"
/// (cas limite), utilisé pour dériver `MonthlyCashflow.hasData`.
@freezed
class MonthlyCollectedRent with _$MonthlyCollectedRent {
  const factory MonthlyCollectedRent({
    required int year,
    required int month,
    required int collectedCents,
    required bool hasPayments,
  }) = _MonthlyCollectedRent;
}
