import 'package:flutter/material.dart';

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
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Date de fin effective',
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Clôturer ce bail'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cette action passera le statut du bail à "Terminé". '
            'Elle est irréversible via l\'interface.',
          ),
          const SizedBox(height: 16),
          Text('Date de fin effective', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: Text(
                _formatDate(_selectedDate),
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
          child: const Text('Annuler'),
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
          child: const Text('Clôturer'),
        ),
      ],
    );
  }
}
