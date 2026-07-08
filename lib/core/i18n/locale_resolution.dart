import 'package:flutter/material.dart' show Locale;

/// Locales supportées par l'app (FEAT-043), dans l'ordre de préférence.
///
/// `fr` en tête : marché principal, sert de fallback système (voir
/// [resolveLocale]) et de résolution par défaut de Flutter en l'absence de
/// correspondance (`supportedLocales.first`). **Toujours** utiliser cette
/// constante pour `MaterialApp.supportedLocales` (prod ET tests) plutôt que
/// `AppLocalizations.supportedLocales` (généré par gen_l10n, ordonné selon
/// le fichier ARB template `app_en.arb` — `en` en tête, ce qui inverserait
/// silencieusement le fallback dans les harnais de test qui ne fixent pas de
/// `locale:` explicite).
const supportedLocales = [Locale('fr'), Locale('en')];

/// Résout la [Locale] à utiliser à partir de la locale système/navigateur
/// [deviceLocale] et de la liste des locales [supported] par l'app.
///
/// Logique (FEAT-043) :
/// - `deviceLocale == null` → fallback FR (marché principal).
/// - `deviceLocale` supporté (comparaison sur `languageCode`, ex. `en-GB` →
///   `en`) → cette locale.
/// - Sinon → fallback FR.
///
/// Fonction pure, extraite de `MaterialApp.localeResolutionCallback`
/// (`main.dart`) pour être testable unitairement sans monter de widget.
Locale resolveLocale(Locale? deviceLocale, Iterable<Locale> supported) {
  if (deviceLocale == null) return const Locale('fr');
  for (final l in supported) {
    if (l.languageCode == deviceLocale.languageCode) return l;
  }
  return const Locale('fr'); // fallback marché principal
}
