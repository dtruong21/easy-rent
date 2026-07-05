/// Tests de l'agrégation des notes de paiement dans le PDF de quittance
/// (FEAT-029 V1.1 — `FirestoreReceiptsRepository.renderPdfBytes`).
///
/// Le doc Firestore `receipts/{id}` (posé par la CF `generateReceipt`, hors
/// scope de cette story) ne dénormalise PAS `payment.notes` — ce test
/// vérifie que `renderPdfBytes` relit bien le(s) paiement(s) source
/// (`receipt.paymentIds`) et agrège leurs notes non vides, sans lever
/// d'exception ni bloquer le rendu quand un paiement source est absent ou
/// sans note.
///
/// Réutilise le pattern `property_repository_firestore_test.dart` : VRAIE
/// implémentation contre `fake_cloud_firestore`, pas un fake d'interface —
/// nécessaire ici car la logique testée (lecture croisée `payments/{id}`)
/// vit dans le corps privé de la classe concrète, pas dans le contrat
/// abstrait `ReceiptsRepository`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

/// [FirebaseFunctions] jamais appelé par `renderPdfBytes` — toute
/// utilisation lève via noSuchMethod.
class _UnusedFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _uid = 'lld-test-1';

Map<String, dynamic> _receiptDoc({required List<String> paymentIds}) => {
  'landlordId': _uid,
  'leaseId': 'lease-1',
  'paymentIds': paymentIds,
  'periodStart': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
  'periodEnd': Timestamp.fromDate(DateTime.utc(2026, 3, 31)),
  'totalCents': 90000,
  'rentCents': 85000,
  'chargesCents': 5000,
  'documentType': 'quittance',
  'isVoided': false,
  'isStale': false,
  'generatedAt': Timestamp.fromDate(DateTime.utc(2026, 4, 1)),
  'landlordFullName': 'Marie Martin',
  'landlordAddress': '1 rue de Paris, 75001 Paris',
  'tenantFullName': 'Jean Dupont',
  'propertyAddress': '2 rue de Lyon, 69001 Lyon',
  'lastPaidAt': Timestamp.fromDate(DateTime.utc(2026, 3, 5)),
};

Map<String, dynamic> _paymentDoc({String? notes}) => {
  'landlordId': _uid,
  'leaseId': 'lease-1',
  'periodStart': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
  'periodEnd': Timestamp.fromDate(DateTime.utc(2026, 3, 31)),
  'paidAt': Timestamp.fromDate(DateTime.utc(2026, 3, 5)),
  'rentAmountCents': 85000,
  'chargesAmountCents': 5000,
  'paymentMethod': 'virement',
  if (notes != null && notes.isNotEmpty) 'notes': notes,
};

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreReceiptsRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _uid, isAnonymous: false, isEmailVerified: true),
    );
    repo = FirestoreReceiptsRepository(firestore, auth, _UnusedFunctions());
  });

  group('renderPdfBytes — agrégation des notes du paiement source', () {
    test('paiement source avec une note → PDF généré sans exception', () async {
      await firestore
          .collection('payments')
          .doc('pay-1')
          .set(_paymentDoc(notes: 'Régularisation ascenseur T2 2026'));
      await firestore
          .collection('receipts')
          .doc('r-1')
          .set(_receiptDoc(paymentIds: ['pay-1']));

      final bytes = await repo.renderPdfBytes('r-1');
      expect(bytes, isNotEmpty);
    });

    test(
      'paiement source SANS note → PDF généré sans exception (motif absent)',
      () async {
        await firestore.collection('payments').doc('pay-1').set(_paymentDoc());
        await firestore
            .collection('receipts')
            .doc('r-1')
            .set(_receiptDoc(paymentIds: ['pay-1']));

        final bytes = await repo.renderPdfBytes('r-1');
        expect(bytes, isNotEmpty);
      },
    );

    test('paiement source introuvable (supprimé entre-temps) → ne bloque pas '
        'le rendu du PDF', () async {
      // Aucun doc payments/pay-1 créé — simule une suppression concurrente.
      await firestore
          .collection('receipts')
          .doc('r-1')
          .set(_receiptDoc(paymentIds: ['pay-1']));

      final bytes = await repo.renderPdfBytes('r-1');
      expect(bytes, isNotEmpty);
    });

    test('plusieurs paiements source, une seule note non vide → PDF généré '
        'sans exception', () async {
      await firestore
          .collection('payments')
          .doc('pay-1')
          .set(_paymentDoc(notes: 'Charge exceptionnelle'));
      await firestore.collection('payments').doc('pay-2').set(_paymentDoc());
      await firestore
          .collection('receipts')
          .doc('r-1')
          .set(_receiptDoc(paymentIds: ['pay-1', 'pay-2']));

      final bytes = await repo.renderPdfBytes('r-1');
      expect(bytes, isNotEmpty);
    });

    test(
      'quittance sans paymentIds (liste vide) → PDF généré sans exception',
      () async {
        await firestore
            .collection('receipts')
            .doc('r-1')
            .set(_receiptDoc(paymentIds: const []));

        final bytes = await repo.renderPdfBytes('r-1');
        expect(bytes, isNotEmpty);
      },
    );

    test('note composée uniquement d\'espaces → traitée comme absente (motif '
        'non affiché, pas d\'exception)', () async {
      await firestore
          .collection('payments')
          .doc('pay-1')
          .set(_paymentDoc(notes: '   '));
      await firestore
          .collection('receipts')
          .doc('r-1')
          .set(_receiptDoc(paymentIds: ['pay-1']));

      final bytes = await repo.renderPdfBytes('r-1');
      expect(bytes, isNotEmpty);
    });
  });
}
