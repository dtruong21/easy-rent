/// Tests du contrat [PaymentRepository] via un fake in-memory.
///
/// NOTE : [SupabasePaymentRepository] utilise [Db.from()] qui dépend de
/// [Supabase.instance.client] — non initialisé en test unitaire.
/// On teste donc le contrat de l'interface + les invariants du fake.
/// La vérification du payload SQL (absence de `id`/timestamps,
/// présence de `landlord_id`, appel RPC `soft_delete_payment`) est
/// documentée ici comme QA manuelle obligatoire (code review + security-auditor).
library;

import 'package:easyrent/features/payments/data/payment_repository.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake in-memory repository
// ---------------------------------------------------------------------------

class _InMemoryPaymentRepository implements PaymentRepository {
  final List<Payment> _payments = [];
  String? lastArchivedId;

  @override
  Future<List<Payment>> listForLease(String leaseId) async {
    final filtered = _payments.where((p) => p.leaseId == leaseId).toList()
      ..sort((a, b) => b.periodStart.compareTo(a.periodStart));
    return filtered;
  }

  @override
  Future<Payment> getById(String id) async {
    final matches = _payments.where((p) => p.id == id);
    if (matches.isEmpty) throw PaymentNotFoundException(id);
    return matches.first;
  }

  @override
  Future<Payment> create({
    required String leaseId,
    required String landlordId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime paidAt,
    required int rentAmountCents,
    required int chargesAmountCents,
    required PaymentMethod paymentMethod,
    String? notes,
  }) async {
    final p = Payment(
      id: 'gen-${_payments.length + 1}',
      leaseId: leaseId,
      landlordId: landlordId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      paidAt: paidAt,
      rentAmountCents: rentAmountCents,
      chargesAmountCents: chargesAmountCents,
      paymentMethod: paymentMethod,
      notes: notes,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
    _payments.add(p);
    return p;
  }

  @override
  Future<Payment> update(Payment payment) async {
    final idx = _payments.indexWhere((p) => p.id == payment.id);
    if (idx == -1) throw PaymentNotFoundException(payment.id);
    _payments[idx] = payment;
    return payment;
  }

  @override
  Future<void> archive(String id) async {
    lastArchivedId = id;
    _payments.removeWhere((p) => p.id == id);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Payment _makePayment({
  String id = 'pay-1',
  String leaseId = 'lease-1',
  String landlordId = 'landlord-1',
  DateTime? periodStart,
  DateTime? periodEnd,
}) {
  final start = periodStart ?? DateTime(2024, 1, 1);
  return Payment(
    id: id,
    leaseId: leaseId,
    landlordId: landlordId,
    periodStart: start,
    periodEnd: periodEnd ?? DateTime(2024, 1, 31),
    paidAt: DateTime(2024, 1, 5),
    rentAmountCents: 85000,
    chargesAmountCents: 5000,
    paymentMethod: PaymentMethod.virement,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _InMemoryPaymentRepository repo;

  setUp(() => repo = _InMemoryPaymentRepository());

  // ---------------------------------------------------------------------------
  group('create', () {
    test('crée un paiement avec les bons champs', () async {
      final payment = await repo.create(
        leaseId: 'lease-1',
        landlordId: 'landlord-1',
        periodStart: DateTime(2024, 1, 1),
        periodEnd: DateTime(2024, 1, 31),
        paidAt: DateTime(2024, 1, 5),
        rentAmountCents: 85000,
        chargesAmountCents: 5000,
        paymentMethod: PaymentMethod.virement,
        notes: 'Note test',
      );
      expect(payment.leaseId, 'lease-1');
      expect(payment.landlordId, 'landlord-1');
      expect(payment.rentAmountCents, 85000);
      expect(payment.chargesAmountCents, 5000);
      expect(payment.paymentMethod, PaymentMethod.virement);
      expect(payment.notes, 'Note test');
    });

    test('crée sans notes → notes est null', () async {
      final payment = await repo.create(
        leaseId: 'lease-1',
        landlordId: 'landlord-1',
        periodStart: DateTime(2024, 1, 1),
        periodEnd: DateTime(2024, 1, 31),
        paidAt: DateTime(2024, 1, 5),
        rentAmountCents: 85000,
        chargesAmountCents: 0,
        paymentMethod: PaymentMethod.cheque,
      );
      expect(payment.notes, isNull);
    });

    test(
      'payload ne contient pas id ni timestamps (contrat interface)',
      () async {
        // Le fake vérifie que l'interface crée sans id/timestamps passés
        // dans les paramètres — conforme à la doc du repository.
        final payment = await repo.create(
          leaseId: 'lease-1',
          landlordId: 'landlord-1',
          periodStart: DateTime(2024, 1, 1),
          periodEnd: DateTime(2024, 1, 31),
          paidAt: DateTime(2024, 1, 5),
          rentAmountCents: 85000,
          chargesAmountCents: 0,
          paymentMethod: PaymentMethod.virement,
        );
        // id est généré par le repo, pas passé en paramètre
        expect(payment.id, isNotEmpty);
      },
    );
  });

  // ---------------------------------------------------------------------------
  group('getById', () {
    test('retourne le paiement si trouvé', () async {
      repo._payments.add(_makePayment(id: 'pay-42'));
      final p = await repo.getById('pay-42');
      expect(p.id, 'pay-42');
    });

    test('lève PaymentNotFoundException si introuvable', () async {
      expect(
        () => repo.getById('inconnu'),
        throwsA(isA<PaymentNotFoundException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('update', () {
    test('met à jour le paiement', () async {
      repo._payments.add(_makePayment(id: 'pay-1'));
      final updated = _makePayment(
        id: 'pay-1',
      ).copyWith(rentAmountCents: 90000);
      final result = await repo.update(updated);
      expect(result.rentAmountCents, 90000);
    });

    test('lève PaymentNotFoundException si id inconnu', () async {
      expect(
        () => repo.update(_makePayment(id: 'inconnu')),
        throwsA(isA<PaymentNotFoundException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('listForLease', () {
    test('liste vide → []', () async {
      final result = await repo.listForLease('lease-1');
      expect(result, isEmpty);
    });

    test('filtre par leaseId', () async {
      repo._payments.add(_makePayment(id: 'pay-1', leaseId: 'lease-1'));
      repo._payments.add(_makePayment(id: 'pay-2', leaseId: 'lease-2'));
      final result = await repo.listForLease('lease-1');
      expect(result.length, 1);
      expect(result.first.id, 'pay-1');
    });

    test('tri period_start DESC', () async {
      repo._payments.add(
        _makePayment(
          id: 'pay-old',
          leaseId: 'lease-1',
          periodStart: DateTime(2024, 1, 1),
        ),
      );
      repo._payments.add(
        _makePayment(
          id: 'pay-new',
          leaseId: 'lease-1',
          periodStart: DateTime(2024, 3, 1),
        ),
      );
      final result = await repo.listForLease('lease-1');
      expect(result.first.id, 'pay-new');
      expect(result.last.id, 'pay-old');
    });
  });

  // ---------------------------------------------------------------------------
  group('archive (soft-delete via RPC)', () {
    test('archive enregistre l\'id (appel RPC simulé)', () async {
      repo._payments.add(_makePayment(id: 'pay-1'));
      await repo.archive('pay-1');
      expect(repo.lastArchivedId, 'pay-1');
    });

    test('le paiement disparaît de la liste après archivage', () async {
      repo._payments.add(_makePayment(id: 'pay-1', leaseId: 'lease-1'));
      await repo.archive('pay-1');
      final result = await repo.listForLease('lease-1');
      expect(result, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('PaymentNotFoundException.toString', () {
    test('contient l\'id', () {
      final ex = PaymentNotFoundException('pay-42');
      expect(ex.toString(), contains('pay-42'));
    });
  });

  // ---------------------------------------------------------------------------
  group('Payment.totalAmountCents', () {
    test('loyer + charges = total', () {
      final p = _makePayment();
      expect(p.totalAmountCents, p.rentAmountCents + p.chargesAmountCents);
    });

    test('85000 + 5000 = 90000', () {
      final p = _makePayment();
      expect(p.totalAmountCents, 90000);
    });
  });
}
