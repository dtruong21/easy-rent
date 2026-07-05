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
