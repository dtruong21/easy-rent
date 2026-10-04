import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenant_card.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Lanceur d'URL factice : enregistre les URL et renvoie [result].
class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final launched = <String>[];
  bool result = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => result;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return result;
  }
}

Tenant _makeTenant({
  String id = 't1',
  String email = 'jean@test.com',
  String? phone,
}) => Tenant(
  id: id,
  landlordId: 'owner',
  firstName: 'Jean',
  lastName: 'Dupont',
  email: email,
  phone: phone,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

TenantListItem _item({
  String id = 't1',
  String? leaseId,
  String? phone,
  String? propertyName,
}) => TenantListItem(
  tenant: _makeTenant(id: id, phone: phone),
  activeLeaseId: leaseId,
  currentPropertyName: leaseId == null ? null : (propertyName ?? 'Studio Test'),
  activeLeasePeriodLabel: leaseId == null ? null : 'Depuis 01/01/2024',
  activeLeaseRentCents: leaseId == null ? null : 80000,
  activeLeaseChargesCents: leaseId == null ? null : 5000,
);

Widget _app(TenantListItem item) => MaterialApp.router(
  theme: AppTheme.light,
  locale: const Locale('fr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: supportedLocales,
  routerConfig: GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: TenantCard(item: item, onTap: () {}),
        ),
      ),
      GoRoute(path: '/leases/new', builder: (_, _) => const Text('new lease')),
      GoRoute(
        path: '/leases/:id',
        builder: (_, s) => Text('lease ${s.pathParameters['id']}'),
      ),
      GoRoute(path: '/tenants/:id/edit', builder: (_, _) => const Text('edit')),
    ],
  ),
);

void main() {
  late _FakeUrlLauncher launcher;
  late UrlLauncherPlatform previousLauncher;

  setUp(() {
    previousLauncher = UrlLauncherPlatform.instance;
    launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() => UrlLauncherPlatform.instance = previousLauncher);

  group('lancement Appeler / Email', () {
    testWidgets('Appeler compose un numéro tel: sans espaces', (t) async {
      await t.pumpWidget(_app(_item(leaseId: 'L1', phone: ' 06 12 34 56 78 ')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('card_call_t1')));
      await t.pumpAndSettle();

      expect(launcher.launched, ['tel:0612345678']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('échec d\'ouverture de l\'appel → SnackBar d\'erreur', (
      t,
    ) async {
      launcher.result = false;
      await t.pumpWidget(_app(_item(leaseId: 'L1', phone: '0612345678')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('card_call_t1')));
      await t.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text(
          lookupAppLocalizations(const Locale('fr')).tenantsLaunchFailed,
        ),
        findsOneWidget,
      );
    });

    testWidgets('échec d\'ouverture de l\'email → SnackBar d\'erreur', (
      t,
    ) async {
      launcher.result = false;
      await t.pumpWidget(_app(_item(leaseId: 'L1')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('card_email_t1')));
      await t.pumpAndSettle();

      expect(launcher.launched, ['mailto:jean@test.com']);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  testWidgets(
    'avec bail + téléphone : chiffre clé loyer+charges, action rapide '
    'Appeler, pas de bouton email, menu contient Envoyer un email',
    (t) async {
      await t.pumpWidget(_app(_item(leaseId: 'L1', phone: '0612345678')));
      await t.pumpAndSettle();

      expect(find.textContaining('850,00'), findsOneWidget);
      expect(find.text('CC / mois'), findsOneWidget);
      expect(find.byKey(const Key('card_call_t1')), findsOneWidget);
      expect(find.byKey(const Key('card_email_t1')), findsNothing);

      await t.tap(find.byIcon(Icons.more_vert));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('menu_email_t1')), findsOneWidget);
    },
  );

  testWidgets(
    'avec bail sans téléphone : action rapide email, menu ne contient '
    'plus Envoyer un email',
    (t) async {
      await t.pumpWidget(_app(_item(leaseId: 'L1')));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('card_email_t1')), findsOneWidget);
      expect(find.byKey(const Key('card_call_t1')), findsNothing);

      await t.tap(find.byIcon(Icons.more_vert));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('menu_email_t1')), findsNothing);
    },
  );

  testWidgets('avec bail : menu ⋮ → Voir le bail', (t) async {
    await t.pumpWidget(_app(_item(leaseId: 'L1', phone: '0612345678')));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('card_view_lease_t1')));
    await t.pumpAndSettle();

    expect(find.text('lease L1'), findsOneWidget);
  });

  testWidgets(
    'sans bail : action rapide "Créer un bail" → tap navigue vers new lease',
    (t) async {
      await t.pumpWidget(_app(_item()));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('card_create_lease_t1')));
      await t.pumpAndSettle();

      expect(find.text('new lease'), findsOneWidget);
    },
  );

  testWidgets('sans bail : menu ⋮ contient Envoyer un email et Modifier', (
    t,
  ) async {
    await t.pumpWidget(_app(_item()));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('menu_email_t1')), findsOneWidget);
    expect(find.byKey(const Key('card_edit_tenant_t1')), findsOneWidget);
  });
}
