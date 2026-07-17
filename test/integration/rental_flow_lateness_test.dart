/// Test d'intégration end-to-end du flux « registre locatif » :
/// **bien → locataire → bail (contrat) → paiement**, avec vérification de
/// l'état **à jour (done)** vs **en retard (late)** via [isLeaseLate]
/// (FEAT-006 CRUD paiements + FEAT-028 détection des retards, grâce 5 j).
///
/// Les tests unitaires existants couvrent chaque brique ISOLÉMENT
/// (`lease_lateness_test.dart` : 30 cas de la fonction pure ; les domain +
/// repos de property/tenant/lease/payment). Ce test comble le trou signalé :
/// aucun test ne CHAÎNAIT les 4 entités bout-en-bout. Ici on :
///   1. construit les 4 entités avec des IDs liés (le « câblage » du registre),
///   2. round-trip la sérialisation JSON de chacune (contrat de persistance —
///      ce que les Cloud Functions écrivent puis relisent),
///   3. prouve que le MÊME bail bascule done ↔ late selon qu'un paiement
///      couvre ou non le mois dû courant.
///
/// Horloge figée : `startDate` + `now` choisis pour qu'il n'existe qu'UN SEUL
/// mois dû (février 2026), afin d'isoler le basculement done/late d'un retard
/// multi-mois (déjà couvert ailleurs).
library;

import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_lateness.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Constantes du scénario
// ---------------------------------------------------------------------------

const _landlordId = 'owner-e2e';
final _ts = DateTime.utc(2026, 1, 1);

/// Bail démarré le 01/02/2026, échéance le 1er du mois.
final _leaseStart = DateTime(2026, 2, 1);

/// « Maintenant » = 10/02/2026 : l'échéance de février (01/02) + 5 j de grâce
/// (06/02) est dépassée, mais celle de mars (01/03 + grâce) ne l'est pas.
/// → EXACTEMENT un mois dû : février 2026.
final _now = DateTime(2026, 2, 10);

// ---------------------------------------------------------------------------
// Builders — round-trip JSON pour exercer le contrat de sérialisation
// (fromJson(toJson()) = ce que les CF écrivent puis ce que le client relit).
// ---------------------------------------------------------------------------

Property _property() => Property.fromJson(
  Property(
    id: 'prop-1',
    landlordId: _landlordId,
    name: 'Studio Bastille',
    address: '12 rue de la Roquette, 75011 Paris',
    type: PropertyType.studio,
    createdAt: _ts,
    updatedAt: _ts,
  ).toJson(),
);

Tenant _tenant() => Tenant.fromJson(
  Tenant(
    id: 'ten-1',
    landlordId: _landlordId,
    firstName: 'Jean',
    lastName: 'Dupont',
    email: 'jean.dupont@example.test',
    createdAt: _ts,
    updatedAt: _ts,
  ).toJson(),
);

Lease _lease({required String propertyId, required String tenantId}) =>
    Lease.fromJson(
      Lease(
        id: 'lease-1',
        landlordId: _landlordId,
        propertyId: propertyId,
        tenantId: tenantId,
        rentAmountCents: 80000,
        chargesAmountCents: 5000,
        startDate: _leaseStart,
        status: LeaseStatus.active,
        leaseType: LeaseType.unfurnished,
        paymentDay: 1,
        createdAt: _ts,
        updatedAt: _ts,
      ).toJson(),
    );

/// Paiement couvrant [periodStart]..[periodEnd] pour [leaseId].
Payment _payment({
  required String leaseId,
  required DateTime periodStart,
  required DateTime periodEnd,
  DateTime? paidAt,
}) => Payment.fromJson(
  Payment(
    id: 'pay-1',
    leaseId: leaseId,
    landlordId: _landlordId,
    periodStart: periodStart,
    periodEnd: periodEnd,
    paidAt: paidAt ?? periodStart,
    rentAmountCents: 80000,
    chargesAmountCents: 5000,
    paymentMethod: PaymentMethod.virement,
    createdAt: _ts,
    updatedAt: _ts,
  ).toJson(),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Registre locatif e2e — bien → locataire → bail → paiement', () {
    test(
      'câblage cross-entité cohérent (paiement → bail → bien/locataire)',
      () {
        final property = _property();
        final tenant = _tenant();
        final lease = _lease(propertyId: property.id, tenantId: tenant.id);
        final payment = _payment(
          leaseId: lease.id,
          periodStart: DateTime(2026, 2, 1),
          periodEnd: DateTime(2026, 2, 28),
        );

        // La chaîne référentielle du registre, telle que les CF la persistent.
        expect(lease.propertyId, property.id, reason: 'bail → bien');
        expect(lease.tenantId, tenant.id, reason: 'bail → locataire');
        expect(payment.leaseId, lease.id, reason: 'paiement → bail');
        // Même propriétaire de bout en bout (isolation cross-user).
        expect(
          {
            property.landlordId,
            tenant.landlordId,
            lease.landlordId,
            payment.landlordId,
          },
          {_landlordId},
          reason: 'les 4 entités appartiennent au même landlord',
        );
      },
    );

    test('PAIEMENT enregistré couvrant le mois dû → bail À JOUR (done)', () {
      final property = _property();
      final tenant = _tenant();
      final lease = _lease(propertyId: property.id, tenantId: tenant.id);
      final payment = _payment(
        leaseId: lease.id,
        periodStart: DateTime(2026, 2, 1),
        periodEnd: DateTime(2026, 2, 28),
        paidAt: DateTime(2026, 2, 3),
      );

      expect(
        isLeaseLate(lease: lease, payments: [payment], now: _now),
        isFalse,
        reason: 'un paiement couvre février 2026 → pas de retard',
      );
    });

    test('AUCUN paiement pour le mois dû (échéance + grâce dépassées) → EN '
        'RETARD (late)', () {
      final property = _property();
      final tenant = _tenant();
      final lease = _lease(propertyId: property.id, tenantId: tenant.id);

      expect(
        isLeaseLate(lease: lease, payments: const [], now: _now),
        isTrue,
        reason:
            'février dû, échéance 01/02 + 5 j de grâce < 10/02, aucun '
            'paiement enregistré',
      );
    });

    test('paiement d\'un AUTRE mois (janvier) ne couvre pas février → EN '
        'RETARD', () {
      final property = _property();
      final tenant = _tenant();
      final lease = _lease(propertyId: property.id, tenantId: tenant.id);
      final janPayment = _payment(
        leaseId: lease.id,
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 31),
      );

      expect(
        isLeaseLate(lease: lease, payments: [janPayment], now: _now),
        isTrue,
        reason: 'le paiement de janvier ne recouvre pas le mois dû (février)',
      );
    });

    test('bail résilié → jamais en retard, même sans paiement', () {
      final property = _property();
      final tenant = _tenant();
      // Bail terminé : la détection de retard ne s'applique pas (règle FEAT-028).
      final terminated = _lease(
        propertyId: property.id,
        tenantId: tenant.id,
      ).copyWith(status: LeaseStatus.terminated);

      expect(
        isLeaseLate(lease: terminated, payments: const [], now: _now),
        isFalse,
        reason: 'un bail non actif n\'est jamais signalé en retard',
      );
    });
  });
}
