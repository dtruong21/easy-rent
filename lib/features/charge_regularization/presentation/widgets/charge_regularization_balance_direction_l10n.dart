import 'package:flutter/widgets.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/charge_regularization_balance.dart';

/// Libellé localisé de [ChargeRegularizationBalanceDirection] (FEAT-043 —
/// pattern « enum métier → mapping l10n en présentation », cf.
/// `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`charge_regularization_balance.dart`) conserve `labelFr` (FR
/// en dur) : il reste utilisé tel quel par l'avis PDF légal
/// (`charge_regularization_pdf_renderer.dart`) et le corps de l'email de
/// partage (`charge_regularization_share_payload_builder.dart`) — tous deux
/// hors périmètre i18n (document opposable au locataire / contenu adressé
/// au locataire composé sans `BuildContext`, cf.
/// `docs/plans/FEAT-043-i18n.md` §6). Cette extension est réservée à
/// l'affichage écran ([ChargeRegularizationBalanceSummary]).
extension ChargeRegularizationBalanceDirectionL10n
    on ChargeRegularizationBalanceDirection {
  String localizedLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ChargeRegularizationBalanceDirection.dueByTenant =>
        l10n.chargeRegularizationBalanceDirectionDueByTenant,
      ChargeRegularizationBalanceDirection.dueToTenant =>
        l10n.chargeRegularizationBalanceDirectionDueToTenant,
      ChargeRegularizationBalanceDirection.balanced =>
        l10n.chargeRegularizationBalanceDirectionBalanced,
    };
  }
}
