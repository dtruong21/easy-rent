/// Verrou de conformité : `firestore.rules` ↔ chemins d'écriture des dépôts.
///
/// ## La régression que ce fichier attrape
///
/// Quand une collection bascule en écriture serveur-only (`allow create: if
/// false`, la création devant passer par une Cloud Function) mais que le dépôt
/// client continue d'écrire en direct via `docRef.set(...)`, l'app casse en
/// `permission-denied` en production — et AUCUN test ne devient rouge :
///
/// - les tests de contrôleurs/widgets passent par l'interface abstraite
///   (`InvestmentScenarioRepository`) avec des faux in-memory ;
/// - les tests de dépôt concret utilisent `fake_cloud_firestore`, qui
///   **n'évalue pas** `firestore.rules` — une écriture interdite y réussit ;
/// - les tests de règles (`functions/rules-tests/`) valident les règles seules,
///   sans jamais regarder ce que le client fait réellement.
///
/// Les deux moitiés du contrat sont testées séparément, donc leur **désaccord**
/// n'est testé nulle part. Ce fichier teste le joint.
///
/// ## Comment le maintenir
///
/// [_clientDirectWrites] déclare, par collection, les opérations que le client
/// exécute en écriture directe (tout le reste passe par une callable). Le test
/// `matrice à jour` re-dérive cette matrice depuis les sources : si tu changes
/// le transport d'une opération, il devient rouge et te dit quoi corriger.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Opérations exécutées par le client en **écriture directe Firestore**.
/// Toute opération absente d'ici doit passer par une Cloud Function callable.
///
/// Dérivé de `lib/features/*/data/*_repository.dart` — cf. test « matrice à
/// jour » qui vérifie que cette déclaration ne dérive pas des sources.
const _clientDirectWrites = <String, Set<String>>{
  'properties': {'update'},
  'tenants': {'update'},
  'investment_scenarios': {'create', 'update'},
  'leases': <String>{},
  'payments': <String>{},
  'receipts': <String>{},
  'documents': <String>{},
  'expenses': <String>{},
};

/// Fichier dépôt portant les écritures de chaque collection.
const _repositoryOf = <String, String>{
  'properties': 'lib/features/properties/data/property_repository.dart',
  'tenants': 'lib/features/tenants/data/tenant_repository.dart',
  'investment_scenarios':
      'lib/features/simulator/data/investment_scenario_repository.dart',
  'leases': 'lib/features/leases/data/lease_repository.dart',
  'payments': 'lib/features/payments/data/payment_repository.dart',
  'receipts': 'lib/features/receipts/data/receipts_repository.dart',
  'documents': 'lib/features/documents/data/documents_repository.dart',
  'expenses': 'lib/features/expenses/data/expenses_repository.dart',
};

/// Extrait le corps du bloc `match /<collection>/{...} { ... }`.
String _matchBlock(String rules, String collection) {
  final header = RegExp('match\\s+/$collection/\\{[^}]*\\}\\s*\\{');
  final start = header.firstMatch(rules);
  expect(
    start,
    isNotNull,
    reason: 'Bloc `match /$collection/{id}` introuvable dans firestore.rules',
  );

  var depth = 1;
  var i = start!.end;
  while (i < rules.length && depth > 0) {
    if (rules[i] == '{') depth++;
    if (rules[i] == '}') depth--;
    i++;
  }
  return rules.substring(start.end, i - 1);
}

