import 'package:flutter/material.dart';

/// Dialog de confirmation d'archivage d'un bien.
///
/// Deux variantes selon [hasActiveLease] :
/// - false : message standard ("Archiver ce bien ?")
/// - true  : message renforcé ("Ce bien a un bail actif.")
///
/// L'archivage reste possible dans les deux cas après confirmation explicite.
class ArchiveConfirmDialog extends StatelessWidget {
  const ArchiveConfirmDialog({
    super.key,
    required this.propertyName,
    required this.hasActiveLease,
    required this.onConfirm,
  });

  final String propertyName;
  final bool hasActiveLease;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Archiver ce bien ?'),
      content: Text(
        hasActiveLease
            ? 'Ce bien a un bail actif. Êtes-vous sûr de vouloir archiver '
                  '"$propertyName" ? Les baux actifs liés seront conservés '
                  'mais le bien n\'apparaîtra plus dans votre liste.'
            : 'Voulez-vous archiver "$propertyName" ? '
                  'Le bien n\'apparaîtra plus dans votre liste. '
                  'Les baux liés seront conservés.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          child: const Text('Archiver'),
        ),
      ],
    );
  }
}
