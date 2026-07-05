/// Tests "golden-free" de [renderChargeRegularizationPdf] (FEAT-029 V1.2).
///
/// Le package `pdf` (writer) ne fournit aucune API d'extraction de texte —
/// impossible de faire une assertion type "le PDF contient la chaîne X" sans
/// dépendance supplémentaire (hors scope : `pubspec.yaml` ne doit pas
/// changer pour cette story). Ce fichier applique donc la même limite déjà
/// acceptée implicitement par `receipt_pdf_renderer.dart` (aucun test dédié
/// dans ce repo à ce jour) — en allant plus loin qu'un simple "ne crashe
/// pas" : on exerce le renderer avec des données limites (solde positif /
/// négatif / zéro, montants à zéro, montants élevés) pour garantir qu'aucune
/// combinaison de [ChargeRegularizationBalance] ne fait planter la
/// génération, et on vérifie une propriété observable indirecte (taille du
/// document croissante avec le contenu textuel).
library;

import 'package:easyrent/features/charge_regularization/domain/charge_regularization_balance.dart';
import 'package:easyrent/features/charge_regularization/domain/charge_regularization_pdf_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

ChargeRegularizationPdfData _makeData({
  ChargeRegularizationBalance? balance,
  String landlordFullName = 'Marie Martin',
  String landlordAddress = '1 rue de Paris, 75001 Paris',
  String tenantFullName = 'Jean Dupont',
  String propertyAddress = '2 rue de Lyon, 69001 Lyon',
}) {
  return ChargeRegularizationPdfData(
    landlordFullName: landlordFullName,
    landlordAddress: landlordAddress,
    tenantFullName: tenantFullName,
    propertyAddress: propertyAddress,
    balance:
        balance ??
        ChargeRegularizationBalance(
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 12, 31),
          provisionsCollectedCents: 120000,
          actualExpensesCents: 130000,
        ),
    generatedAt: DateTime(2026, 1, 15),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('renderChargeRegularizationPdf — génère un document valide', () {
    test('retourne des bytes non vides (cas nominal, solde positif)', () async {
      final bytes = await renderChargeRegularizationPdf(_makeData());
      expect(bytes, isNotEmpty);
    });

    test('en-tête PDF standard (%PDF-) présent au début du document', () async {
      final bytes = await renderChargeRegularizationPdf(_makeData());
      // Un fichier PDF valide commence toujours par la signature "%PDF-".
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, '%PDF-');
    });
  });

  group('renderChargeRegularizationPdf — robustesse sur les 3 sens de '
      'solde', () {
    test('solde positif (à réclamer) ne lève pas d\'exception', () async {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 100000,
        actualExpensesCents: 108500,
      );
      expect(
        balance.direction,
        ChargeRegularizationBalanceDirection.dueByTenant,
      );
      final bytes = await renderChargeRegularizationPdf(
        _makeData(balance: balance),
      );
      expect(bytes, isNotEmpty);
    });

    test('solde négatif (à rembourser) ne lève pas d\'exception', () async {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 100000,
        actualExpensesCents: 91500,
      );
      expect(
        balance.direction,
        ChargeRegularizationBalanceDirection.dueToTenant,
      );
      final bytes = await renderChargeRegularizationPdf(
        _makeData(balance: balance),
      );
      expect(bytes, isNotEmpty);
    });

    test('solde zéro (équilibré) ne lève pas d\'exception', () async {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 50000,
        actualExpensesCents: 50000,
      );
      expect(balance.direction, ChargeRegularizationBalanceDirection.balanced);
      final bytes = await renderChargeRegularizationPdf(
        _makeData(balance: balance),
      );
      expect(bytes, isNotEmpty);
    });
  });

  group('renderChargeRegularizationPdf — cas limites de montants', () {
    test('provisions et dépenses à zéro ne lève pas d\'exception', () async {
      final balance = ChargeRegularizationBalance(
        periodStart: DateTime(2025, 1, 1),
        periodEnd: DateTime(2025, 12, 31),
        provisionsCollectedCents: 0,
        actualExpensesCents: 0,
      );
      final bytes = await renderChargeRegularizationPdf(
        _makeData(balance: balance),
      );
      expect(bytes, isNotEmpty);
    });

    test(
      'montants élevés (six chiffres en euros) ne lève pas d\'exception',
      () async {
        final balance = ChargeRegularizationBalance(
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 12, 31),
          provisionsCollectedCents: 99999900,
          actualExpensesCents: 100000000,
        );
        final bytes = await renderChargeRegularizationPdf(
          _makeData(balance: balance),
        );
        expect(bytes, isNotEmpty);
      },
    );
  });

  group('renderChargeRegularizationPdf — identité et adresses', () {
    test('noms et adresses avec accents et caractères spéciaux ne lève pas '
        'd\'exception', () async {
      final data = _makeData(
        landlordFullName: 'Éric François-Xavier de Léon',
        landlordAddress: "12 rue de l'Église, 75001 Paris",
        tenantFullName: 'Amélie Nguyễn',
        propertyAddress: '3 allée des Chênes, 33000 Bordeaux',
      );
      final bytes = await renderChargeRegularizationPdf(data);
      expect(bytes, isNotEmpty);
    });

    test('deux jeux de données distincts produisent des documents de taille '
        'différente (contenu textuel réellement injecté, pas un template '
        'figé)', () async {
      final shortData = _makeData(
        landlordFullName: 'A',
        tenantFullName: 'B',
        propertyAddress: 'C',
        landlordAddress: 'D',
      );
      final longData = _makeData(
        landlordFullName: 'Jean-Baptiste Alexandre de la Tour du Pin Montauban',
        tenantFullName: 'Marie-Charlotte Isabelle Rodriguez y Fernandez',
        propertyAddress:
            '128 boulevard du Maréchal de Lattre de Tassigny, '
            '75016 Paris',
        landlordAddress:
            '45 avenue du Général Leclerc, 92100 Boulogne-Billancourt',
      );

      final shortBytes = await renderChargeRegularizationPdf(shortData);
      final longBytes = await renderChargeRegularizationPdf(longData);

      // Preuve indirecte que le contenu (noms/adresses) est bien injecté
      // dans le PDF plutôt qu'un gabarit statique : plus de texte → document
      // plus volumineux (le contenu textuel est compressé par la
      // bibliothèque, mais la relation reste monotone sur des écarts de
      // cette ampleur).
      expect(longBytes.length, greaterThan(shortBytes.length));
    });
  });
}
