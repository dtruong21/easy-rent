#!/usr/bin/env dart

/// FEAT-052 — Feature Readiness Score.
///
/// Produit un rapport markdown *advisory* sur l'état de préparation d'une
/// feature, en lecture seule. Voir `docs/plans/FEAT-052-feature-readiness-score.md`.
///
/// Règles structurantes (business rules du plan) :
/// - **Lecture seule** : ce script n'écrit JAMAIS dans le dépôt. Le rapport
///   part sur stdout ; à l'appelant de le rediriger s'il veut un fichier.
/// - **Déterministe** : même arbre de code → même rapport, à l'octet près.
///   Donc aucun timestamp, aucun chemin absolu, et toute collection listée
///   est triée avant rendu.
/// - **Non bloquant** : exit code 0 quoi qu'il arrive, sauf `--strict`
///   (opt-in, non utilisé par la CI).
///
/// Usage :
///   dart run tool/feature_ready.dart 052
///   dart run tool/feature_ready.dart FEAT-052 --no-analyze
///   dart run tool/feature_ready.dart 052 > /tmp/readiness.md
library;

import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// Modèle
// ---------------------------------------------------------------------------

/// Une vérification élémentaire, mécanique et reproductible.
class Check {
  Check(this.label, {required this.passed, this.detail});

  final String label;
  final bool passed;

  /// Précision affichée quand la vérif échoue (ex. clés ARB manquantes).
  final String? detail;
}

/// Un axe de qualité pondéré. `skipped` = non évalué (poids redistribué).
class Category {
  Category(
    this.name, {
    required this.weight,
    required this.checks,
    this.skipped = false,
    this.skipReason,
    this.advisory = false,
  });

  final String name;
  final int weight;
  final List<Check> checks;
  final bool skipped;
  final String? skipReason;

  /// Vrai quand la vérif est un simple accusé de réception documentaire et
  /// ne prouve pas la qualité réelle (accessibilité, complétude produit).
  final bool advisory;

  int get _passedCount => checks.where((c) => c.passed).length;

  /// Sous-score 0–100. Une catégorie sans check vaut 0.
  int get score {
    if (checks.isEmpty) return 0;
    return ((_passedCount / checks.length) * 100).round();
  }

  String get symbol {
    if (skipped) return '⏭';
    if (score == 100) return '✅';
    if (score == 0) return '❌';
    return '⚠';
  }
}

// ---------------------------------------------------------------------------
// Utilitaires de lecture (aucune écriture)
// ---------------------------------------------------------------------------

/// Liste les fichiers de [dir] (récursif) dont le nom finit par [extension].
/// Trié : l'ordre de `listSync` dépend du système de fichiers, pas nous.
List<File> _filesIn(String dir, {String extension = ''}) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return const [];
  final files = directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith(extension))
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// Fichiers de [dir] contenant [token] (ex. `FEAT-052`), chemins relatifs triés.
List<String> _filesMentioning(
  String dir,
  String token, {
  String extension = '',
}) {
  return _filesIn(dir, extension: extension)
      .where((f) => f.readAsStringSync().contains(token))
      .map((f) => f.path)
      .toList();
}

/// Premier fichier de [dir] dont le nom matche [pattern], ou null.
String? _findFile(String dir, RegExp pattern) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return null;
  final matches =
      directory
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where(pattern.hasMatch)
          .toList()
        ..sort();
  return matches.isEmpty ? null : '$dir/${matches.first}';
}

String _readOrEmpty(String? path) {
  if (path == null) return '';
  final file = File(path);
  return file.existsSync() ? file.readAsStringSync() : '';
}

/// Clés ARB réelles (exclut `@@locale` et les métadonnées `@key`).
/// Même règle que `test/l10n/arb_parity_test.dart` — source de vérité unique.
Set<String> _arbKeys(Map<String, dynamic> json) =>
    json.keys.where((k) => !k.startsWith('@')).toSet();

// ---------------------------------------------------------------------------
// Catégories
// ---------------------------------------------------------------------------

