import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/utils/french_date.dart';
import '../../domain/receipt.dart';

/// Résultat du mapping quittance → données de pill.
typedef ReceiptStatusPillData = ({
  StatusPillTone tone,
  String label,
  IconData icon,
});

/// Mappe une [Receipt] vers les propriétés d'affichage d'un [StatusPill].
///
/// 5 statuts effectifs (aucun brouillon — une quittance en DB est déjà générée) :
/// 1. `isVoided`               → danger   "Annulée"
/// 2. `isStale && !isVoided`   → warning  "Périmée"
/// 3. `!isVoided && hasBeenShared` → success "Envoyée"
/// 4. `!isVoided && paymentIds non vide` → info "Payée"
/// 5. sinon                   → info     "Émise"
///
/// [context] est requis pour la localisation des libellés (FEAT-043) — les
/// appelants sont tous des widgets avec un [BuildContext] disponible.
ReceiptStatusPillData receiptStatusPill(BuildContext context, Receipt r) {
  final l10n = context.l10n;
  if (r.isVoided) {
    return (
      tone: StatusPillTone.danger,
      label: l10n.receiptsStatusVoided,
      icon: Icons.cancel_outlined,
    );
  }
  if (r.isStale) {
    return (
      tone: StatusPillTone.warning,
      label: l10n.receiptsStatusStale,
      icon: Icons.warning_amber_outlined,
    );
  }
  if (r.hasBeenShared) {
    return (
      tone: StatusPillTone.success,
      label: l10n.receiptsStatusSent,
      icon: Icons.task_alt_outlined,
    );
  }
  if (r.paymentIds.isNotEmpty) {
    return (
      tone: StatusPillTone.info,
      label: l10n.receiptsStatusPaid,
      icon: Icons.paid_outlined,
    );
  }
  return (
    tone: StatusPillTone.info,
    label: l10n.receiptsStatusIssued,
    icon: Icons.receipt_long_outlined,
  );
}

/// Libellé de période mensuelle court (ex: "Mars 2026").
///
/// Capitalise le premier caractère du mois retourné par [FrenchDate.frenchMonthYear].
String receiptPeriodMonthYear(Receipt r) {
  final raw = FrenchDate.frenchMonthYear(r.periodStart);
  if (raw.isEmpty) return raw;
  return raw[0].toUpperCase() + raw.substring(1);
}

/// Ligne secondaire d'information contextuelle sur la quittance.
///
/// Règles :
/// - `void`                       → "Annulée le DD/MM"
/// - `valid + paid + sent`        → "Payée le DD/MM · Partagée le DD/MM à m***@domain"
/// - `valid + paid`               → "Payée le DD/MM"
/// - `valid`                      → "Émise le DD/MM"
///
/// Note : `paid_at` n'existe pas en DB (Phase 4). On approxime par [generatedAt].
///
/// [context] est requis pour la localisation (FEAT-043) — les appelants sont
/// tous des widgets avec un [BuildContext] disponible.
String receiptSecondaryLine(BuildContext context, Receipt r) {
  final l10n = context.l10n;
  final issuedDate = _shortDate(r.generatedAt);

  if (r.isVoided) {
    final voidDate = r.voidedAt != null ? _shortDate(r.voidedAt!) : issuedDate;
    return l10n.receiptsSecondaryVoidedOn(voidDate);
  }

  final isPaid = r.paymentIds.isNotEmpty;

  if (isPaid && r.hasBeenShared) {
    final sharedDate = _shortDate(r.sentAt!);
    final maskedEmail = r.maskedSentToEmail ?? '';
    return l10n.receiptsSecondaryPaidAndSharedOn(
      issuedDate,
      sharedDate,
      maskedEmail,
    );
  }

  if (isPaid) {
    return l10n.receiptsSecondaryPaidOn(issuedDate);
  }

  return l10n.receiptsSecondaryIssuedOn(issuedDate);
}

/// Formate une date en `DD/MM` (ex: "04/03").
String _shortDate(DateTime date) {
  final d = date.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}';
}
