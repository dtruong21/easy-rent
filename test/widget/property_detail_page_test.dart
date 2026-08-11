import 'dart:async';

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:easyrent/features/leases/domain/charge_mode.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/properties/application/property_detail_provider.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/heating_type.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/property_detail_page.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository (bien)
// ---------------------------------------------------------------------------

class _FakeRepo implements PropertyRepository {
  final Property? result;
  final bool throwNotFound;
  int archiveCalls = 0;

  _FakeRepo({this.result, this.throwNotFound = false});

  @override
  Future<Property> getById(String id) async {
    if (throwNotFound) throw PropertyNotFoundException(id);
    if (result == null) throw PropertyNotFoundException(id);
    return result!;
  }

  @override
  Future<List<Property>> list() async => result == null ? [] : [result!];

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
  Future<Property> update(Property property) async => property;

  @override
  Future<int> countActiveLeases(String propertyId) async => 0;

  @override
  Future<void> archive(String id) async {
    archiveCalls++;
  }

  @override
  Future<List<PropertyListItem>> listWithLeases() async => [];
}

// ---------------------------------------------------------------------------
// Fake repository (baux) — section "Baux actifs"
// ---------------------------------------------------------------------------

class _FakeLeaseRepo implements LeaseRepository {
  _FakeLeaseRepo({this.activeLeases = const [], this.loadError});

  final List<Map<String, dynamic>> activeLeases;
  final Exception? loadError;

  @override
  Future<List<Map<String, dynamic>>> listActiveLeasesForProperty(
    String propertyId,
  ) async {
    if (loadError != null) throw loadError!;
    return activeLeases;
  }

