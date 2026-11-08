/// Messages de limite « offre gratuite » : sur les apps iOS/Android
/// ([isStoreApp]) ils ne doivent contenir aucun appel à passer à une offre
/// payante (aucun achat hors achat intégré — App Store 3.1.1) ; sur le web ils
/// gardent l'appel « Passez à … ».
library;

import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/documents/domain/upload_file_status.dart';
import 'package:easyrent/features/documents/presentation/upload_file_error_reason_l10n.dart';
import 'package:easyrent/features/leases/domain/lease_submit_error.dart';
import 'package:easyrent/features/leases/presentation/lease_submit_error_l10n.dart';
import 'package:easyrent/features/properties/domain/property_submit_error.dart';
import 'package:easyrent/features/properties/presentation/property_submit_error_l10n.dart';
import 'package:easyrent/features/tenants/domain/tenant_submit_error.dart';
import 'package:easyrent/features/tenants/presentation/tenant_submit_error_l10n.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Résout les quatre messages dans un vrai [BuildContext] localisé (FR).
Future<Map<String, String>> _messages(WidgetTester tester) async {
  final out = <String, String>{};
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
      home: Builder(
        builder: (context) {
          out['property'] = PropertySubmitError.limitReached.message(context);
          out['tenant'] = TenantSubmitError.limitReached.message(context);
          out['lease'] = LeaseSubmitError.limitReached.message(context);
          out['document'] = UploadFileErrorReason.fileTooLarge.message(
            context,
            maxFileSizeBytes: 10 * 1024 * 1024,
            serverLimitBytes: 10 * 1024 * 1024,
            serverUpgradeToLevelId: 'pro',
          );
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return out;
}

void main() {
  tearDown(() => debugIsStoreAppOverride = null);

  testWidgets('apps store : aucun appel à passer à une offre payante', (
    tester,
  ) async {
    debugIsStoreAppOverride = true;
    final m = await _messages(tester);

    for (final entry in m.entries) {
      expect(
        entry.value,
        isNot(contains('Passez')),
        reason: 'message ${entry.key} : ${entry.value}',
      );
    }
    // La limite elle-même reste dite.
    expect(m['property'], contains('limite de biens'));
    expect(m['tenant'], contains('limite de locataires'));
    expect(m['lease'], contains('limite de baux actifs'));
    expect(m['document'], contains('Le fichier dépasse'));
  });

  testWidgets('web : le message garde l\'appel « Passez à … »', (tester) async {
    debugIsStoreAppOverride = false;
    final m = await _messages(tester);

    expect(m['property'], contains('Passez à l\'offre Pro'));
    expect(m['tenant'], contains('Passez à l\'offre Pro'));
    expect(m['lease'], contains('Passez à l\'offre Pro'));
    expect(m['document'], contains('Passez à'));
  });
}
