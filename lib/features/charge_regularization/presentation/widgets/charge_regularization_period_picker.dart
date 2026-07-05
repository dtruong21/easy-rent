import 'package:flutter/material.dart';

import '../../../../core/utils/french_date.dart';

/// Sélecteur de date pour la période de référence d'une régularisation.
///
/// Extrait de [ChargeRegularizationDialog] pour lisibilité (règle
/// "widgets < 200 lignes").
///
/// [minDate]/[maxDate] permettent à l'appelant de contraindre la plage
/// sélectionnable — utilisé par [ChargeRegularizationForm] pour empêcher de
/// choisir une fin de période antérieure au début (cf. correctif review
/// FEAT-029 : une période inversée produirait un avis légal incohérent et un
/// calcul de provisions faux).
class ChargeRegularizationPeriodPicker extends StatelessWidget {
  const ChargeRegularizationPeriodPicker({
    super.key,
    required this.label,
    required this.date,
    required this.onPick,
    this.minDate,
    this.maxDate,
    this.errorText,
  });

  final String label;
  final DateTime date;
  final void Function(DateTime) onPick;

  /// Date minimale sélectionnable — par défaut `DateTime(1900)`.
  final DateTime? minDate;

  /// Date maximale sélectionnable — par défaut `DateTime(2100)`.
  final DateTime? maxDate;

  /// Message d'erreur affiché sous le champ (ex. période inversée).
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final firstDate = minDate ?? DateTime(1900);
    final lastDate = maxDate ?? DateTime(2100);
    // `initialDate` doit rester dans `[firstDate, lastDate]` (contrat
    // showDatePicker) — si `date` est devenue antérieure à `firstDate` suite
    // à un changement de l'autre borne, on clamp pour éviter une assertion
    // Flutter au moment de l'ouverture du picker.
    final initialDate = date.isBefore(firstDate)
        ? firstDate
        : (date.isAfter(lastDate) ? lastDate : date);

    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: lastDate,
          helpText: label,
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
          errorText: errorText,
        ),
        child: Text(FrenchDate.format(date)),
      ),
    );
  }
}
