import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';

/// Champ mot de passe réutilisable avec toggle show/hide.
class PasswordField extends StatefulWidget {
  const PasswordField({
    required this.controller,
    required this.labelText,
    this.autofillHints,
    this.errorText,
    this.enabled = true,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String labelText;
  final Iterable<String>? autofillHints;
  final String? errorText;
  final bool enabled;
  final VoidCallback? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      enabled: widget.enabled,
      autocorrect: false,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.labelText,
        errorText: widget.errorText,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
          tooltip: _obscure
              ? l10n.authPasswordShowTooltip
              : l10n.authPasswordHideTooltip,
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      onSubmitted: widget.onSubmitted != null
          ? (_) => widget.onSubmitted!()
          : null,
    );
  }
}
