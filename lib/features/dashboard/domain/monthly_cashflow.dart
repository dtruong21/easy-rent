import 'package:freezed_annotation/freezed_annotation.dart';

part 'monthly_cashflow.freezed.dart';

/// Cash flow **réel** d'un mois — alimente le graphique dashboard qui a
/// remplacé l'ancien barchart « Loyers » (encaissé vs dû) : un loyer est
/// fixe, le voir en barres n'apprend rien au bailleur. Ce qu'il ne connaît
/// PAS de tête, c'est son cash flow réel une fois les dépenses du mois
/// déduites.
///
/// [year] + [month] identifient le mois (mois 1–12).
///
/// [collectedRentCents] : somme des loyers + charges effectivement encaissés
/// ce mois-ci (paiements enregistrés, `paidAt` dans le mois).
///
/// [nonRecoverableExpenseCents] : somme des dépenses réelles **non
/// récupérables** engagées ce mois-ci (`expenseDate` dans le mois). Les
/// charges récupérables sont refacturées au locataire via la régularisation
/// annuelle — elles ne représentent pas une sortie de cash flow nette pour
/// le bailleur, même principe que `PortfolioYieldSection`/
/// `PropertyProfitabilityCard`. **Diverge en revanche** de
/// `groupRealCharges` (core/finance) sur un point : ce dernier ne retient
/// que 3 natures ayant un équivalent prévisionnel déclaré sur le bien
/// (taxe foncière, PNO, charges de copro), pour éviter un double comptage
/// avec le prévisionnel lors de la bascule réel/prévisionnel. Ce graphique
/// n'a AUCUN prévisionnel à protéger (100 % réel) : restreindre à ces 3
/// natures rendrait invisible, par exemple, une grosse facture de travaux —
/// contraire au but même du graphique (montrer un mois où les dépenses
/// dépassent les loyers). Toute dépense non récupérable compte donc ici.
///
/// [loanPaymentCents] : somme, tous biens confondus, des mensualités de
/// prêt (capital + intérêts + assurance) imputables à ce mois — voir
/// `monthly_loan_payment.dart` pour la règle de fenêtre (un mois hors
/// `[loanStartDate, dernière échéance]` ne porte aucune mensualité). Sans
/// cette déduction, le graphique contredisait le KPI « Rentabilité
/// portfolio » (`computeMonthlyCashflowBeforeTaxCents`, core/finance), qui
/// lui déduit déjà la mensualité — signalé en recette (« aucun impact sur
/// le graphique du cash-flow mensuel »).
///
/// [hasData] : `true` si au moins un paiement, une dépense OU une mensualité
/// de prêt a été enregistré/imputé ce mois-ci — distingue un mois « zéro
/// net » (données présentes, solde nul par coïncidence) d'un mois « sans
/// donnée » (rien n'a été saisi, le bailleur n'avait tout simplement pas
/// encore de bien/bail à cette période). Une mensualité de prêt à elle
/// seule fait exister le mois : un bien à crédit sans loyer ni dépense ce
/// mois-là a quand même une sortie de cash flow réelle et négative, pas
/// « rien à mesurer ».
@freezed
class MonthlyCashflow with _$MonthlyCashflow {
  const factory MonthlyCashflow({
    required int year,
    required int month,
    required int collectedRentCents,
    required int nonRecoverableExpenseCents,
    required int loanPaymentCents,
    required bool hasData,
  }) = _MonthlyCashflow;
}

/// Getters calculés — non freezed pour ne pas alourdir le codegen.
extension MonthlyCashflowX on MonthlyCashflow {
  /// Cash flow net du mois : loyers encaissés moins dépenses non
  /// récupérables réellement engagées moins mensualité de prêt. Peut être
  /// négatif (dépenses + mensualité > loyers).
  int get netCents =>
      collectedRentCents - nonRecoverableExpenseCents - loanPaymentCents;
}
