import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/french_date.dart';
import '../../../tenants/domain/tenant.dart';
import '../../domain/lease.dart';
import '../../domain/lease_lateness.dart';
import '../../domain/payment_reminder_channel.dart';
import '../../domain/payment_reminder_message.dart';

/// Signature du lanceur d'URL (injectable pour les tests).
typedef UrlLauncher = Future<bool> Function(Uri uri, {LaunchMode mode});

/// Bouton « Relancer le locataire » (FEAT-031 V1). À monter uniquement quand
/// le bail est en retard. Ouvre l'app email/SMS/WhatsApp du bailleur avec un
/// message de relance amiable pré-rempli (aucun envoi serveur).
class PaymentReminderButton extends StatelessWidget {
  const PaymentReminderButton({
    super.key,
    required this.lease,
    required this.tenant,
    required this.landlordFullName,
    required this.propertyAddress,
    UrlLauncher? launcher,
    DateTime? now,
  }) : _launcher = launcher ?? launchUrl,
       _now = now;

  final Lease lease;
  final Tenant tenant;
  final String landlordFullName;
  final String propertyAddress;
  final UrlLauncher _launcher;
  final DateTime? _now;

  PaymentReminderMessage _message() {
    final due = leaseCurrentDueMonth(
      startDate: lease.startDate,
      paymentDay: lease.paymentDay,
      now: _now ?? DateTime.now(),
    );
    final dueLabel = due != null
        ? FrenchDate.frenchMonthYear(due)
        : FrenchDate.frenchMonthYear(_now ?? DateTime.now());
    return buildPaymentReminderMessage(
      tenantFirstName: tenant.firstName,
      landlordFullName: landlordFullName,
      propertyAddress: propertyAddress,
      dueMonthLabel: dueLabel,
      // FEAT-031 revue finale : le locataire doit légalement uniquement
      // rent + charges RÉCUPÉRABLES, pas les non-récupérables incluses dans
      // `totalChargesCents` (voir lease.dart — jamais un montant dû).
      amountDueCents: lease.totalAmountCents,
    );
  }

  String _channelLabel(BuildContext context, ReminderChannel c) => switch (c) {
    ReminderChannel.email => context.l10n.paymentReminderChannelEmail,
    ReminderChannel.sms => context.l10n.paymentReminderChannelSms,
    ReminderChannel.whatsApp => context.l10n.paymentReminderChannelWhatsApp,
  };

  IconData _channelIcon(ReminderChannel c) => switch (c) {
    ReminderChannel.email => Icons.email_outlined,
    ReminderChannel.sms => Icons.sms_outlined,
    ReminderChannel.whatsApp => Icons.chat_outlined,
  };

  Future<void> _launch(BuildContext context, ReminderChannel channel) async {
    final uri = reminderUriFor(
      channel: channel,
      tenantEmail: tenant.email,
      tenantPhone: tenant.phone,
      message: _message(),
    );
    if (uri == null) return;
    var ok = false;
    try {
      ok = await _launcher(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.paymentReminderLaunchError)),
      );
    }
  }

  Future<void> _onPressed(BuildContext context) async {
    final channels = availableReminderChannels(phone: tenant.phone);
    if (channels.length == 1) {
      await _launch(context, channels.first);
      return;
    }
    final chosen = await showModalBottomSheet<ReminderChannel>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                sheetContext.l10n.paymentReminderChannelSheetTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final c in channels)
              ListTile(
                key: Key('reminder_channel_${c.name}'),
                leading: Icon(_channelIcon(c)),
                title: Text(_channelLabel(sheetContext, c)),
                onTap: () => Navigator.of(sheetContext).pop(c),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && context.mounted) {
      await _launch(context, chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('btn_payment_reminder'),
      icon: const Icon(Icons.notifications_active_outlined, size: 18),
      label: Text(context.l10n.paymentReminderButton),
      onPressed: () => _onPressed(context),
    );
  }
}