Category _documentation(String featId, String idNum) {
  final plan = _findFile('docs/plans', RegExp('^$featId-.*\\.md\$'));
  final backlog = _findFile('docs/backlog', RegExp('^$idNum-.*\\.md\$'));

  // « documentation mise à jour » = une doc hors plan/backlog cite la feature.
  final otherDocs = _filesMentioning('docs', featId, extension: '.md')
      .where(
        (p) => !p.startsWith('docs/plans/') && !p.startsWith('docs/backlog/'),
      )
      .toList();

  return Category(
    'Documentation',
    weight: 15,
    checks: [
      Check(
        'Plan `docs/plans/$featId-*.md`',
        passed: plan != null,
        detail: 'aucun plan trouvé',
      ),
      Check(
        'Backlog `docs/backlog/$idNum-*.md`',
        passed: backlog != null,
        detail: 'aucune user story trouvée',
      ),
      Check(
        'Documentation citant $featId',
        passed: otherDocs.isNotEmpty,
        detail: 'aucun doc hors plan/backlog ne mentionne $featId',
      ),
    ],
  );
}

Category _testing(String featId) {
  final unit = _filesMentioning('test/unit', featId, extension: '.dart');
  final widget = _filesMentioning('test/widget', featId, extension: '.dart');

  return Category(
    'Tests',
    weight: 25,
    checks: [
      Check(
        'Tests unitaires référençant $featId',
        passed: unit.isNotEmpty,
        detail: 'aucun fichier dans test/unit/ ne mentionne $featId',
      ),
      Check(
        'Tests widget référençant $featId',
        passed: widget.isNotEmpty,
        detail: 'aucun fichier dans test/widget/ ne mentionne $featId',
      ),
    ],
  );
}

Category _localization() {
  final en = File('lib/l10n/app_en.arb');
  final fr = File('lib/l10n/app_fr.arb');

  if (!en.existsSync() || !fr.existsSync()) {
    return Category(
      'Localisation',
      weight: 10,
      checks: [
        Check(
          'Fichiers ARB présents',
          passed: false,
          detail: 'app_en.arb ou app_fr.arb introuvable',
        ),
      ],
    );
  }

  final enKeys = _arbKeys(
    jsonDecode(en.readAsStringSync()) as Map<String, dynamic>,
  );
  final frKeys = _arbKeys(
    jsonDecode(fr.readAsStringSync()) as Map<String, dynamic>,
  );

  final missingInFr = (enKeys.difference(frKeys).toList()..sort());
  final orphanInFr = (frKeys.difference(enKeys).toList()..sort());

  return Category(
    'Localisation',
    weight: 10,
    checks: [
      Check(
        'Aucune clé manquante dans app_fr.arb',
        passed: missingInFr.isEmpty,
        detail: 'manquantes : ${missingInFr.join(', ')}',
      ),
      Check(
        'Aucune clé orpheline dans app_fr.arb',
        passed: orphanInFr.isEmpty,
        detail: 'orphelines : ${orphanInFr.join(', ')}',
      ),
    ],
  );
}

Category _accessibility(String planBody) {
  final body = planBody.toLowerCase();
  return Category(
    'Accessibilité',
    weight: 10,
    advisory: true,
    checks: [
      Check(
        'Le plan traite l\'accessibilité',
        passed: body.contains('accessib') || body.contains('a11y'),
        detail: 'le plan ne mentionne ni accessibilité ni a11y',
      ),
      Check(
        'Le plan traite la navigation clavier / lecteur d\'écran',
        passed:
            body.contains('clavier') ||
            body.contains('keyboard') ||
            body.contains('semantics'),
        detail: 'aucune mention clavier / semantics dans le plan',
      ),
    ],
  );
}

Category _productCompleteness(String planBody) {
  final body = planBody.toLowerCase();
  return Category(
    'Complétude produit',
    weight: 15,
    advisory: true,
    checks: [
      Check(
        'Le plan a des critères d\'acceptation',
        passed:
            body.contains('acceptance criteria') ||
            body.contains('critères d\'acceptation'),
        detail: 'section « Acceptance Criteria » absente du plan',
      ),
      Check(
        'Le plan borne le scope (Non Goals / cas limites)',
        passed:
            body.contains('non goals') ||
            body.contains('non-goals') ||
            body.contains('hors scope') ||
            body.contains('edge case'),
        detail: 'section « Non Goals » / cas limites absente du plan',
      ),
    ],
  );
}

