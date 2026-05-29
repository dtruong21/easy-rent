import 'package:flutter/material.dart';

/// Dialog d'avertissement affiché quand un bail actif existe déjà pour le
/// bien sélectionné.
///
/// L'utilisateur peut annuler ou confirmer la création malgré l'avertissement.
/// Cas d'usage : copropriété, erreur de saisie, transition entre locataires.
class ActiveLeaseWarningDialog extends StatelessWidget {
  const ActiveLeaseWarningDialog({super.key, required this.onConfirm});

  /// Callback appelé quand l'utilisateur choisit "Continuer" malgré
  /// l'avertissement.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bail actif existant'),
      content: const Text(
        'Ce bien a déjà un bail actif. '
        'Voulez-vous quand même créer ce nouveau bail ?',
      ),
      actions: [
        TextButton(
          key: const Key('btn_warning_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('btn_warning_confirm'),
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          child: const Text('Continuer'),
        ),
      ],
    );
  }
}
