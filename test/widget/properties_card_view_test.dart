import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/widgets/properties_card_view.dart';
import 'package:easyrent/features/properties/presentation/widgets/property_card.dart';
import 'package:easyrent/features/properties/presentation/widgets/property_color_dot.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

Property _makeProperty({String id = 'p1', String name = 'Appartement Test'}) =>
    Property(
      id: id,
      landlordId: 'owner',
      name: name,
      address: '1 rue Test, 75001 Paris',
      type: PropertyType.appartement,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

PropertyListItem _makeItem({
  String id = 'p1',
  String name = 'Appartement Test',
  String? activeLeaseId,
  String? tenantName,
}) => PropertyListItem(
  property: _makeProperty(id: id, name: name),
  activeLeaseId: activeLeaseId,
  currentTenantName: tenantName,
  currentRentLabel: activeLeaseId != null ? '1 200,00 € CC / mois' : null,
);

Widget _buildCardView(List<PropertyListItem> items) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) =>
            Scaffold(body: PropertiesCardView(properties: items)),
      ),
      GoRoute(
        path: '/properties/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/properties/:id/edit',
        builder: (_, state) =>
            Scaffold(body: Text('edit ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, state) =>
            Scaffold(body: Text('lease ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/leases/new',
        builder: (context, _) => const Scaffold(body: Text('new lease')),
      ),
    ],
  );

  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      theme: _appTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PropertiesCardView', () {
    testWidgets('0 item — affiche aucune PropertyCard', (tester) async {
      await tester.pumpWidget(_buildCardView([]));
      await tester.pumpAndSettle();

      expect(find.byType(PropertyCard), findsNothing);
    });

    testWidgets('3 items — affiche 3 PropertyCard', (tester) async {
      final items = [
        _makeItem(id: 'p1', name: 'Bien 1'),
        _makeItem(id: 'p2', name: 'Bien 2'),
        _makeItem(id: 'p3', name: 'Bien 3'),
      ];

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      expect(find.byType(PropertyCard), findsNWidgets(3));
      expect(find.text('Bien 1'), findsOneWidget);
      expect(find.text('Bien 2'), findsOneWidget);
      expect(find.text('Bien 3'), findsOneWidget);
    });

    testWidgets('6 items — affiche 6 PropertyCard', (tester) async {
      final items = List.generate(
        6,
        (i) => _makeItem(id: 'p$i', name: 'Bien $i'),
      );

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      expect(find.byType(PropertyCard), findsNWidgets(6));
    });

    testWidgets('tap card → navigue vers /properties/:id', (tester) async {
      final items = [_makeItem(id: 'prop-xyz', name: 'Bien Test')];

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bien Test'));
      await tester.pumpAndSettle();

      expect(find.text('detail prop-xyz'), findsOneWidget);
    });

    testWidgets('état loading — affiche aucune PropertyCard', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) =>
                Scaffold(body: PropertiesCardView.loading()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            theme: _appTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            locale: const Locale('fr'),
            supportedLocales: supportedLocales,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PropertyCard), findsNothing);
    });

    testWidgets('bien vacant → pill "Vacant" visible', (tester) async {
      final items = [_makeItem(id: 'pv', name: 'Bien Vacant')];

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      expect(find.text('Vacant'), findsOneWidget);
    });

    testWidgets('bien loué → pill "Loué" visible', (tester) async {
      final items = [
        _makeItem(
          id: 'pl',
          name: 'Bien Loué',
          activeLeaseId: 'l1',
          tenantName: 'Jean Dupont',
        ),
      ];

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      expect(find.text('Loué'), findsOneWidget);
    });

    testWidgets(
      'chaque bien affiche sa pastille de couleur d\'identité (FEAT-057) — '
      'même un bien "legacy" sans colorKey stockée (repli déterministe, '
      'jamais sans couleur)',
      (tester) async {
        final items = [
          _makeItem(id: 'p1', name: 'Bien 1'),
          _makeItem(id: 'p2', name: 'Bien 2'),
        ];

        await tester.pumpWidget(_buildCardView(items));
        await tester.pumpAndSettle();

        expect(find.byType(PropertyColorDot), findsNWidgets(2));
      },
    );
  });
}
