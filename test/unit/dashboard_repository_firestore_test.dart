/// Tests de [FirestoreDashboardRepository.fetchRetards] via
/// fake_cloud_firestore — FEAT-028.
///
/// Couvre spécifiquement la régression corrigée par cette feature :
/// l'ancienne règle (`startDate <= now - 35 jours`) ignorait les baux
/// récents dont la 1ʳᵉ échéance était déjà dépassée. La logique de calcul
/// pure (`isLeaseLate`) est testée exhaustivement dans
/// `lease_lateness_test.dart` — ce fichier vérifie seulement le branchement
/// Firestore (requête + chunking + agrégation du compte).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easyrent/features/dashboard/data/dashboard_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uid = 'landlord-1';

  late FakeFirebaseFirestore firestore;
  late FirestoreDashboardRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));
    repo = FirestoreDashboardRepository(firestore, auth);
  });

  Future<void> seedLease({
    required String id,
    String status = 'active',
    required DateTime startDate,
    DateTime? endDate,
    int paymentDay = 1,
  }) async {
    await firestore.collection('leases').doc(id).set({
      'landlordId': uid,
      'propertyId': 'p1',
      'tenantId': 't1',
      'rentAmountCents': 80000,
      'chargesAmountCents': 5000,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate == null ? null : Timestamp.fromDate(endDate),
      'status': status,
      'paymentDay': paymentDay,
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

  group('FirestoreDashboardRepository.fetchRetards — FEAT-028', () {
    test('aucun bail actif → count=0', () async {
      final kpi = await repo.fetchRetards();
      expect(kpi.count, 0);
    });

    test(
      'RÉGRESSION corrigée : bail démarré il y a 6 jours, 1ʳᵉ échéance déjà '
      'dépassée + grâce écoulée, aucun paiement → compté (l\'ancien filtre '
      '`startDate <= now-35j` l\'aurait exclu à tort — 6 jours << 35 jours)',
      () async {
        final now = DateTime.now();
        // startDate.day == paymentDay → l'échéance du mois de démarrage est
        // exactement le jour de démarrage (règle ">= inclusif", pas de saut
        // au mois suivant). deadline = startDate + 5j = now - 1j <= now →
        // dépassé le délai de grâce, peu importe le jour d'exécution du test.
        final startDate = now.subtract(const Duration(days: 6));
        await seedLease(
          id: 'l1',
          startDate: startDate,
          paymentDay: startDate.day,
        );

        final kpi = await repo.fetchRetards();

        expect(kpi.count, 1);
      },
    );

    test('bail actif payé pour le mois en cours → non compté', () async {
      // Le « mois dû courant » (avec délai de grâce de 5 jours, cf.
      // lease_lateness.dart) n'est PAS toujours le mois calendaire de
      // `now` : les 5 premiers jours d'un mois, le mois dû courant est
      // encore le mois PRÉCÉDENT (grâce de juillet pas expirée avant le 6
      // juillet). Un test qui ne paie QUE `now.month` est donc fragile —
      // il échoue déterministement les 5 premiers jours de chaque mois
      // (régression découverte le 2026-07-04, exécution un 4 juillet).
      // On paie ici les DEUX mois candidats (précédent + courant) pour
      // rester robuste quel que soit le jour d'exécution du test, sans
      // dupliquer la logique de grâce dans le test lui-même.
      await seedLease(id: 'l1', startDate: DateTime(2020, 1, 1));
      final now = DateTime.now();
      final previousMonthStart = DateTime(now.year, now.month - 1, 1);
      final currentMonthEnd = DateTime(now.year, now.month + 1, 0);
      await seedPayment(
        id: 'pay1',
        leaseId: 'l1',
        periodStart: previousMonthStart,
        periodEnd: currentMonthEnd,
      );

      final kpi = await repo.fetchRetards();

      expect(kpi.count, 0);
    });

    test('bail terminated sans aucun paiement récent → jamais compté (statut '
        'non-actif ignoré par la requête `where status == active`)', () async {
      await seedLease(
        id: 'l1',
        status: 'terminated',
        startDate: DateTime(2020, 1, 1),
      );

      final kpi = await repo.fetchRetards();

      expect(kpi.count, 0);
    });

    test(
      'mix : 1 bail en retard + 1 bail payé + 1 bail terminé → count=1',
      () async {
        await seedLease(id: 'l-late', startDate: DateTime(2020, 1, 1));

        await seedLease(id: 'l-paid', startDate: DateTime(2020, 1, 1));
        final now = DateTime.now();
        // Paie précédent + courant : robuste quel que soit le jour
        // d'exécution du test (cf. commentaire détaillé sur le test
        // « bail actif payé pour le mois en cours » ci-dessus).
        await seedPayment(
          id: 'pay1',
          leaseId: 'l-paid',
          periodStart: DateTime(now.year, now.month - 1, 1),
          periodEnd: DateTime(now.year, now.month + 1, 0),
        );

        await seedLease(
          id: 'l-terminated',
          status: 'terminated',
          startDate: DateTime(2020, 1, 1),
        );

        final kpi = await repo.fetchRetards();

        expect(kpi.count, 1);
      },
    );
  });
}
