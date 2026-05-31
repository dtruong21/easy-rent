/// Tests du [DocumentType] — fromSql / sqlValue / label.
library;

import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DocumentType.sqlValue', () {
    test('quittance → "quittance"', () {
      expect(DocumentType.quittance.sqlValue, 'quittance');
    });

    test('recu → "recu"', () {
      expect(DocumentType.recu.sqlValue, 'recu');
    });
  });

  group('DocumentType.label', () {
    test('quittance → "Quittance"', () {
      expect(DocumentType.quittance.label, 'Quittance');
    });

    test('recu → "Reçu"', () {
      expect(DocumentType.recu.label, 'Reçu');
    });
  });

  group('DocumentType.fromSql', () {
    test('fromSql("quittance") → quittance', () {
      expect(DocumentType.fromSql('quittance'), DocumentType.quittance);
    });

    test('fromSql("recu") → recu', () {
      expect(DocumentType.fromSql('recu'), DocumentType.recu);
    });

    test('fromSql("inconnu") → quittance (fallback défensif)', () {
      expect(DocumentType.fromSql('inconnu'), DocumentType.quittance);
    });

    test('round-trip sqlValue → fromSql', () {
      for (final dt in DocumentType.values) {
        expect(DocumentType.fromSql(dt.sqlValue), dt);
      }
    });
  });
}
