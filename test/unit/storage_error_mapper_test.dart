/// Tests du helper [mapStorageError].
library;

import 'package:easyrent/core/utils/storage_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

StorageException _makeError(String statusCode) =>
    StorageException('test error', statusCode: statusCode);

void main() {
  group('mapStorageError', () {
    test('413 → fichier trop volumineux', () {
      final msg = mapStorageError(_makeError('413'));
      expect(msg, contains('10 Mo'));
    });

    test('415 → format non supporté', () {
      final msg = mapStorageError(_makeError('415'));
      expect(msg, contains('PDF'));
    });

    test('409 → fichier déjà existant', () {
      final msg = mapStorageError(_makeError('409'));
      expect(msg, contains('existe'));
    });

    test('507 → espace insuffisant', () {
      final msg = mapStorageError(_makeError('507'));
      expect(msg, contains('stockage'));
    });

    test('code inconnu → message générique', () {
      final msg = mapStorageError(_makeError('500'));
      expect(msg, isNotEmpty);
      expect(msg, contains('Réessayez'));
    });
  });
}
