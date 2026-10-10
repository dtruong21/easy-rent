/// Tests de [FirestoreLeaseRepository.listForDisplay] via
/// fake_cloud_firestore — FEAT-028 : calcul du champ [LeaseListItem.isLate].
///
/// Couvre le chargement des paiements par bail actif (chunk whereIn) et son
/// branchement vers `isLeaseLate()` — la logique de calcul pure elle-même
/// est testée exhaustivement dans `lease_lateness_test.dart`.
///
/// ## Déterminisme (fix bug flaky-par-date)
///
/// `listForDisplay()` accepte un paramètre `now` optionnel (défaut
/// `DateTime.now()` côté prod, jamais fourni par les appelants réels). Tous
/// les tests ci-dessous ancrent leurs scénarios sur un `now` FIXE
/// ([_fixedNow]) plutôt que sur `DateTime.now()` réel : les dates de seed
/// sont construites relativement à ce `now` fixe, ce qui rend les tests
/// verts quel que soit le jour réel d'exécution (plus de dépendance à la
/// date du jour — cf. régressions du 2026-07-04 et du 2026-07-06 causées par
/// des tests ancrés sur `DateTime.now()` réel).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

/// [FirebaseFunctions] jamais invoqué par listForDisplay — toute
/// utilisation inattendue fait échouer le test.
class _UnusedFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'FirebaseFunctions ne doit pas être appelé par listForDisplay',
  );
}

/// Horloge fixe (milieu de mois, loin des bornes de fin de mois/année) pour
/// que tous les scénarios ci-dessous soient déterministes, quel que soit le
/// jour réel d'exécution du test.
final _fixedNow = DateTime(2026, 3, 15);