  @override
  Future<List<LeaseListItem>> listForDisplay({DateTime? now}) async => [];

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
    ChargeMode? chargeMode,
    int? depositAmountCents,
    int paymentDay = 1,
    PaymentMethod paymentMethod = PaymentMethod.virement,
    double? irlIndexValue,
    String? irlQuarterRef,
    int agencyFeesCents = 0,
    bool solidarityClause = false,
    bool entryInventoryDone = false,
    int nonRecoverableChargesCents = 0,
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

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Property _makeProperty({double? surfaceM2}) => Property(
  id: 'prop-1',
  landlordId: 'owner-1',
  name: 'Appart Lyon',
  address: '5 rue Mercière, 69001 Lyon',
  type: PropertyType.appartement,
  surfaceM2: surfaceM2,
  createdAt: DateTime(2024, 1, 15),
  updatedAt: DateTime(2024, 3, 20),
);

Widget _buildPage({
  required String propertyId,
  required _FakeRepo repo,
  LeaseRepository? leaseRepo,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, state) => PropertyDetailPage(id: propertyId),
      ),
      GoRoute(
        path: '/properties',
        builder: (context, _) => const Scaffold(body: Text('liste')),
      ),
      GoRoute(
        path: '/properties/:id/edit',
        builder: (context, state) =>
            Scaffold(body: Text('edit ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, state) =>
            Scaffold(body: Text('bail ${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      propertyRepositoryProvider.overrideWithValue(repo),
      leaseRepositoryProvider.overrideWithValue(leaseRepo ?? _FakeLeaseRepo()),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
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
  group('PropertyDetailPage', () {
    // -----------------------------------------------------------------------
    // Bien trouvé — affichage des champs
    // -----------------------------------------------------------------------
    testWidgets('affiche le nom du bien dans l\'AppBar', (tester) async {
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Appart Lyon'), findsWidgets);
    });

    testWidgets('affiche l\'adresse du bien', (tester) async {
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('5 rue Mercière, 69001 Lyon'), findsOneWidget);
    });

    testWidgets('affiche le type en français', (tester) async {
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Appartement'), findsOneWidget);
    });

    testWidgets('affiche la surface quand renseignée', (tester) async {
      final repo = _FakeRepo(result: _makeProperty(surfaceM2: 45.5));
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('45'), findsWidgets);
      expect(find.textContaining('m²'), findsWidgets);
    });

    testWidgets('n\'affiche pas la ligne surface si null', (tester) async {
      // Surface absente = la ligne "Surface" ne doit pas apparaître.
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Surface'), findsNothing);
    });

    testWidgets('bouton "Modifier" présent', (tester) async {
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_edit_property')), findsOneWidget);
    });

    testWidgets('bouton "Archiver ce bien" présent', (tester) async {
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_archive_property')), findsOneWidget);
    });

    testWidgets('date formatée DD/MM/YYYY — FR', (tester) async {
      // createdAt = 2024-01-15 → "15/01/2024"
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(_buildPage(propertyId: 'prop-1', repo: repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('15/01/2024'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Section "Baux actifs" (FEAT-005 — remplace le stub)
    // -----------------------------------------------------------------------
    testWidgets('section "Baux actifs" — état vide', (tester) async {
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(
        _buildPage(
          propertyId: 'prop-1',
          repo: repo,
          leaseRepo: _FakeLeaseRepo(activeLeases: const []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Baux actifs'), findsOneWidget);
      expect(find.text('Aucun bail actif pour ce bien.'), findsOneWidget);
    });

    testWidgets('section "Baux actifs" — affiche un bail actif', (
      tester,
    ) async {
      final repo = _FakeRepo(result: _makeProperty());
      await tester.pumpWidget(
        _buildPage(
          propertyId: 'prop-1',
          repo: repo,
          leaseRepo: _FakeLeaseRepo(
            activeLeases: const [
              {
                'id': 'lease-1',
                'property_id': 'prop-1',
                'start_date': '2024-01-01',
                'end_date': null,
                'status': 'active',
                'rent_amount_cents': 80000,
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Actif'), findsOneWidget);
      expect(find.textContaining('800,00'), findsOneWidget);
      expect(find.text('Voir le bail'), findsOneWidget);
    });

    testWidgets(
      'section "Baux actifs" — tap sur un bail navigue vers /leases/:id',
      (tester) async {
        final repo = _FakeRepo(result: _makeProperty());
        await tester.pumpWidget(
          _buildPage(
            propertyId: 'prop-1',
            repo: repo,
            leaseRepo: _FakeLeaseRepo(
              activeLeases: const [
                {
                  'id': 'lease-1',
                  'property_id': 'prop-1',
                  'start_date': '2024-01-01',
                  'end_date': null,
                  'status': 'active',
                  'rent_amount_cents': 80000,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // La section est sous la ligne de flottaison (SingleChildScrollView) —
        // il faut la faire défiler dans le viewport avant le tap.
        await tester.ensureVisible(find.text('Voir le bail'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Voir le bail'));
        await tester.pumpAndSettle();

        expect(find.text('bail lease-1'), findsOneWidget);
      },
    );

    testWidgets(
      'section "Baux actifs" — erreur de chargement affiche un message',
      (tester) async {
        final repo = _FakeRepo(result: _makeProperty());
        await tester.pumpWidget(
          _buildPage(
            propertyId: 'prop-1',
            repo: repo,
            leaseRepo: _FakeLeaseRepo(loadError: Exception('boom')),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Impossible de charger les baux.'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Bien introuvable (les Firestore Rules ne renvoient aucun document ou PropertyNotFoundException)
    // -----------------------------------------------------------------------
    testWidgets('cross-user / archivé — affiche "Bien introuvable"', (
      tester,
    ) async {
      final repo = _FakeRepo(throwNotFound: true);
      await tester.pumpWidget(_buildPage(propertyId: 'unknown-id', repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Bien introuvable'), findsOneWidget);
    });

    testWidgets('"Bien introuvable" — bouton "Retour à la liste" présent', (
      tester,
    ) async {
      final repo = _FakeRepo(throwNotFound: true);
      await tester.pumpWidget(_buildPage(propertyId: 'x', repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Retour à la liste'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // État loading
    // -----------------------------------------------------------------------
    testWidgets('CircularProgressIndicator pendant le chargement', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => const PropertyDetailPage(id: 'prop-1'),
          ),
          GoRoute(
            path: '/properties',
            builder: (context, _) => const Scaffold(body: Text('liste')),
          ),
        ],
      );

      // Override direct du provider pour rester en état loading.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            propertyDetailProvider.overrideWith(() => _LoadingDetailNotifier()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            locale: const Locale('fr'),
            supportedLocales: supportedLocales,
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

/// Notifier qui reste en état loading sans timer réel.
class _LoadingDetailNotifier extends PropertyDetailNotifier {
  @override
  Future<Property> build(String arg) async {
    state = const AsyncValue.loading();
    await Completer<void>().future;
    throw Exception('never');
  }
}
