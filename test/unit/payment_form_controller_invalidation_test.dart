/// Garde-fou : encaisser ou archiver un paiement doit rafraîchir le STATUT DU
/// BAIL, pas seulement la liste des paiements et le dashboard.
///
/// Le statut « en retard » est DÉRIVÉ des paiements (`isLeaseLate()`, calculé
/// dans `lease_repository.listForDisplay()`). Sans invalidation des providers de
/// baux, un bail restait affiché « en retard » après encaissement jusqu'à un
/// rechargement complet de la page — alors que le dashboard, lui invalidé,
/// était déjà à jour. Incohérence signalée en recette le 2026-08-12.
///
/// On compte les appels à `listForDisplay()` : un appel de plus après l'action
/// = le provider a bien été reconstruit.
library;

import 'package:easyrent/features/leases/application/leases_list_provider.dart';
import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/payments/application/payment_form_controller.dart';
import 'package:easyrent/features/payments/data/payment_repository.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _leaseId = 'lease-1';

class _CountingLeaseRepo implements LeaseRepository {
  int listForDisplayCalls = 0;

  @override
  Future<List<LeaseListItem>> listForDisplay({DateTime? now}) async {
    listForDisplayCalls++;
    return const <LeaseListItem>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _payment = Payment(
  id: 'pay-1',
  leaseId: _leaseId,
  landlordId: 'uid-1',
  periodStart: DateTime.utc(2026, 8),
  periodEnd: DateTime.utc(2026, 8, 31),
  paidAt: DateTime.utc(2026, 8, 1),
  rentAmountCents: 75000,
  chargesAmountCents: 5000,
  paymentMethod: PaymentMethod.virement,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
);

class _FakePaymentRepo implements PaymentRepository {
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
    String? reference,
  }) async => _payment;

  @override
  Future<void> archive(String id) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _CountingLeaseRepo leaseRepo;
  late ProviderContainer container;

  setUp(() async {
    leaseRepo = _CountingLeaseRepo();
    container = ProviderContainer(
      overrides: [
        leaseRepositoryProvider.overrideWithValue(leaseRepo),
        paymentRepositoryProvider.overrideWithValue(_FakePaymentRepo()),
      ],
    );
    // Abonnement actif : sans écoute, un provider invalidé n'est pas reconstruit
    // et le test passerait quoi qu'il arrive.
    container.listen(leasesListProvider, (_, _) {});
    await container.read(leasesListProvider.future);
    expect(leaseRepo.listForDisplayCalls, 1);
  });

  tearDown(() => container.dispose());

  test('encaisser un paiement rafraîchit la liste des baux', () async {
    await container
        .read(paymentFormControllerProvider.notifier)
        .submit(
          leaseId: _leaseId,
          landlordId: 'uid-1',
          periodStart: DateTime.utc(2026, 8),
          periodEnd: DateTime.utc(2026, 8, 31),
          paidAt: DateTime.utc(2026, 8, 1),
          rentAmountCents: 75000,
          chargesAmountCents: 5000,
          paymentMethod: PaymentMethod.virement,
        );
    await container.read(leasesListProvider.future);

    expect(
      leaseRepo.listForDisplayCalls,
      2,
      reason:
          'leasesListProvider doit être invalidé — le statut « en retard » '
          'du bail dérive des paiements',
    );
  });

  test('archiver un paiement rafraîchit aussi la liste des baux', () async {
    // Sens inverse : retirer un paiement peut REMETTRE le bail en retard.
    await container
        .read(paymentFormControllerProvider.notifier)
        .archive(paymentId: 'pay-1', leaseId: _leaseId);
    await container.read(leasesListProvider.future);

    expect(leaseRepo.listForDisplayCalls, 2);
  });
}