void main() {
  const uid = 'landlord-1';

  late FakeFirebaseFirestore firestore;
  late FirestoreLeaseRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));
    repo = FirestoreLeaseRepository(firestore, auth, _UnusedFunctions());
  });

  Future<void> seedLease({
    required String id,
    String status = 'active',
    required DateTime startDate,
    int paymentDay = 1,
  }) async {
    await firestore.collection('leases').doc(id).set({
      'landlordId': uid,
      'propertyId': 'p1',
      'tenantId': 't1',
      'rentAmountCents': 80000,
      'chargesAmountCents': 5000,
      'startDate': Timestamp.fromDate(startDate),
      'status': status,
      'paymentDay': paymentDay,
      'propertyName': 'Studio Test',
      'tenantFirstName': 'Jean',
      'tenantLastName': 'Dupont',
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'deletedAt': null,
    });
  }

  Future<void> seedPayment({
    required String id,
    required String leaseId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    await firestore.collection('payments').doc(id).set({
      'landlordId': uid,
      'leaseId': leaseId,
      'periodStart': Timestamp.fromDate(periodStart),
      'periodEnd': Timestamp.fromDate(periodEnd),
      'paidAt': Timestamp.fromDate(periodStart),
      'rentAmountCents': 80000,
      'chargesAmountCents': 5000,
      'paymentMethod': 'virement',
      'createdAt': Timestamp.fromDate(periodStart),
      'updatedAt': Timestamp.fromDate(periodStart),
      'deletedAt': null,
    });
  }

  group('FirestoreLeaseRepository.listForDisplay — isLate (FEAT-028)', () {
    test('bail actif, échéance dépassée + grâce écoulée, aucun paiement → '
        'isLate=true', () async {
      // paymentDay=1, démarré il y a longtemps → l'échéance du mois en
      // cours (quel qu'il soit) est nécessairement dépassée de plus de 5
      // jours par rapport à `now` fixe utilisé par le repo.
      await seedLease(id: 'l1', startDate: DateTime(2020, 1, 1));

      final items = await repo.listForDisplay(now: _fixedNow);

      expect(items, hasLength(1));
      expect(items.single.isLate, isTrue);
    });

    test('bail actif payé pour le mois en cours → isLate=false', () async {
      // Le « mois dû courant » (avec délai de grâce de 5 jours, cf.
      // lease_lateness.dart) n'est PAS toujours le mois calendaire de
      // `now` : les 5 premiers jours d'un mois, le mois dû courant est
      // encore le mois PRÉCÉDENT (grâce pas expirée avant le 6 du mois).
      // On paie ici les DEUX mois candidats (précédent + courant, relatifs
      // à `_fixedNow`) pour rester robuste sans dupliquer la logique de
      // grâce dans le test lui-même.
      await seedLease(id: 'l1', startDate: DateTime(2020, 1, 1));
      final previousMonthStart = DateTime(
        _fixedNow.year,
        _fixedNow.month - 1,
        1,
      );
      final currentMonthEnd = DateTime(_fixedNow.year, _fixedNow.month + 1, 0);
      await seedPayment(
        id: 'pay1',
        leaseId: 'l1',
        periodStart: previousMonthStart,
        periodEnd: currentMonthEnd,
      );

      final items = await repo.listForDisplay(now: _fixedNow);

      expect(items.single.isLate, isFalse);
    });

    test('bail terminated sans aucun paiement → isLate=false (jamais en '
        'retard, quel que soit le statut de paiement)', () async {
      await seedLease(
        id: 'l1',
        status: 'terminated',
        startDate: DateTime(2020, 1, 1),
      );

      final items = await repo.listForDisplay(now: _fixedNow);

      expect(items.single.isLate, isFalse);
    });

    test(
      'bail créé aujourd\'hui, encore dans le délai de grâce → isLate=false',
      () async {
        await seedLease(
          id: 'l1',
          startDate: _fixedNow,
          paymentDay: _fixedNow.day,
        );

        final items = await repo.listForDisplay(now: _fixedNow);

        expect(items.single.isLate, isFalse);
      },
    );

    test('plusieurs baux actifs (>30, chunk whereIn) → chaque isLate calculé '
        'indépendamment', () async {
      // Régression du chunking whereIn (limite Firestore à 30 valeurs) :
      // 35 baux en retard, aucun payé — tous doivent être détectés malgré
      // le découpage en 2 chunks (30 + 5).
      for (var i = 0; i < 35; i++) {
        await seedLease(id: 'l$i', startDate: DateTime(2020, 1, 1));
      }

      final items = await repo.listForDisplay(now: _fixedNow);

      expect(items, hasLength(35));
      expect(items.every((item) => item.isLate), isTrue);
    });
  });

  group('FirestoreLeaseRepository.listForDisplay — régression fuseau horaire '
      '(seed comme la prod)', () {
    // La Cloud Function `createLease` reçoit `startDate.toUtc()
    // .toIso8601String()` (cf. lease_repository.dart::create()) : le
    // Timestamp Firestore résultant représente exactement le même instant
    // que `Timestamp.fromDate(local.toUtc())` ici. Le point sensible n'est
    // PAS l'écriture (un Timestamp est un instant absolu, peu importe la
    // forme utilisée pour le construire) mais la RELECTURE via
    // `firestoreDocToSnakeJson` (`.toDate().toUtc().toIso8601String()`,
    // cf. core/firestore_helpers.dart) qui renvoie systématiquement une
    // chaîne UTC — d'où le bug de `_dateOnly` sans `.toLocal()` corrigé
    // dans lease_lateness.dart. Ce test seed exactement comme la prod pour
    // exercer ce chemin bout-en-bout (pas seulement `isLeaseLate` en
    // isolation, déjà couvert par lease_lateness_test.dart).
    test('bail démarré à MINUIT local il y a 5 jours (seedé .toUtc(), comme '
        'la prod — un date picker saisit toujours minuit local), '
        'paymentDay = (jour de démarrage − 1) → isLate=false : le mois de '
        'démarrage n\'est PAS éligible (paymentDay < jour de démarrage → '
        'échéance du mois de démarrage déjà passée à la signature → on '
        'saute au mois suivant, qui n\'est lui-même pas encore atteint '
        '5 jours après le démarrage)', () async {
      // `now` est fixé à `_fixedNow` (injecté via `listForDisplay(now:)`) —
      // le scénario est ancré dessus plutôt que sur `DateTime.now()` réel,
      // pour rester déterministe quel que soit le jour d'exécution du
      // test. `paymentDay = jour démarrage - 1` garantit que le mois de
      // démarrage est écarté (échéance déjà passée au jour de signature,
      // cf. règle "pas de proratisation"), et le mois suivant — seul mois
      // éligible — démarre au moins ~25 jours après `startDate`, donc
      // largement après `_fixedNow` (`startDate + 5 jours`) : aucun mois
      // dû, quel que soit le mois choisi pour `_fixedNow`.
      //
      // IMPORTANT : startDate est construit à MINUIT local explicite
      // (DateTime(y,m,d), pas `_fixedNow - 5j` qui garderait l'heure de
      // `_fixedNow`) — c'est le cas réel de prod (date picker) ET c'est ce
      // qui garantit de franchir la frontière du jour civil lors de la
      // conversion UTC en zone UTC+1/+2 (minuit local = 22h/23h UTC la
      // veille), donc de reproduire le symptôme du bug corrigé
      // (contrairement à une heure de journée quelconque, qui peut rester
      // dans le même jour UTC selon le moment considéré).
      final fiveDaysAgo = _fixedNow.subtract(const Duration(days: 5));
      final startDateLocalMidnight = DateTime(
        fiveDaysAgo.year,
        fiveDaysAgo.month,
        fiveDaysAgo.day,
      );
      final paymentDay = startDateLocalMidnight.day > 1
          ? startDateLocalMidnight.day - 1
          : 1;

      await seedLease(
        id: 'l1',
        startDate: startDateLocalMidnight.toUtc(),
        paymentDay: paymentDay,
      );

      final items = await repo.listForDisplay(now: _fixedNow);

      expect(items.single.isLate, isFalse);
    });
  });

  group('FirestoreLeaseRepository.listForDisplay — propertyColorKey '
      '(FEAT-057, lecture groupée)', () {
    test('bien avec colorKey personnalisée → propagée sur le LeaseListItem '
        '(pas de requête supplémentaire par bail)', () async {
      await firestore.collection('properties').doc('p1').set({
        'landlordId': uid,
        'name': 'Studio Test',
        'address': '1 rue Test',
        'type': 'studio',
        'colorKey': 'cobalt',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'deletedAt': null,
      });
      await seedLease(id: 'l1', startDate: DateTime(2020, 1, 1));

      final items = await repo.listForDisplay(now: _fixedNow);

      expect(items.single.propertyColorKey, 'cobalt');
    });

    test('bien sans colorKey (créé avant FEAT-057) → propertyColorKey null '
        'sur le LeaseListItem (le repli déterministe se fait à '
        "l'affichage, pas ici)", () async {
      await firestore.collection('properties').doc('p1').set({
        'landlordId': uid,
        'name': 'Studio Test',
        'address': '1 rue Test',
        'type': 'studio',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'deletedAt': null,
      });
      await seedLease(id: 'l1', startDate: DateTime(2020, 1, 1));

      final items = await repo.listForDisplay(now: _fixedNow);

      expect(items.single.propertyColorKey, isNull);
    });

    test('bien introuvable (archivé/supprimé) → propertyColorKey null, pas '
        "d'erreur", () async {
      await seedLease(id: 'l1', startDate: DateTime(2020, 1, 1));

      final items = await repo.listForDisplay(now: _fixedNow);

      expect(items.single.propertyColorKey, isNull);
    });

    test('deux baux sur deux biens distincts → chaque item porte la '
        'couleur du BON bien (pas de mélange)', () async {
      await firestore.collection('properties').doc('p1').set({
        'landlordId': uid,
        'name': 'Studio A',
        'address': '1 rue A',
        'type': 'studio',
        'colorKey': 'cobalt',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'deletedAt': null,
      });
      await firestore.collection('properties').doc('p2').set({
        'landlordId': uid,
        'name': 'Studio B',
        'address': '2 rue B',
        'type': 'studio',
        'colorKey': 'sauge',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'deletedAt': null,
      });
      await seedLease(id: 'l1', startDate: DateTime(2020, 1, 1));
      await firestore.collection('leases').doc('l2').set({
        'landlordId': uid,
        'propertyId': 'p2',
        'tenantId': 't2',
        'rentAmountCents': 90000,
        'chargesAmountCents': 0,
        'startDate': Timestamp.fromDate(DateTime(2020, 1, 1)),
        'status': 'terminated',
        'paymentDay': 1,
        'propertyName': 'Studio B',
        'tenantFirstName': 'Marie',
        'tenantLastName': 'Curie',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'deletedAt': null,
      });

      final items = await repo.listForDisplay(now: _fixedNow);
      final byId = {for (final item in items) item.lease.id: item};

      expect(byId['l1']!.propertyColorKey, 'cobalt');
      expect(byId['l2']!.propertyColorKey, 'sauge');
    });
  });

  group('FirestoreLeaseRepository.listActiveLeasesForProperty — '
      'section "Baux actifs" fiche bien (FEAT-005)', () {
    test('bien sans bail → liste vide', () async {
      final leases = await repo.listActiveLeasesForProperty('p1');

      expect(leases, isEmpty);
    });

    test('un bail actif sur le bien → renvoyé au format snake_case', () async {
      await seedLease(id: 'l1', startDate: DateTime(2024, 6, 1));

      final leases = await repo.listActiveLeasesForProperty('p1');

      expect(leases, hasLength(1));
      expect(leases.single['id'], 'l1');
      expect(leases.single['property_id'], 'p1');
      expect(leases.single['status'], 'active');
      expect(leases.single['rent_amount_cents'], 80000);
      expect(leases.single['start_date'], isNotNull);
    });

    test('bail terminated sur le bien → exclu (section "Baux actifs" '
        'seulement)', () async {
      await seedLease(
        id: 'l1',
        status: 'terminated',
        startDate: DateTime(2023, 1, 1),
      );

      final leases = await repo.listActiveLeasesForProperty('p1');

      expect(leases, isEmpty);
    });

    test('bail actif soft-supprimé → exclu', () async {
      await seedLease(id: 'l1', startDate: DateTime(2024, 1, 1));
      await firestore.collection('leases').doc('l1').update({
        'deletedAt': Timestamp.fromDate(DateTime(2024, 6, 1)),
      });

      final leases = await repo.listActiveLeasesForProperty('p1');

      expect(leases, isEmpty);
    });

    test('bail actif d\'un autre bien → exclu (filtre propertyId)', () async {
      await firestore.collection('leases').doc('l1').set({
        'landlordId': uid,
        'propertyId': 'autre-bien',
        'tenantId': 't1',
        'rentAmountCents': 50000,
        'chargesAmountCents': 0,
        'startDate': Timestamp.fromDate(DateTime(2024, 1, 1)),
        'status': 'active',
        'paymentDay': 1,
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
        'deletedAt': null,
      });

      final leases = await repo.listActiveLeasesForProperty('p1');

      expect(leases, isEmpty);
    });

    test(
      'bail actif d\'un autre landlord → exclu (isolation cross-user)',
      () async {
        await firestore.collection('leases').doc('l1').set({
          'landlordId': 'autre-landlord',
          'propertyId': 'p1',
          'tenantId': 't1',
          'rentAmountCents': 50000,
          'chargesAmountCents': 0,
          'startDate': Timestamp.fromDate(DateTime(2024, 1, 1)),
          'status': 'active',
          'paymentDay': 1,
          'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
          'updatedAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
          'deletedAt': null,
        });

        final leases = await repo.listActiveLeasesForProperty('p1');

        expect(leases, isEmpty);
      },
    );
  });
}
