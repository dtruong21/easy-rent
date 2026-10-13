import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/utils/byte_format.dart';
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

/// Rend le message calculé par [compute] dans un contexte localisé `fr`.
Future<String> _message(
  WidgetTester tester,
  String Function(BuildContext context) compute,
) async {
  late String result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
      home: Builder(
        builder: (context) {
          result = compute(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

/// Déclare les 3 cas (web / app store achat coupé / app store achat actif)
/// d'un message dont la variante d'incitation est [upsell] et la variante
/// neutre [neutral].
void _threeCases({
  required String Function(BuildContext context) compute,
  required String upsell,
  required String neutral,
}) {
  testWidgets('web → incitation', (tester) async {
    debugIsStoreAppOverride = false;
    expect(await _message(tester, compute), upsell);
  });

  testWidgets('app store, achat coupé → message neutre', (tester) async {
    debugIsStoreAppOverride = true;
    debugInAppPurchaseEnabledOverride = false;
    expect(await _message(tester, compute), neutral);
  });

  testWidgets('app store, achat actif → incitation', (tester) async {
    debugIsStoreAppOverride = true;
    debugInAppPurchaseEnabledOverride = true;
    expect(await _message(tester, compute), upsell);
  });
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('fr'));

  tearDown(() {
    debugIsStoreAppOverride = false;
    debugInAppPurchaseEnabledOverride = null;
  });

  group('biens — limite atteinte', () {
    _threeCases(
      compute: (c) => PropertySubmitError.limitReached.message(c),
      upsell: l10n.propertiesErrorLimitReached,
      neutral: l10n.propertiesErrorLimitReachedStore,
    );
  });

  group('locataires — limite atteinte', () {
    _threeCases(
      compute: (c) => TenantSubmitError.limitReached.message(c),
      upsell: l10n.tenantsErrorLimitReached,
      neutral: l10n.tenantsErrorLimitReachedStore,
    );
  });

  group('baux — limite atteinte', () {
    _threeCases(
      compute: (c) => LeaseSubmitError.limitReached.message(c),
      upsell: l10n.leasesErrorLimitReached,
      neutral: l10n.leasesErrorLimitReachedStore,
    );
  });

  group('document trop volumineux', () {
    const limit = 5 * 1024 * 1024;
    final sizeLabel = ByteFormat.format(limit);

    String compute(BuildContext c) => UploadFileErrorReason.fileTooLarge
        .message(c, serverLimitBytes: limit, serverUpgradeToLevelId: 'pro');

    _threeCases(
      compute: compute,
      // `planLevelPro` = libellé du palier « Pro » (planLevelLabelForId).
      upsell: l10n.documentsUploadErrorFileTooLargeWithUpgrade(
        sizeLabel,
        l10n.planLevelPro,
      ),
      neutral: l10n.documentsUploadErrorFileTooLarge(sizeLabel),
    );
  });
}
