/// Garde-fou source contre le piège `isEqualTo: null` de cloud_firestore.
///
/// `Query.where(field, isEqualTo: null)` ne crée AUCUN filtre : le paramètre
/// nommé passé à `null` est indistinguable d'un paramètre omis
/// (cloud_firestore, query.dart : `if (isEqualTo != null) addCondition(…)`).
/// La syntaxe correcte pour filtrer sur null est `isNull: true`.
///
/// Le piège est indétectable par les tests classiques : fake_cloud_firestore
/// convertit, lui, `isEqualTo: null` en vrai filtre null (mock_query.dart) —
/// les tests passent, la prod casse (missing composite index + réapparition
/// des docs soft-deleted). Régression découverte en E2E le 2026-07-02
/// (page « Mes biens » morte sur failed-precondition). Ce scan de source est
/// donc le seul verrou fiable.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'lib/ ne contient aucun `isEqualTo: null` (filtre no-op silencieux)',
    () {
      final offenders = <String>[];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('isEqualTo: null')) {
            offenders.add('${file.path}:${i + 1}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            '`isEqualTo: null` est un no-op (aucun filtre envoyé à Firestore). '
            'Utiliser `isNull: true` pour filtrer sur null. Occurrences : '
            '$offenders',
      );
    },
  );
}
