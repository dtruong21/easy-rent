import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/presentation/lease_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements LeaseRepository {
  final Lease? lease;
  final bool notFound;

  const _FakeRepo({this.lease, this.notFound = false});

  @override
  Future<Lease> getById(String id) async {
    if (notFound || lease == null) throw LeaseNotFoundException(id);
    return lease!;
  }

  @override
  Future<List<LeaseListItem>> listForDisplay() async => [];

  @override
  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
  }) async => throw UnimplementedError();

  @override
  Future<Lease> update(Lease lease) async => lease;

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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Lease _makeLease({
  String id = 'lease-1',
  LeaseStatus status = LeaseStatus.active,
  DateTime? endDate,
}) => Lease(
  id: id,
  landlordId: 'owner-1',
  propertyId: 'prop-1',
  tenantId: 'tenant-1',
  rentAmountCents: 85000,
  chargesAmountCents: 5000,
  startDate: DateTime(2024, 1, 1),
  endDate: endDate,
  status: status,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Widget _buildDetailPage({required String leaseId, required _FakeRepo repo}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => LeaseDetailPage(id: leaseId),
      ),
      GoRoute(
        path: '/leases',
        builder: (context, _) => const Scaffold(body: Text('liste baux')),
      ),
      GoRoute(
        path: '/leases/:id/edit',
        builder: (_, state) =>
            Scaffold(body: Text('edit ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/properties/:id',
        builder: (_, state) =>
            Scaffold(body: Text('property ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/tenants/:id',
        builder: (_, state) =>
            Scaffold(body: Text('tenant ${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [leaseRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LeaseDetailPage', () {
    // -----------------------------------------------------------------------
    // Affichage des champs
    // -----------------------------------------------------------------------
    testWidgets('affiche le badge de statut "Actif"', (tester) async {
      final lease = _makeLease(status: LeaseStatus.active);
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Actif'), findsOneWidget);
    });

    testWidgets('affiche le loyer HC formaté', (tester) async {
      final lease = _makeLease();
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      // 85000 centimes = 850,00 €
      expect(find.textContaining('850'), findsWidgets);
    });

    testWidgets('affiche la date de début au format DD/MM/YYYY', (
      tester,
    ) async {
      final lease = _makeLease();
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('01/01/2024'), findsOneWidget);
    });

    testWidgets('affiche "(CDI)" si end_date est null', (tester) async {
      final lease = _makeLease(endDate: null);
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('(CDI)'), findsOneWidget);
    });

    testWidgets('affiche la date de fin si end_date est renseignée', (
      tester,
    ) async {
      final lease = _makeLease(endDate: DateTime(2025, 6, 30));
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('30/06/2025'), findsOneWidget);
    });

    testWidgets('section paiements placeholder visible', (tester) async {
      final lease = _makeLease();
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('FEAT-006'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Bouton "Modifier"
    // -----------------------------------------------------------------------
    testWidgets('bouton "Modifier" (icône) présent', (tester) async {
      final lease = _makeLease();
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_edit_lease')), findsOneWidget);
    });

    testWidgets('tap "Modifier" navigue vers /leases/:id/edit', (tester) async {
      final lease = _makeLease(id: 'lease-xyz');
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_edit_lease')));
      await tester.pumpAndSettle();

      expect(find.text('edit lease-xyz'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Bouton "Clôturer" — conditionnel au statut
    // -----------------------------------------------------------------------
    testWidgets('bail actif — bouton "Clôturer ce bail" visible', (
      tester,
    ) async {
      final lease = _makeLease(status: LeaseStatus.active);
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_close_lease')), findsOneWidget);
    });

    testWidgets('bail terminé — bouton "Clôturer ce bail" masqué', (
      tester,
    ) async {
      final lease = _makeLease(
        status: LeaseStatus.terminated,
        endDate: DateTime(2024, 12, 31),
      );
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_close_lease')), findsNothing);
    });

    testWidgets('bail terminé — badge "Terminé" visible', (tester) async {
      final lease = _makeLease(
        status: LeaseStatus.terminated,
        endDate: DateTime(2024, 12, 31),
      );
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Terminé'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Bouton "Archiver"
    // -----------------------------------------------------------------------
    testWidgets('bouton "Archiver ce bail" présent', (tester) async {
      final lease = _makeLease();
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_archive_lease')), findsOneWidget);
    });

    testWidgets('tap "Archiver" ouvre le dialog de confirmation', (
      tester,
    ) async {
      final lease = _makeLease();
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to the button in case it's below the fold
      await tester.ensureVisible(find.byKey(const Key('btn_archive_lease')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('btn_archive_lease')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Archiver ce bail ?'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Tap "Clôturer" ouvre CloseLeaseDialog
    // -----------------------------------------------------------------------
    testWidgets('tap "Clôturer" ouvre le dialog CloseLeaseDialog', (
      tester,
    ) async {
      final lease = _makeLease(status: LeaseStatus.active);
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('btn_close_lease')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('btn_close_lease')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // The dialog title "Clôturer ce bail" is shown (button also has that label)
      expect(find.text('Clôturer ce bail'), findsWidgets);
      // Verify at least the confirm button of the dialog is present
      expect(find.byKey(const Key('btn_close_lease_confirm')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Cross-user / "Bail introuvable" (RLS 0 ligne)
    // -----------------------------------------------------------------------
    testWidgets('cross-user — affiche "Bail introuvable"', (tester) async {
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: 'foreign-lease-id',
          repo: const _FakeRepo(notFound: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bail introuvable'), findsOneWidget);
    });

    testWidgets('cross-user — affiche bouton "Retour à la liste"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: 'foreign-lease-id',
          repo: const _FakeRepo(notFound: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Retour'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Liens property / tenant
    // -----------------------------------------------------------------------
    testWidgets('tap lien "Bien" navigue vers /properties/:propertyId', (
      tester,
    ) async {
      final lease = _makeLease();
      await tester.pumpWidget(
        _buildDetailPage(
          leaseId: lease.id,
          repo: _FakeRepo(lease: lease),
        ),
      );
      await tester.pumpAndSettle();

      // Le lien "Voir la fiche" sous "Bien" est le premier InkWell dans la card
      final inkWells = tester.widgetList<InkWell>(find.byType(InkWell));
      // Trouver l'InkWell de la row "Bien"
      await tester.tap(find.widgetWithText(InkWell, 'Voir la fiche').first);
      await tester.pumpAndSettle();

      // Vérifier qu'on est sur la page property
      expect(find.textContaining('property'), findsOneWidget);
      // inkWells reference used above for the test
      expect(inkWells, isNotNull);
    });
  });
}
