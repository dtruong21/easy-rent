import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/tenants/application/tenants_filter_provider.dart';
import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_filter.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenants_filter_bar.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements TenantRepository {
  @override
  Future<List<Tenant>> list() async => [];

  @override
  Future<Tenant> getById(String id) async => throw UnimplementedError();

  @override
  Future<Tenant> create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    DateTime? birthDate,
    String? birthPlace,
    String? nationality,
    String? profession,
    String? employer,
    int? monthlyIncomeCents,
    String? previousAddress,
    String? guarantorName,
    String? guarantorEmail,
    String? guarantorPhone,
  }) async => throw UnimplementedError();

  @override
  Future<Tenant> update(Tenant tenant) async => throw UnimplementedError();

  @override
  Future<int> countActiveLeases(String tenantId) async => 0;

  @override
  Future<void> archive(String id) async {}

  @override
  Future<List<TenantListItem>> listWithActiveLeases() async => [];

  @override
  Future<List<Map<String, dynamic>>> listLeasesForTenant(
    String tenantId,
  ) async => [];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

Widget _buildDesktop(ProviderContainer container) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => const Scaffold(body: TenantsFilterBar()),
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
        builder: (context, _) => const Scaffold(body: TenantsFilterBar()),
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
  group('TenantsFilterBar', () {
    testWidgets('desktop — puces de filtre visibles avec ViewModeToggle', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [tenantRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildDesktop(container));
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('filter_chip_${TenantFilter.all}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('filter_chip_${TenantFilter.withActiveLease}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('filter_chip_${TenantFilter.withoutActiveLease}')),
        findsOneWidget,
      );
      expect(find.textContaining('Tous'), findsOneWidget);
      expect(find.textContaining('Actifs'), findsOneWidget);
      expect(find.textContaining('Sans bail'), findsOneWidget);
    });

    testWidgets('mobile — puces de filtre visibles', (tester) async {
      final container = ProviderContainer(
        overrides: [tenantRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildMobile(container));
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('filter_chip_${TenantFilter.all}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('filter_chip_${TenantFilter.withActiveLease}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('filter_chip_${TenantFilter.withoutActiveLease}')),
        findsOneWidget,
      );
    });

    testWidgets(
      'desktop — tap puce "Sans bail" → état provider = withoutActiveLease',
      (tester) async {
        final container = ProviderContainer(
          overrides: [tenantRepositoryProvider.overrideWithValue(_FakeRepo())],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildDesktop(container));
        await tester.pumpAndSettle();

        expect(container.read(tenantFilterProvider), TenantFilter.all);

        await tester.tap(
          find.byKey(Key('filter_chip_${TenantFilter.withoutActiveLease}')),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(tenantFilterProvider),
          TenantFilter.withoutActiveLease,
        );
      },
    );

    testWidgets(
      'desktop — tap puce "Actifs" → état provider = withActiveLease',
      (tester) async {
        final container = ProviderContainer(
          overrides: [tenantRepositoryProvider.overrideWithValue(_FakeRepo())],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildDesktop(container));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(Key('filter_chip_${TenantFilter.withActiveLease}')),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(tenantFilterProvider),
          TenantFilter.withActiveLease,
        );
      },
    );
  });
}
