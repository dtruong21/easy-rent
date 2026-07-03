import 'package:freezed_annotation/freezed_annotation.dart';

part 'monthly_amount.freezed.dart';

/// Montants mensuels pour le barchart « Loyers » (période variable :
/// 6 / 12 / 24 mois, cf. [ChartPeriod]).
///
/// [year] + [month] identifient le mois (mois 1–12).
/// [encaissedCents] : somme des paiements encaissés dans ce mois.
/// [dueCents]       : somme théorique des baux actifs durant ce mois.
@freezed
class MonthlyAmount with _$MonthlyAmount {
  const factory MonthlyAmount({
    required int year,
    required int month,
    required int encaissedCents,
    required int dueCents,
  }) = _MonthlyAmount;
}
