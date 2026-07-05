/// Tests de l'enum [DocumentCategory] — fromSql, sqlValue, label, requiresLegalHold.
library;

import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DocumentCategory.fromSql', () {
    test('bail_signe', () {
      expect(
        DocumentCategory.fromSql('bail_signe'),
        DocumentCategory.bailSigne,
      );
    });

    test('etat_des_lieux', () {
      expect(
        DocumentCategory.fromSql('etat_des_lieux'),
        DocumentCategory.etatDesLieux,
      );
    });

    test('attestation_assurance', () {
      expect(
        DocumentCategory.fromSql('attestation_assurance'),
        DocumentCategory.attestationAssurance,
      );
    });

    test('quittance_scannee', () {
      expect(
        DocumentCategory.fromSql('quittance_scannee'),
        DocumentCategory.quittanceScannee,
      );
    });

    test('expense_receipt', () {
      expect(
        DocumentCategory.fromSql('expense_receipt'),
        DocumentCategory.expenseReceipt,
      );
    });

    test('autre', () {
      expect(DocumentCategory.fromSql('autre'), DocumentCategory.autre);
    });

    test('valeur inconnue lève ArgumentError', () {
      expect(() => DocumentCategory.fromSql('unknown'), throwsArgumentError);
    });
  });

  group('DocumentCategory.sqlValue', () {
    test('bailSigne → bail_signe', () {
      expect(DocumentCategory.bailSigne.sqlValue, 'bail_signe');
    });

    test('etatDesLieux → etat_des_lieux', () {
      expect(DocumentCategory.etatDesLieux.sqlValue, 'etat_des_lieux');
    });

    test('attestationAssurance → attestation_assurance', () {
      expect(
        DocumentCategory.attestationAssurance.sqlValue,
        'attestation_assurance',
      );
    });

    test('quittanceScannee → quittance_scannee', () {
      expect(DocumentCategory.quittanceScannee.sqlValue, 'quittance_scannee');
    });

    test('expenseReceipt → expense_receipt', () {
      expect(DocumentCategory.expenseReceipt.sqlValue, 'expense_receipt');
    });

    test('autre → autre', () {
      expect(DocumentCategory.autre.sqlValue, 'autre');
    });
  });

  group('DocumentCategory.label (FR)', () {
    test('bailSigne a un libellé FR non vide', () {
      expect(DocumentCategory.bailSigne.label, isNotEmpty);
    });

    test('tous les labels sont non vides', () {
      for (final cat in DocumentCategory.values) {
        expect(cat.label, isNotEmpty);
      }
    });
  });

  group('DocumentCategory.icon', () {
    test('tous les icons sont définis (non null)', () {
      for (final cat in DocumentCategory.values) {
        expect(cat.icon, isA<IconData>());
      }
    });
  });

  group('DocumentCategory.requiresLegalHold', () {
    test('bail_signe nécessite legal_hold', () {
      expect(DocumentCategory.bailSigne.requiresLegalHold, true);
    });

    test('etat_des_lieux nécessite legal_hold', () {
      expect(DocumentCategory.etatDesLieux.requiresLegalHold, true);
    });

    test('attestation_assurance ne nécessite pas legal_hold', () {
      expect(DocumentCategory.attestationAssurance.requiresLegalHold, false);
    });

    test('quittance_scannee ne nécessite pas legal_hold', () {
      expect(DocumentCategory.quittanceScannee.requiresLegalHold, false);
    });

    test('expense_receipt (FEAT-041b) nécessite legal_hold', () {
      expect(DocumentCategory.expenseReceipt.requiresLegalHold, true);
    });

    test('autre ne nécessite pas legal_hold', () {
      expect(DocumentCategory.autre.requiresLegalHold, false);
    });
  });

  group('DocumentCategory fromSql/sqlValue round-trip', () {
    test('round-trip pour toutes les valeurs', () {
      for (final cat in DocumentCategory.values) {
        final restored = DocumentCategory.fromSql(cat.sqlValue);
        expect(restored, cat);
      }
    });
  });
}