/// Condition associée à une opération dans un bloc de règles.
///
/// Gère les déclarations groupées (`allow create, update, delete: if false;`)
/// et les conditions multi-lignes (terminées par `;`).
String? _conditionFor(String block, String operation) {
  final statements = RegExp(
    r'allow\s+([a-z,\s]+?)\s*:\s*if\s+([\s\S]*?);',
  ).allMatches(block);

  for (final s in statements) {
    final ops = s
        .group(1)!
        .split(',')
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .toSet();
    if (ops.contains(operation)) {
      return s.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }
  return null;
}

/// Une opération est refusée si sa condition est absente (deny-by-default)
/// ou littéralement `false`.
bool _isDenied(String block, String operation) {
  final condition = _conditionFor(block, operation);
  return condition == null || condition == 'false';
}

/// Ops d'écriture directe réellement présentes dans le source d'un dépôt.
///
/// Cherche les appels `.set(` / `.update(` / `.delete(` sur une référence
/// Firestore (`docRef`, `ref`, `_col.doc(...)`), en excluant les appels
/// Storage (`_storage.ref(...)`) et les callables.
Set<String> _directWritesInSource(String source) {
  final found = <String>{};
  final call = RegExp(
    r'(?:docRef|ref|_col\.doc\([^)]*\)|\.doc\([^)]*\))\s*\.\s*(set|update|delete)\s*\(',
  );

  for (final line in source.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
    // Firebase Storage, pas Firestore.
    if (trimmed.contains('_storage')) {
      continue;
    }
    for (final m in call.allMatches(line)) {
      final op = m.group(1)!;
      found.add(op == 'set' ? 'create' : op);
    }
  }
  return found;
}

void main() {
  late String rules;

  setUpAll(() {
    final file = File('firestore.rules');
    expect(file.existsSync(), isTrue, reason: 'firestore.rules introuvable');
    rules = file.readAsStringSync();
  });

  group('firestore.rules ↔ écritures directes du client', () {
    test('toute écriture directe du client est autorisée par les règles', () {
      final violations = <String>[];

      _clientDirectWrites.forEach((collection, ops) {
        final block = _matchBlock(rules, collection);
        for (final op in ops) {
          if (_isDenied(block, op)) {
            violations.add(
              '$collection.$op : le client écrit en direct '
              '(${_repositoryOf[collection]}) mais firestore.rules refuse '
              'cette opération → permission-denied en production',
            );
          }
        }
      });

      expect(
        violations,
        isEmpty,
        reason:
            'Dérive règles ↔ dépôt détectée.\n\n'
            '${violations.join('\n')}\n\n'
            'Corrige DANS LE MÊME CHANGEMENT : soit la règle réautorise '
            'l\'opération, soit le dépôt passe par une Cloud Function '
            'callable (et la matrice _clientDirectWrites est mise à jour).',
      );
    });

    test(
      'toute opération refusée par les règles passe bien par une callable',
      () {
        final unjustified = <String>[];

        _clientDirectWrites.forEach((collection, declaredDirect) {
          final block = _matchBlock(rules, collection);
          final source = File(_repositoryOf[collection]!).readAsStringSync();
          final actualDirect = _directWritesInSource(source);

          for (final op in actualDirect) {
            if (declaredDirect.contains(op)) continue;
            if (_isDenied(block, op)) {
              unjustified.add(
                '$collection.$op : écriture directe détectée dans '
                '${_repositoryOf[collection]} alors que la règle la refuse',
              );
            }
          }
        });

        expect(unjustified, isEmpty, reason: unjustified.join('\n'));
      },
    );
  });

  group('garde-fous de la matrice', () {
    test('la matrice reflète les sources (anti-dérive silencieuse)', () {
      final drift = <String>[];

      _clientDirectWrites.forEach((collection, declared) {
        final source = File(_repositoryOf[collection]!).readAsStringSync();
        final actual = _directWritesInSource(source);

        final missing = actual.difference(declared);
        final stale = declared.difference(actual);

        if (missing.isNotEmpty) {
          drift.add(
            '$collection : écritures directes non déclarées $missing '
            '(${_repositoryOf[collection]})',
          );
        }
        if (stale.isNotEmpty) {
          drift.add(
            '$collection : déclarées comme directes mais absentes du source '
            '$stale — le dépôt est probablement passé aux callables, retire-les '
            'de _clientDirectWrites',
          );
        }
      });

      expect(
        drift,
        isEmpty,
        reason:
            'La matrice _clientDirectWrites ne reflète plus les sources :\n'
            '${drift.join('\n')}',
      );
    });

    test('chaque collection déclarée a un bloc de règles et un dépôt', () {
      for (final collection in _clientDirectWrites.keys) {
        expect(
          _repositoryOf,
          contains(collection),
          reason: 'Dépôt non déclaré pour $collection',
        );
        expect(
          File(_repositoryOf[collection]!).existsSync(),
          isTrue,
          reason: 'Fichier dépôt introuvable pour $collection',
        );
        expect(
          () => _matchBlock(rules, collection),
          returnsNormally,
          reason: 'Règles introuvables pour $collection',
        );
      }
    });
  });
}