Category _technicalHealth({required bool run}) {
  if (!run) {
    return Category(
      'Santé technique',
      weight: 15,
      checks: const [],
      skipped: true,
      skipReason: '`--no-analyze` : analyzer et format non exécutés',
    );
  }

  // `--output=none` : dart format n'écrit rien, il se contente du code retour.
  final format = _tryRun('dart', [
    'format',
    '--output=none',
    '--set-exit-if-changed',
    '.',
  ]);
  final analyze = _tryRun('flutter', ['analyze']);

  final checks = <Check>[];
  if (format == null) {
    checks.add(
      Check(
        'Formatage (`dart format`)',
        passed: false,
        detail: 'binaire `dart` introuvable',
      ),
    );
  } else {
    checks.add(
      Check(
        'Formatage (`dart format`)',
        passed: format == 0,
        detail: 'des fichiers ne sont pas formatés',
      ),
    );
  }
  if (analyze == null) {
    checks.add(
      Check(
        'Analyse statique (`flutter analyze`)',
        passed: false,
        detail: 'binaire `flutter` introuvable',
      ),
    );
  } else {
    checks.add(
      Check(
        'Analyse statique (`flutter analyze`)',
        passed: analyze == 0,
        detail: '`flutter analyze` remonte des erreurs',
      ),
    );
  }
  return Category('Santé technique', weight: 15, checks: checks);
}

/// Lance [executable] en lecture seule. Retourne le code sortie, ou null si le
/// binaire est absent (machine sans Flutter → catégorie dégradée, pas de crash).
int? _tryRun(String executable, List<String> args) {
  try {
    return Process.runSync(executable, args).exitCode;
  } on ProcessException {
    return null;
  }
}

