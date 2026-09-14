/// Tests widget de [PaymentReminderButton] (FEAT-031 V1).
///
/// Couvre : locataire sans téléphone → un seul canal disponible (email),
/// ouverture directe d'un `mailto:` sans passer par le bottom sheet ;
/// locataire avec téléphone FR → bottom sheet listant les 3 canaux
/// (email/SMS/WhatsApp). Le `launcher` est injecté (factice) pour ne jamais
/// ouvrir une vraie app pendant le test.
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/leases/presentation/widgets/payment_reminder_button.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// Helpers — factories calquées sur test/unit/lease_lateness_test.dart et
// test/unit/tenant_serialization_test.dart (constructeurs réels).
// ---------------------------------------------------------------------------

/// Bail actif démarré il y a longtemps (paymentDay=1) : un mois est
/// nécessairement dû à `DateTime.now()`, quelle que soit la date
/// d'exécution du test. Le test n'assert pas la période, seulement le
/// canal/URI choisi.
Lease _lease() => Lease(
  id: 'l1',
  landlordId: 'owner',
  propertyId: 'p1',
  tenantId: 't1',
  rentAmountCents: 80000,
  chargesAmountCents: 5000,
  startDate: DateTime(2020, 1, 1),
  status: LeaseStatus.active,
  leaseType: LeaseType.unfurnished,
  paymentDay: 1,
  createdAt: DateTime(2020, 1, 1),
  updatedAt: DateTime(2020, 1, 1),
);

Tenant _tenant({String? phone}) => Tenant(
  id: 't1',
  landlordId: 'owner',
  firstName: 'Marie',
  lastName: 'Martin',
  email: 'loc@ex.fr',
  phone: phone,
  createdAt: DateTime.utc(2024, 1, 1),
  updatedAt: DateTime.utc(2024, 1, 2),
);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  locale: const Locale('fr'),
  supportedLocales: supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('téléphone vide → email direct (mailto), pas de bottom sheet', (
    tester,
  ) async {
    Uri? launched;
    await tester.pumpWidget(
      _host(
        PaymentReminderButton(
          lease: _lease(),
          tenant: _tenant(phone: null),
          landlordFullName: 'Jean Bailleur',
          propertyAddress: '2 rue de Lyon',
          launcher: (uri, {mode = LaunchMode.platformDefault}) async {
            launched = uri;
            return true;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('btn_payment_reminder')));
    await tester.pumpAndSettle();
    expect(find.text('Envoyer la relance via'), findsNothing);
    expect(launched!.scheme, 'mailto');
    expect(launched!.path, 'loc@ex.fr');
  });

  testWidgets('téléphone FR → bottom sheet avec 3 canaux', (tester) async {
    await tester.pumpWidget(
      _host(
        PaymentReminderButton(
          lease: _lease(),
          tenant: _tenant(phone: '06 12 34 56 78'),
          landlordFullName: 'Jean Bailleur',
          propertyAddress: '2 rue de Lyon',
          launcher: (uri, {mode = LaunchMode.platformDefault}) async => true,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('btn_payment_reminder')));
    await tester.pumpAndSettle();
    expect(find.text('Envoyer la relance via'), findsOneWidget);
    expect(find.byKey(const Key('reminder_channel_email')), findsOneWidget);
    expect(find.byKey(const Key('reminder_channel_sms')), findsOneWidget);
    expect(find.byKey(const Key('reminder_channel_whatsApp')), findsOneWidget);
  });
}
