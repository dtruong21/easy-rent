// Générateur des miroirs de la palette Baillan.
//
//   dart run tool/gen_theme_tokens.dart
//
// Lit `config/theme_tokens.json` (SOURCE CANONIQUE UNIQUE) et écrit deux
// miroirs : `lib/core/theme/app_palette.g.dart` pour l'app, et
// `site/src/styles/tokens.css` pour la vitrine. Garde-fou :
// `bash scripts/check-theme-tokens.sh`.
//
// Pourquoi générer plutôt que laisser chaque camp déclarer ses couleurs : la
// vitrine et l'app doivent être indiscernables à l'œil. Une double déclaration
// rend la divergence possible ; la génération la rend inexprimable.

import 'dart:convert';
import 'dart:io';

const _source = 'config/theme_tokens.json';
const _dartOut = 'lib/core/theme/app_palette.g.dart';
const _cssOut = 'site/src/styles/tokens.css';

/// `oliveMid` -> `olive-mid`, pour les noms de variables CSS.
String _kebab(String camel) =>
    camel.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');

void main() {
  final raw = File(_source).readAsStringSync();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final colors = (decoded['colors'] as Map<String, dynamic>)
      .cast<String, String>();

  if (colors.isEmpty) {
    stderr.writeln('$_source ne déclare aucune couleur.');
    exit(1);
  }

  final hexRe = RegExp(r'^#[0-9A-F]{6}$');
  for (final entry in colors.entries) {
    if (!hexRe.hasMatch(entry.value)) {
      stderr.writeln(
        'Couleur invalide : ${entry.key} = "${entry.value}". '
        'Format attendu : #RRGGBB en majuscules.',
      );
      exit(1);
    }
  }

  const header =
      '// GENERATED — do not edit. Source: $_source\n'
      '// Regenerate: dart run tool/gen_theme_tokens.dart\n'
      '// Guard: bash scripts/check-theme-tokens.sh\n';

  final dart = StringBuffer()
    ..writeln(header)
    ..writeln("import 'package:flutter/painting.dart';")
    ..writeln()
    ..writeln('/// Palette canonique de Baillan, partagée avec la vitrine.')
    ..writeln('abstract final class AppPalette {');
  for (final entry in colors.entries) {
    final argb = '0xFF${entry.value.substring(1)}';
    dart.writeln('  static const Color ${entry.key} = Color($argb);');
  }
  dart.writeln('}');
  File(_dartOut).writeAsStringSync(dart.toString());

  final css = StringBuffer()
    ..writeln(
      header.replaceAll('//', '/*').replaceAll('\n', ' */\n').trimRight(),
    )
    ..writeln(':root {');
  for (final entry in colors.entries) {
    css.writeln('  --color-${_kebab(entry.key)}: ${entry.value};');
  }
  css.writeln('}');
  Directory(File(_cssOut).parent.path).createSync(recursive: true);
  File(_cssOut).writeAsStringSync(css.toString());

  stdout.writeln('${colors.length} couleurs → $_dartOut, $_cssOut');
}
