import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/properties/application/properties_filter_provider.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/heating_type.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_filter.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/widgets/properties_filter_bar.dart';
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

class _FakeRepo implements PropertyRepository {
  @override
  Future<List<Property>> list() async => [];

  @override
  Future<List<PropertyListItem>> listWithLeases() async => [];

  @override
  Future<Property> getById(String id) async => throw UnimplementedError();

  @override
  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
    String? postalCode,
    String? city,
    int? rooms,
    int? bedrooms,
    int? floor,
    bool hasElevator = false,
    bool furnished = false,
    HeatingType? heatingType,
    String? dpeLetter,
    int? dpeValueKwhM2Year,
    String? gesLetter,
    int? constructionYear,
    int? purchasePriceCents,
    DateTime? purchaseDate,
    int? notaryFeesCents,
    bool isNewProperty = false,
    int? propertyTaxAnnualCents,
    int? insurancePnoAnnualCents,
    int? condoFeesNonRecoverableCents,
    int? loanPrincipalCents,
    int? loanRateBps,
    int? loanInsuranceBps,
    int? loanDurationMonths,
    DateTime? loanStartDate,
    int? loanMonthlyPaymentOverrideCents,
  }) async => throw UnimplementedError();

  @override
  Future<Property> update(Property property) async =>
      throw UnimplementedError();

  @override
  Future<int> countActiveLeases(String propertyId) async => 0;

  @override
  Future<void> archive(String id) async {}
}

Widget _buildDesktop(ProviderContainer container) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => const Scaffold(body: PropertiesFilterBar()),
      ),
    ],
  );

  return UncontrolledProviderScope(
    container: container,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: MaterialApp.router(
        routerConfig: router,
        theme: _appTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('fr'),
        supportedLocales: supportedLocales,
      ),
    ),
  );
}

Widget _buildMobile(ProviderContainer container) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => const Scaffold(body: PropertiesFilterBar()),
      ),
    ],
  );

  return UncontrolledProviderScope(
    container: container,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(375, 667)),
      child: MaterialApp.router(
        routerConfig: router,
        theme: _appTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('fr'),
        supportedLocales: supportedLocales,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PropertiesFilterBar', () {
    testWidgets('desktop — puces de filtre visibles avec ViewModeToggle', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [propertyRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildDesktop(container));
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('filter_chip_${PropertyFilter.all}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('filter_chip_${PropertyFilter.occupied}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('filter_chip_${PropertyFilter.vacant}')),
        findsOneWidget,
      );
      expect(find.textContaining('Tous'), findsOneWidget);
      expect(find.textContaining('Loués'), findsOneWidget);
      expect(find.textContaining('Vacants'), findsOneWidget);
    });

    testWidgets('mobile — puces de filtre visibles', (tester) async {
      final container = ProviderContainer(
        overrides: [propertyRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildMobile(container));
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('filter_chip_${PropertyFilter.all}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('filter_chip_${PropertyFilter.occupied}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('filter_chip_${PropertyFilter.vacant}')),
        findsOneWidget,
      );
    });

    testWidgets('desktop — tap puce "Loués" → état provider = occupied', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [propertyRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildDesktop(container));
      await tester.pumpAndSettle();

      expect(container.read(propertyFilterProvider), PropertyFilter.all);

      await tester.tap(
        find.byKey(Key('filter_chip_${PropertyFilter.occupied}')),
      );
      await tester.pumpAndSettle();

      expect(container.read(propertyFilterProvider), PropertyFilter.occupied);
    });

    testWidgets('desktop — tap puce "Vacants" → état provider = vacant', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [propertyRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildDesktop(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('filter_chip_${PropertyFilter.vacant}')));
      await tester.pumpAndSettle();

      expect(container.read(propertyFilterProvider), PropertyFilter.vacant);
    });
  });
}
