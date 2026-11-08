/// Tests widget de [EtatDesLieuxListPage] (FEAT-037, tâche 7).
///
/// Couvre : empty state (+ CTA), liste avec 2 EDL (repo mocké), CTA "Nouvel
/// état des lieux" qui navigue vers `/leases/:id/etat-des-lieux/new`.
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/etat_des_lieux/data/etat_des_lieux_repository.dart';
import 'package:easyrent/features/etat_des_lieux/domain/edl_enums.dart';
import 'package:easyrent/features/etat_des_lieux/domain/etat_des_lieux.dart';
import 'package:easyrent/features/etat_des_lieux/presentation/etat_des_lieux_list_page.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake
// ---------------------------------------------------------------------------

class _FakeEtatDesLieuxRepository implements EtatDesLieuxRepository {
  _FakeEtatDesLieuxRepository({this.items = const []});

  final List<EtatDesLieux> items;

  @override
  Future<EtatDesLieux> create({
    required String leaseId,
    required EtatDesLieuxType type,
    required DateTime date,
    required List<EdlRoom> rooms,
    required EdlMeterReadings meterReadings,
    required int keysCount,
    String? generalComment,
  }) async => throw UnimplementedError();

  @override
  Future<List<EtatDesLieux>> listForLease(String leaseId) async => items;

  @override
  Future<EtatDesLieux> getById(String id) async => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

EtatDesLieux _makeEdl({
  required String id,
  EtatDesLieuxType type = EtatDesLieuxType.entree,
  DateTime? date,
}) => EtatDesLieux(
  id: id,
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  type: type,
  date: date ?? DateTime(2026, 9, 16),
  propertyAddress: '1 rue du Test, 75000 Paris',
  landlordFullName: 'Jean Bailleur',
  landlordAddress: '2 rue du Bailleur, 75000 Paris',
  tenantFullName: 'Marie Locataire',
  rooms: const [],
  meterReadings: EdlMeterReadings(),
  keysCount: 2,
  createdAt: DateTime(2026, 9, 16),
);

Widget _buildPage({required EtatDesLieuxRepository repo}) {
  final router = GoRouter(
    initialLocation: '/leases/lease-1/etat-des-lieux',
    routes: [
      GoRoute(
        path: '/leases/:id/etat-des-lieux',
        builder: (context, state) =>
            EtatDesLieuxListPage(leaseId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => Scaffold(
              body: Text('formulaire edl ${state.pathParameters['id']}'),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (context, state) =>
            Scaffold(body: Text('fiche bail ${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [etatDesLieuxRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(
      routerConfig: router,
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
  group('EtatDesLieuxListPage', () {
    testWidgets('empty state affiché quand aucun EDL', (tester) async {
      await tester.pumpWidget(_buildPage(repo: _FakeEtatDesLieuxRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Aucun état des lieux'), findsOneWidget);
      expect(find.byKey(const Key('btn_new_edl_empty')), findsOneWidget);
      expect(find.byKey(const Key('btn_new_edl')), findsNothing);
    });

    testWidgets('liste avec 2 EDL : type + date affichés', (tester) async {
      final repo = _FakeEtatDesLieuxRepository(
        items: [
          _makeEdl(
            id: 'edl-1',
            type: EtatDesLieuxType.entree,
            date: DateTime(2026, 1, 10),
          ),
          _makeEdl(
            id: 'edl-2',
            type: EtatDesLieuxType.sortie,
            date: DateTime(2026, 6, 20),
          ),
        ],
      );
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edl_tile_edl-1')), findsOneWidget);
      expect(find.byKey(const Key('edl_tile_edl-2')), findsOneWidget);
      expect(find.text('Entrée'), findsOneWidget);
      expect(find.text('Sortie'), findsOneWidget);
      expect(find.text('10/01/2026'), findsOneWidget);
      expect(find.text('20/06/2026'), findsOneWidget);
      expect(find.byKey(const Key('edl_pdf_button_edl-1')), findsOneWidget);
      expect(find.byKey(const Key('edl_pdf_button_edl-2')), findsOneWidget);
      expect(find.byKey(const Key('btn_new_edl')), findsOneWidget);
    });

    testWidgets(
      'CTA "Nouvel état des lieux" navigue vers le formulaire (empty)',
      (tester) async {
        await tester.pumpWidget(
          _buildPage(repo: _FakeEtatDesLieuxRepository()),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_new_edl_empty')));
        await tester.pumpAndSettle();

        expect(find.text('formulaire edl lease-1'), findsOneWidget);
      },
    );

    testWidgets(
      'CTA "Nouvel état des lieux" navigue vers le formulaire (liste)',
      (tester) async {
        final repo = _FakeEtatDesLieuxRepository(
          items: [_makeEdl(id: 'edl-1')],
        );
        await tester.pumpWidget(_buildPage(repo: repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_new_edl')));
        await tester.pumpAndSettle();

        expect(find.text('formulaire edl lease-1'), findsOneWidget);
      },
    );
  });
}
