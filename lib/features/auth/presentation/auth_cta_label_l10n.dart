import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/auth_cta_label.dart';

/// Traduit un [AuthCtaLabel] en libellé localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`auth_cta_label.dart`) reste pur. Réutilise verbatim les clés
/// ARB déjà existantes des boutons homologues (`authCreateAccountLink`,
/// `authSignInButton`) plutôt que d'en dupliquer, conformément à
/// `lib/l10n/l10n_convention.dart` §2.
extension AuthCtaLabelL10n on AuthCtaLabel {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      AuthCtaLabel.createAccount => l10n.authCreateAccountLink,
      AuthCtaLabel.signIn => l10n.authSignInButton,
    };
  }
}