Category _projectState(String featId) {
  final features = _readOrEmpty('docs/state/FEATURES.md');
  final changelog = _readOrEmpty('docs/state/CHANGELOG.md');

  return Category(
    'État projet',
    weight: 10,
    checks: [
      Check(
        'Ligne $featId dans docs/state/FEATURES.md',
        passed: features.contains(featId),
        detail: 'la matrice de features ne connaît pas $featId',
      ),
      Check(
        '$featId cité dans docs/state/CHANGELOG.md',
        passed: changelog.contains(featId),
        detail: 'aucune entrée changelog pour $featId',
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Score + rendu
// ---------------------------------------------------------------------------

/// Somme pondérée sur les seules catégories évaluées : le poids d'une
/// catégorie skippée est redistribué au prorata, sinon `--no-analyze`
/// plafonnerait mécaniquement le score à 85.
int overallScore(List<Category> categories) {
  final scored = categories.where((c) => !c.skipped).toList();
  final totalWeight = scored.fold<int>(0, (sum, c) => sum + c.weight);
  if (totalWeight == 0) return 0;
  final weighted = scored.fold<double>(0, (sum, c) => sum + c.score * c.weight);
  return (weighted / totalWeight).round();
}

String renderReport(String featId, List<Category> categories) {
  final buffer = StringBuffer()
    ..writeln('# Feature Readiness — $featId')
    ..writeln()
    ..writeln('## Score global')
    ..writeln()
    ..writeln('**${overallScore(categories)} / 100**')
    ..writeln()
    ..writeln('## Détail par catégorie')
    ..writeln()
    ..writeln('| Catégorie | Poids | Score | Statut |')
    ..writeln('| --- | --- | --- | --- |');

  for (final c in categories) {
    final score = c.skipped ? '—' : '${c.score} / 100';
    buffer.writeln('| ${c.name} | ${c.weight}% | $score | ${c.symbol} |');
  }

  final missing = <String>[];
  for (final c in categories) {
    if (c.skipped) continue;
    for (final check in c.checks.where((ch) => !ch.passed)) {
      final detail = check.detail == null ? '' : ' — ${check.detail}';
      missing.add('- **${c.name}** : ${check.label}$detail');
    }
  }

  buffer
    ..writeln()
    ..writeln('## Points manquants')
    ..writeln();
  if (missing.isEmpty) {
    buffer.writeln('Aucun. Toutes les vérifications mécaniques passent.');
  } else {
    missing.forEach(buffer.writeln);
  }

  final skipped = categories.where((c) => c.skipped).toList();
  if (skipped.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Non évalué')
      ..writeln();
    for (final c in skipped) {
      buffer.writeln(
        '- **${c.name}** : ${c.skipReason}. '
        'Poids redistribué sur les autres catégories.',
      );
    }
  }

  final advisory = categories
      .where((c) => c.advisory && c.score < 100)
      .toList();
  if (advisory.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Limites de ce rapport')
      ..writeln()
      ..writeln(
        'Ces catégories sont vérifiées **documentairement** : le script '
        'lit le plan, il ne juge pas la qualité réelle. Un ✅ ici ne remplace '
        'ni la revue de code ni la QA.',
      )
      ..writeln();
    for (final c in advisory) {
      buffer.writeln('- ${c.name}');
    }
  }

  buffer
    ..writeln()
    ..writeln('## Recommandation')
    ..writeln();
  final score = overallScore(categories);
  if (missing.isEmpty) {
    buffer.writeln(
      'Prêt à merger du point de vue des vérifications '
      'automatiques.',
    );
  } else {
    final weak =
        (categories.where((c) => !c.skipped && c.score < 100).toList()
              ..sort((a, b) => b.weight.compareTo(a.weight)))
            .map((c) => c.name)
            .toList();
    buffer
      ..writeln('Score $score/100. À traiter en priorité :')
      ..writeln();
    for (final name in weak) {
      buffer.writeln('- $name');
    }
  }

  buffer
    ..writeln()
    ..writeln('---')
    ..writeln()
    ..writeln('_Rapport advisory et déterministe. N\'échoue jamais la CI._');

  return buffer.toString();
}

// ---------------------------------------------------------------------------
// Entrée
// ---------------------------------------------------------------------------

/// Normalise `52`, `052` ou `FEAT-052` en `('FEAT-052', '052')`.
/// Retourne null si l'argument n'est pas un identifiant de feature.
({String featId, String idNum})? parseFeatureId(String raw) {
  final match = RegExp(
    r'^(?:FEAT-)?(\d{1,3})$',
    caseSensitive: false,
  ).firstMatch(raw.trim());
  if (match == null) return null;
  final idNum = match.group(1)!.padLeft(3, '0');
  return (featId: 'FEAT-$idNum', idNum: idNum);
}

/// Construit le rapport. Exposé pour les tests.
List<Category> buildCategories(
  String featId,
  String idNum, {
  required bool analyze,
}) {
  final planPath = _findFile('docs/plans', RegExp('^$featId-.*\\.md\$'));
  final planBody = _readOrEmpty(planPath);

  return [
    _documentation(featId, idNum),
    _testing(featId),
    _localization(),
    _accessibility(planBody),
    _productCompleteness(planBody),
    _technicalHealth(run: analyze),
    _projectState(featId),
  ];
}

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final analyze = !args.contains('--no-analyze');
  final strict = args.contains('--strict');

  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/feature_ready.dart <FEAT-ID> '
      '[--no-analyze] [--strict]',
    );
    exit(64); // EX_USAGE
  }

  final parsed = parseFeatureId(positional.first);
  if (parsed == null) {
    stderr.writeln(
      'Identifiant invalide : "${positional.first}". '
      'Attendu : 52, 052 ou FEAT-052.',
    );
    exit(64);
  }

  final categories = buildCategories(
    parsed.featId,
    parsed.idNum,
    analyze: analyze,
  );
  stdout.write(renderReport(parsed.featId, categories));

  // Non bloquant par défaut (business rule du plan). `--strict` est un opt-in
  // manuel : la CI ne l'utilise pas.
  if (strict && overallScore(categories) < 100) exit(1);
}
