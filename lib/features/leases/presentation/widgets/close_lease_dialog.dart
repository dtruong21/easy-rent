import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/french_date.dart';

/// Dialog de clôture d'un bail actif.
///
/// Affiche un date picker pré-rempli à aujourd'hui pour la date de fin
/// effective. L'utilisateur peut confirmer ou annuler.
///
/// Sur confirmation : appelle [onClose] avec la date effective choisie.
class CloseLeaseDialog extends StatefulWidget {
  const CloseLeaseDialog({super.key, required this.onClose});

  /// Callback appelé avec la date de fin effective choisie par l'utilisateur.
  final void Function(DateTime effectiveEndDate) onClose;

  @override
  State<CloseLeaseDialog> createState() => _CloseLeaseDialogState();
}

class _CloseLeaseDialogState extends State<CloseLeaseDialog> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    // Pré-rempli à aujourd'hui.
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate() async {
    // Sans ça, la fermeture du sélecteur rend le focus au dernier champ
    // saisi et rouvre le clavier (recette iOS, #197).
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: context.l10n.leasesCloseDialogDatePickerHelp,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.leasesCloseDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.leasesCloseDialogContent),
          const SizedBox(height: 16),
          Text(
            l10n.leasesCloseDialogEffectiveDateLabel,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: Text(
                FrenchDate.format(_selectedDate),
                key: const Key('close_lease_date_display'),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('btn_close_lease_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('btn_close_lease_confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            widget.onClose(_selectedDate);
          },
          child: Text(l10n.leasesCloseDialogConfirmButton),
        ),
      ],
    );
  }
}
