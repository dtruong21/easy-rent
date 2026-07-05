/// Tests de [ChargeRegularizationSharePayloadBuilder] (FEAT-029 V1.2).
///
/// Miroir de `share_payload_builder_test.dart` (quittances) — vérifie sujet,
/// corps du message et nom de fichier, y compris la présence du libellé de
/// solde explicite (à réclamer / à rembourser).
library;

import 'package:easyrent/features/charge_regularization/domain/charge_regularization_balance.dart';
import 'package:easyrent/features/charge_regularization/domain/charge_regularization_share_payload_builder.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

ChargeRegularizationBalance _makeBalance({
  DateTime? periodStart,
  DateTime? periodEnd,
  int provisionsCollectedCents = 120000,
  int actualExpensesCents = 130000,
}) {
  return ChargeRegularizationBalance(
    periodStart: periodStart ?? DateTime(2025, 1, 1),
    periodEnd: periodEnd ?? DateTime(2025, 12, 31),
    provisionsCollectedCents: provisionsCollectedCents,
    actualExpensesCents: actualExpensesCents,
  );
}

ChargeRegularizationSharePayload _build({
  ChargeRegularizationBalance? balance,
  String tenantFirstName = 'Jean',
  String propertyAddress = '12 rue de la Paix, 75001 Paris',
  String landlordFullName = 'Marie Martin',
}) {
  return ChargeRegularizationSharePayloadBuilder.build(
    balance: balance ?? _makeBalance(),
    tenantFirstName: tenantFirstName,
    propertyAddress: propertyAddress,
    landlordFullName: landlordFullName,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChargeRegularizationSharePayloadBuilder.build — sujet', () {
    test('format "Régularisation des charges — <début> au <fin>"', () {
      final payload = _build();
      expect(
        payload.subject,
        'Régularisation des charges — 01/01/2025 au 31/12/2025',
      );
    });

    test('reflète une période de référence personnalisée', () {
      final payload = _build(
        balance: _makeBalance(
          periodStart: DateTime(2025, 3, 1),
          periodEnd: DateTime(2026, 2, 28),
        ),
      );
      expect(
        payload.subject,
        'Régularisation des charges — 01/03/2025 au 28/02/2026',
      );
    });
  });

  group('ChargeRegularizationSharePayloadBuilder.build — body', () {
    test('commence par "Bonjour <prénom>"', () {
      final payload = _build(tenantFirstName: 'Sophie');
      expect(payload.body, startsWith('Bonjour Sophie,'));
    });

    test('contient la date de début de période', () {
      final payload = _build(
        balance: _makeBalance(periodStart: DateTime(2025, 1, 1)),
      );
      expect(payload.body, contains('01/01/2025'));
    });

    test('contient la date de fin de période', () {
      final payload = _build(
        balance: _makeBalance(periodEnd: DateTime(2025, 12, 31)),
      );
      expect(payload.body, contains('31/12/2025'));
    });

    test('contient l\'adresse du logement', () {
      final payload = _build(
        propertyAddress: '5 avenue Victor Hugo, 69001 Lyon',
      );
      expect(payload.body, contains('5 avenue Victor Hugo, 69001 Lyon'));
    });

    test('contient le nom du bailleur en signature', () {
      final payload = _build(landlordFullName: 'Dupont François');
      expect(payload.body, contains('Dupont François'));
    });

    test('contient la signature Baillan.', () {
      final payload = _build();
      expect(payload.body, contains('Baillan.'));
    });

    test('solde positif → body contient "à réclamer au locataire"', () {
      final payload = _build(
        balance: _makeBalance(
          provisionsCollectedCents: 100000,
          actualExpensesCents: 108500,
        ),
      );
      expect(payload.body, contains('à réclamer au locataire'));
    });

    test('solde négatif → body contient "à rembourser au locataire"', () {
      final payload = _build(
        balance: _makeBalance(
          provisionsCollectedCents: 100000,
          actualExpensesCents: 91500,
        ),
      );
      expect(payload.body, contains('à rembourser au locataire'));
    });

    test('solde zéro → body contient "aucun solde"', () {
      final payload = _build(
        balance: _makeBalance(
          provisionsCollectedCents: 50000,
          actualExpensesCents: 50000,
        ),
      );
      expect(payload.body, contains('aucun solde'));
    });
  });

  group('ChargeRegularizationSharePayloadBuilder.build — filename', () {
    test('format "regularisation_charges_<année de fin>.pdf"', () {
      final payload = _build(
        balance: _makeBalance(periodEnd: DateTime(2025, 12, 31)),
      );
      expect(payload.filename, 'regularisation_charges_2025.pdf');
    });

    test('utilise l\'année de FIN de période (pas de début)', () {
      final payload = _build(
        balance: _makeBalance(
          periodStart: DateTime(2025, 7, 1),
          periodEnd: DateTime(2026, 6, 30),
        ),
      );
      expect(payload.filename, 'regularisation_charges_2026.pdf');
    });

    test('filename sans espace ni caractère spécial', () {
      final payload = _build();
      expect(payload.filename, matches(RegExp(r'^[a-z0-9_\.]+$')));
    });
  });
}
