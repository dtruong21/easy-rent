import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';

/// Validation côté client du motif d'annulation.
///
/// Miroir de la contrainte DB :
/// `char_length(voided_reason) BETWEEN 3 AND 500`.
const int _kMinReasonLength = 3;
const int _kMaxReasonLength = 500;

/// Dialog de confirmation d'annulation d'une quittance.
///
/// Exige un motif texte (3-500 chars, validation client).
/// Retourne le motif via [onConfirm] si confirmé.
///
/// Actions :
/// - "Annuler" : ferme sans action.
/// - "Confirmer l'annulation" (rouge) : valide et appelle [onConfirm].
class VoidReceiptDialog extends StatefulWidget {
  const VoidReceiptDialog({
    super.key,
    required this.onConfirm,
    this.isSubmitting = false,
  });

  /// Callback appelé avec le motif saisi si l'utilisateur confirme.
  final void Function(String reason) onConfirm;

  /// Si `true`, les boutons sont désactivés (annulation en cours).
  final bool isSubmitting;

  @override
  State<VoidReceiptDialog> createState() => _VoidReceiptDialogState();
}

class _VoidReceiptDialogState extends State<VoidReceiptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return AlertDialog(
      key: const Key('dialog_void_receipt'),
      title: Row(
        children: [
          Icon(Icons.cancel_outlined, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Text(l10n.receiptsVoidDialogTitle),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.receiptsVoidDialogContent,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('field_void_reason'),
              controller: _reasonCtrl,
              maxLines: 3,
              maxLength: _kMaxReasonLength,
              enabled: !widget.isSubmitting,
              decoration: InputDecoration(
                labelText: l10n.receiptsVoidReasonLabel,
                hintText: l10n.receiptsVoidReasonHint,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.length < _kMinReasonLength) {
                  return l10n.receiptsVoidReasonTooShort(_kMinReasonLength);
                }
                if (trimmed.length > _kMaxReasonLength) {
                  return l10n.receiptsVoidReasonTooLong(_kMaxReasonLength);
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('btn_void_cancel'),
          onPressed: widget.isSubmitting
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('btn_void_confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: widget.isSubmitting ? null : _submit,
          child: widget.isSubmitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.receiptsVoidConfirmButton),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      widget.onConfirm(_reasonCtrl.text.trim());
    }
  }
}
