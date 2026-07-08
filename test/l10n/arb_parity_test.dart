/// Vérifie que `app_en.arb` (template) et `app_fr.arb` exposent EXACTEMENT
/// le même jeu de clés (FEAT-043 — R5 : éviter les dérives lors de
/// l'extraction module par module à venir, cf.
/// `lib/l10n/l10n_convention.dart`).
///
/// Complète `l10n_untranslated.json` (généré par `flutter gen-l10n`, doit
/// rester vide) par une vérification indépendante de la présence du fichier
/// build.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Clés ARB réelles (exclut les métadonnées `@@...` et `@key`).
Set<String> _arbKeys(Map<String, dynamic> json) {
  return json.keys.where((k) => !k.startsWith('@')).toSet();
}

void main() {
  test('app_en.arb et app_fr.arb ont le même jeu de clés', () {
    final enFile = File('lib/l10n/app_en.arb');
    final frFile = File('lib/l10n/app_fr.arb');

    expect(enFile.existsSync(), isTrue, reason: 'app_en.arb introuvable');
    expect(frFile.existsSync(), isTrue, reason: 'app_fr.arb introuvable');

    final enJson =
        jsonDecode(enFile.readAsStringSync()) as Map<String, dynamic>;
    final frJson =
        jsonDecode(frFile.readAsStringSync()) as Map<String, dynamic>;

    final enKeys = _arbKeys(enJson);
    final frKeys = _arbKeys(frJson);

    final missingInFr = enKeys.difference(frKeys);
    final extraInFr = frKeys.difference(enKeys);

    expect(
      missingInFr,
      isEmpty,
      reason:
          'Clés présentes dans app_en.arb mais absentes de app_fr.arb : '
          '$missingInFr',
    );
    expect(
      extraInFr,
      isEmpty,
      reason:
          'Clés présentes dans app_fr.arb mais absentes de app_en.arb '
          '(orphelines) : $extraInFr',
    );
  });

  test('chaque clé du template a une description (@key.description)', () {
    final enFile = File('lib/l10n/app_en.arb');
    final enJson =
        jsonDecode(enFile.readAsStringSync()) as Map<String, dynamic>;

    final keys = _arbKeys(enJson);
    final missingDescription = <String>[];

    for (final key in keys) {
      final meta = enJson['@$key'];
      if (meta is! Map || (meta['description'] as String?)?.isEmpty != false) {
        missingDescription.add(key);
      }
    }

    expect(
      missingDescription,
      isEmpty,
      reason:
          'Clés sans metadata `description` dans app_en.arb (convention '
          'lib/l10n/l10n_convention.dart, règle 6) : $missingDescription',
    );
  });
}
