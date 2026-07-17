/// FEAT-051 — Feature Readiness Score.
///
/// Couvre la logique pure du script `tool/feature_ready.dart` : parsing de
/// l'ID, pondération du score (dont la redistribution des catégories non
/// évaluées) et déterminisme du rendu.
///
/// Les checks eux-mêmes (`buildCategories`) lisent l'arbre de fichiers réel :
/// les tester ici couplerait la suite au contenu du dépôt, qui bouge à chaque
/// feature. On teste donc le moteur, pas l'état du dépôt à un instant t.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/feature_ready.dart';

Category _category(
  String name, {
  required int weight,
  required int passed,
  required int total,
  bool skipped = false,
}) {
  return Category(
    name,
    weight: weight,
    skipped: skipped,
    skipReason: skipped ? 'non évalué' : null,
    checks: [
      for (var i = 0; i < total; i++)
        Check('check $i', passed: i < passed, detail: 'détail $i'),
    ],
  );
}

void main() {
  group('parseFeatureId', () {
    test('normalise les formes courtes et longues vers FEAT-0XX', () {
      for (final raw in ['51', '051', 'FEAT-051', 'feat-051', '  051  ']) {
        final parsed = parseFeatureId(raw);
        expect(parsed, isNotNull, reason: 'échec sur "$raw"');
        expect(parsed!.featId, 'FEAT-051', reason: 'échec sur "$raw"');
        expect(parsed.idNum, '051', reason: 'échec sur "$raw"');
      }
    });

    test('rejette ce qui n\'est pas un identifiant de feature', () {
      for (final raw in ['', 'abc', 'FEAT-', '0051', 'FEAT-51x', '--strict']) {
        expect(parseFeatureId(raw), isNull, reason: 'accepté à tort : "$raw"');
      }
    });
  });

  group('Category.score', () {
    test('vaut le ratio de checks passés, arrondi', () {
      expect(_category('c', weight: 10, passed: 1, total: 3).score, 33);
      expect(_category('c', weight: 10, passed: 2, total: 2).score, 100);
      expect(_category('c', weight: 10, passed: 0, total: 2).score, 0);
    });

    test('expose le bon symbole selon le score', () {
      expect(_category('c', weight: 10, passed: 2, total: 2).symbol, '✅');
      expect(_category('c', weight: 10, passed: 1, total: 2).symbol, '⚠');
      expect(_category('c', weight: 10, passed: 0, total: 2).symbol, '❌');
      expect(
        _category('c', weight: 10, passed: 0, total: 0, skipped: true).symbol,
        '⏭',
      );
    });
  });

  group('overallScore', () {
    test('pondère les catégories par leur poids', () {
      final categories = [
        _category('A', weight: 75, passed: 1, total: 1), // 100
        _category('B', weight: 25, passed: 0, total: 1), // 0
      ];
      expect(overallScore(categories), 75);
    });

    test('redistribue le poids d\'une catégorie non évaluée', () {
      // Sans redistribution, une catégorie skippée à poids 85 plafonnerait
      // mécaniquement le score à 15 — ce qui punirait `--no-analyze`.
      final categories = [
        _category('Évaluée', weight: 15, passed: 1, total: 1),
        _category('Skippée', weight: 85, passed: 0, total: 0, skipped: true),
      ];
      expect(overallScore(categories), 100);
    });

    test('vaut 0 si tout est skippé (pas de division par zéro)', () {
      final categories = [
        _category('A', weight: 50, passed: 0, total: 0, skipped: true),
        _category('B', weight: 50, passed: 0, total: 0, skipped: true),
      ];
      expect(overallScore(categories), 0);
    });
  });

  group('renderReport', () {
    test('est déterministe : deux rendus identiques à l\'octet près', () {
      List<Category> build() => [
        _category('Documentation', weight: 15, passed: 2, total: 3),
        _category('Tests', weight: 25, passed: 0, total: 2),
        _category(
          'Santé technique',
          weight: 15,
          passed: 0,
          total: 0,
          skipped: true,
        ),
      ];

      expect(
        renderReport('FEAT-051', build()),
        renderReport('FEAT-051', build()),
      );
    });

    test('liste les checks manquants et tait ceux qui passent', () {
      final report = renderReport('FEAT-051', [
        Category(
          'Tests',
          weight: 25,
          checks: [
            Check('Tests unitaires', passed: true, detail: 'ne doit pas fuir'),
            Check('Tests widget', passed: false, detail: 'aucun test widget'),
          ],
        ),
      ]);

      expect(report, contains('Tests widget'));
      expect(report, contains('aucun test widget'));
      expect(report, isNot(contains('ne doit pas fuir')));
    });

    test('signale les catégories non évaluées', () {
      final report = renderReport('FEAT-051', [
        _category(
          'Santé technique',
          weight: 15,
          passed: 0,
          total: 0,
          skipped: true,
        ),
        _category('Tests', weight: 85, passed: 1, total: 1),
      ]);

      expect(report, contains('Non évalué'));
      expect(report, contains('Santé technique'));
    });

    test('annonce « prêt » quand tout passe', () {
      final report = renderReport('FEAT-051', [
        _category('Tests', weight: 100, passed: 2, total: 2),
      ]);

      expect(report, contains('100 / 100'));
      expect(report, contains('Aucun.'));
    });

    test('marque les catégories advisory comme documentaires', () {
      final report = renderReport('FEAT-051', [
        Category(
          'Accessibilité',
          weight: 10,
          advisory: true,
          checks: [Check('a11y', passed: false)],
        ),
      ]);

      expect(report, contains('Limites de ce rapport'));
      expect(report, contains('Accessibilité'));
    });
  });
}
