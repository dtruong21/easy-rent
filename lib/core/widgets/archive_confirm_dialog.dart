import 'package:flutter/material.dart';

/// Dialog de confirmation d'archivage — mutualisé pour toutes les entités.
///
/// Paramétré via [title], [entityLabel], [standardMessage] et
/// [activeLeaseMessage] pour s'adapter à n'importe quelle entité
/// (bien, locataire, bail…).
///
/// Deux variantes selon [hasActiveLease] :
/// - false : [standardMessage] affiché.
/// - true  : [activeLeaseMessage] affiché (avertissement renforcé).
///
/// L'archivage reste possible dans les deux cas après confirmation explicite.
class ArchiveConfirmDialog extends StatelessWidget {
  const ArchiveConfirmDialog({
    super.key,
    required this.title,
    required this.entityLabel,
    required this.standardMessage,
    required this.activeLeaseMessage,
    required this.hasActiveLease,
    required this.onConfirm,
  });

  /// Titre de la dialog (ex : "Archiver ce bien ?" ou "Archiver ce locataire ?").
  final String title;

  /// Nom/libellé de l'entité à archiver (ex : "Appart Lyon", "Jean Dupont").
  final String entityLabel;

  /// Message standard (sans bail actif) — doit mentionner [entityLabel].
  final String standardMessage;

  /// Message renforcé (avec bail actif) — doit avertir l'utilisateur.
  final String activeLeaseMessage;

  /// Présence d'au moins un bail actif lié à cette entité.
  final bool hasActiveLease;

  /// Callback appelé quand l'utilisateur confirme l'archivage.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(hasActiveLease ? activeLeaseMessage : standardMessage),
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
