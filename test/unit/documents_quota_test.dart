/// Tests du modèle [DocumentsQuota].
library;

import 'package:easyrent/features/documents/domain/documents_quota.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DocumentsQuota.isOverSoftLimit', () {
    test('faux si totalBytes = 0', () {
      const q = DocumentsQuota(totalBytes: 0);
      expect(q.isOverSoftLimit, false);
    });

    test('faux si totalBytes < 100 Mo', () {
      const q = DocumentsQuota(totalBytes: 50 * 1024 * 1024); // 50 Mo
      expect(q.isOverSoftLimit, false);
    });

    test('vrai si totalBytes == 100 Mo (seuil exact)', () {
      const q = DocumentsQuota(totalBytes: 104857600); // 100 Mo exact
      expect(q.isOverSoftLimit, true);
    });

    test('vrai si totalBytes > 100 Mo', () {
      const q = DocumentsQuota(totalBytes: 110 * 1024 * 1024); // 110 Mo
      expect(q.isOverSoftLimit, true);
    });

    test('softLimitBytes par défaut est 100 Mo', () {
      const q = DocumentsQuota(totalBytes: 0);
      expect(q.softLimitBytes, 104857600);
    });

    test('softLimitBytes personnalisable', () {
      const q = DocumentsQuota(totalBytes: 60, softLimitBytes: 50);
      expect(q.isOverSoftLimit, true);
    });
  });

  group('DocumentsQuota.copyWith', () {
    test('copyWith modifie totalBytes', () {
      const q = DocumentsQuota(totalBytes: 0);
      final updated = q.copyWith(totalBytes: 200);
      expect(updated.totalBytes, 200);
      expect(updated.softLimitBytes, q.softLimitBytes);
    });
  });
}
