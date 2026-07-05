import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/leases/application/leases_filter_provider.dart';
import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_filter.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/leases/presentation/widgets/leases_filter_bar.dart';
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

class _FakeRepo implements LeaseRepository {
  @override
  Future<List<LeaseListItem>> listForDisplay() async => [];

  @override
  Future<Lease> getById(String id) async => throw UnimplementedError();

  @override
  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
    LeaseType leaseType = LeaseType.unfurnished,
    int? depositAmountCents,
    int paymentDay = 1,
    PaymentMethod paymentMethod = PaymentMethod.virement,
    double? irlIndexValue,
    String? irlQuarterRef,
    int agencyFeesCents = 0,
    bool solidarityClause = false,
    bool entryInventoryDone = false,
  }) async => throw UnimplementedError();

  @override
  Future<Lease> update(Lease lease) async => throw UnimplementedError();

  @override
  Future<Lease> close(String id, {required DateTime effectiveEndDate}) async =>
      throw UnimplementedError();

  @override
  Future<bool> hasOtherActiveLeaseOnProperty(
    String propertyId, {
    String? excludeLeaseId,
  }) async => false;

  @override
  Future<void> archive(String id) async {}
}

/// Construit un widget pour tester la FilterBar dans un contexte desktop
/// (largeur >= 600px).
Widget _buildDesktop(ProviderContainer container) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => const Scaffold(body: LeasesFilterBar()),
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
        builder: (context, _) => const Scaffold(body: LeasesFilterBar()),
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
  group('LeasesFilterBar', () {
    testWidgets('desktop — SegmentedButton visible avec 5 segments '
        '(FEAT-028 ajoute « En retard »)', (tester) async {
      final container = ProviderContainer(
        overrides: [leaseRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildDesktop(container));
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton<LeaseFilter>), findsOneWidget);
      expect(find.text('Tous'), findsOneWidget);
      expect(find.text('Actifs'), findsOneWidget);
      expect(find.text('À renouveler'), findsOneWidget);
      expect(find.text('En retard'), findsOneWidget);
      expect(find.text('Terminés'), findsOneWidget);
    });

    testWidgets(
      'desktop — sélection segment "En retard" → état provider = late',
      (tester) async {
        final container = ProviderContainer(
          overrides: [leaseRepositoryProvider.overrideWithValue(_FakeRepo())],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildDesktop(container));
        await tester.pumpAndSettle();

        await tester.tap(find.text('En retard'));
        await tester.pumpAndSettle();

        expect(container.read(leaseFilterProvider), LeaseFilter.late);
      },
    );

    testWidgets('mobile — DropdownButton visible (pas SegmentedButton)', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [leaseRepositoryProvider.overrideWithValue(_FakeRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildMobile(container));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<LeaseFilter>), findsOneWidget);
      expect(find.byType(SegmentedButton<LeaseFilter>), findsNothing);
    });

    testWidgets(
      'desktop — sélection segment "Terminés" → état provider = terminated',
      (tester) async {
        final container = ProviderContainer(
          overrides: [leaseRepositoryProvider.overrideWithValue(_FakeRepo())],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildDesktop(container));
        await tester.pumpAndSettle();

        // Vérifier l'état initial
        expect(container.read(leaseFilterProvider), LeaseFilter.all);

        // Taper sur "Terminés"
        await tester.tap(find.text('Terminés'));
        await tester.pumpAndSettle();

        expect(container.read(leaseFilterProvider), LeaseFilter.terminated);
      },
    );
  });
}
