import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/payment_method.dart';

/// Libellé localisé de [PaymentMethod] pour l'UI (FEAT-043 — pattern
/// « enum métier → mapping l10n en présentation », cf.
/// `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`payment_method.dart`) conserve le getter `label` (FR en dur)
/// pour ne pas casser les call sites du module `leases` (hors périmètre
/// strict de ce ticket) qui l'utilisent encore tel quel :
/// `lease_detail_page.dart` et `widgets/lease_form.dart`.
///
/// Le nom `label` choisi ici pour cette extension entre donc en conflit avec
/// le getter du domaine (member du domaine prioritaire sur l'extension à
/// résolution statique) : les call sites de ce module utilisent la syntaxe
/// d'application explicite `PaymentMethodL10n(value).label(context)` plutôt
/// que `value.label(context)` — même pattern déjà établi pour
/// `LeaseType.formHelperText` (voir `lease_type_l10n.dart` et son usage dans
/// `lease_form.dart:616`).
extension PaymentMethodL10n on PaymentMethod {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      PaymentMethod.virement => l10n.paymentsMethodTransfer,
      PaymentMethod.cheque => l10n.paymentsMethodCheck,
      PaymentMethod.especes => l10n.paymentsMethodCash,
      PaymentMethod.prelevement => l10n.paymentsMethodDirectDebit,
      PaymentMethod.autre => l10n.paymentsMethodOther,
    };
  }
}
