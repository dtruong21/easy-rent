// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'charge_statement_line_item.freezed.dart';
part 'charge_statement_line_item.g.dart';

/// Ligne de détail figée d'un décompte de régularisation (FEAT-033).
///
/// Copie figée d'une Dépense récupérable au moment du finalize — ne
/// référence PAS la Dépense vivante. `nature` porte la valeur SQL de
/// `ExpenseNature` (rendue via `expense_nature_l10n.dart` à l'affichage) ;
/// `notes` est le libellé libre saisi par le bailleur (peut être vide).
@freezed
class ChargeStatementLineItem with _$ChargeStatementLineItem {
  const factory ChargeStatementLineItem({
    @JsonKey(name: 'expense_id') required String expenseId,
    required String nature,
    @Default('') String notes,
    @JsonKey(name: 'amount_cents') required int amountCents,
    @JsonKey(name: 'expense_date') required DateTime expenseDate,
  }) = _ChargeStatementLineItem;

  factory ChargeStatementLineItem.fromJson(Map<String, dynamic> json) =>
      _$ChargeStatementLineItemFromJson(json);
}
