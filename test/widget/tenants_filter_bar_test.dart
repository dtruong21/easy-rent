import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/tenants/application/tenants_filter_provider.dart';
import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_filter.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenants_filter_bar.dart';
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

/// Construit un widget pour tester la FilterBar dans un contexte desktop
/// (largeur >= 600px).
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
      child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
    ),
  );
}

/// Construit un widget pour tester la FilterBar en mode mobile
/// (largeur < 600px).
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
      child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TenantsFilterBar', () {
    testWidgets('desktop — SegmentedButton visible avec 3 segments', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [tenantRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildDesktop(container));
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton<TenantFilter>), findsOneWidget);
      expect(find.text('Tous'), findsOneWidget);
      expect(find.text('Actifs'), findsOneWidget);
      expect(find.text('Sans bail'), findsOneWidget);
    });

    testWidgets('mobile — DropdownButton visible (pas SegmentedButton)', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [tenantRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildMobile(container));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<TenantFilter>), findsOneWidget);
      expect(find.byType(SegmentedButton<TenantFilter>), findsNothing);
    });

    testWidgets(
      'desktop — sélection segment "Sans bail" → état provider = withoutActiveLease',
      (tester) async {
        final container = ProviderContainer(
          overrides: [tenantRepositoryProvider.overrideWithValue(_FakeRepo())],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildDesktop(container));
        await tester.pumpAndSettle();

        // Vérifier l'état initial
        expect(container.read(tenantFilterProvider), TenantFilter.all);

        // Taper sur "Sans bail"
        await tester.tap(find.text('Sans bail'));
        await tester.pumpAndSettle();

        expect(
          container.read(tenantFilterProvider),
          TenantFilter.withoutActiveLease,
        );
      },
    );

    testWidgets(
      'desktop — sélection segment "Actifs" → état provider = withActiveLease',
      (tester) async {
        final container = ProviderContainer(
          overrides: [tenantRepositoryProvider.overrideWithValue(_FakeRepo())],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildDesktop(container));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Actifs'));
        await tester.pumpAndSettle();

        expect(
          container.read(tenantFilterProvider),
          TenantFilter.withActiveLease,
        );
      },
    );
  });
}
