import 'package:flutter/material.dart';

/// Clé de palette pour la couleur d'identité d'un bien immobilier.
///
/// **On stocke une CLÉ, jamais une couleur brute.** Un `#RRGGBB` figé serait
/// illisible dans l'un des deux thèmes (l'app a un mode clair et un mode
/// sombre) — la clé est résolue en [Color] via [PropertyColorPalette],
/// exactement comme `StatusPillTone` l'est via `AppColors`
/// (`lib/core/ui/theme/app_colors.dart`).
///
/// 8 teintes, choisies pour s'accorder au thème papier/encre/olive
/// (`lib/core/theme/app_theme.dart`) — jamais de couleurs primaires
/// criardes, et volontairement à l'écart de l'olive (couleur `primary`,
/// utilisée par les boutons/actions) et de l'oxblood (réservé aux états
/// d'erreur) pour ne jamais laisser croire qu'un point de couleur
/// décoratif est une action ou une alerte.
///
/// La couleur ne porte jamais l'information seule (WCAG) : le nom du bien
/// reste affiché partout où cette clé est utilisée — voir
/// `PropertyColorDot` (décoratif, à côté du texte, jamais à sa place).
enum PropertyColorKey {
  /// Rouille — orange-brun chaud.
  rouille,

  /// Bordeaux — rouge profond, tirant sur le magenta.
  bordeaux,

  /// Prune — violet sourd.
  prune,

  /// Cobalt — bleu vif mais sourd.
  cobalt,

  /// Ardoise — bleu-gris minéral (volontairement distinct du teal
  /// abandonné de l'ancienne identité EasyRent, cf. `docs/state/THEME.md`).
  ardoise,

  /// Sauge — vert grisé, distinct de l'olive `primary`.
  sauge,

  /// Moutarde — kaki doré, volontairement désaturé pour rester distinct
  /// de l'alias sémantique `AppTheme.echu` (ochre, utilisé pour les
  /// échéances — cf. `docs/state/DESIGN_TOKENS.md`).
  moutarde,

  /// Rose poudré — mauve rosé désaturé.
  rosePoudre;

  /// Parse une valeur stockée (Firestore, `colorKey`) vers l'enum.
  ///
  /// Retourne `null` si [value] est `null`, vide ou ne correspond à aucune
  /// clé connue (tolérance au drift — un futur retrait de couleur de la
  /// palette ne doit jamais planter la résolution, juste retomber sur le
  /// repli déterministe de [resolve]).
  static PropertyColorKey? parse(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final key in PropertyColorKey.values) {
      if (key.name == value) return key;
    }
    return null;
  }

  /// Résout la couleur d'identité d'une entité (bien, ou toute entité
  /// rattachée à un bien).
  ///
  /// - Si [stored] est une clé valide (bien déjà personnalisé, ou attribué
  ///   côté serveur), elle est utilisée telle quelle.
  /// - Sinon, repli déterministe : un hash stable de [entityId] (l'UUID du
  ///   bien) choisit une teinte dans la palette. **Stable et non stocké** —
  ///   couvre à la fois les biens créés avant l'introduction de cette
  ///   fonctionnalité (`colorKey` absent) et les biens tout juste créés
  ///   (l'attribution serveur est un follow-up, cf. plan) : dans les deux
  ///   cas, le bien affiche immédiatement une couleur automatique, stable
  ///   d'une session à l'autre.
  ///
  /// ⚠️ N'utilise jamais `Object.hashCode` / `String.hashCode` : Dart ne
  /// garantit leur stabilité qu'au sein d'un même run process
  /// (hash-randomisation possible d'un run à l'autre). Le repli doit rester
  /// identique à chaque ouverture de l'app — d'où le hash FNV-1a maison.
  static PropertyColorKey resolve({required String entityId, String? stored}) {
    final parsed = parse(stored);
    if (parsed != null) return parsed;
    final hash = _stableHash(entityId);
    return PropertyColorKey.values[hash % PropertyColorKey.values.length];
  }
}

/// Hash FNV-1a 32 bits — déterministe sur toute plateforme/run, contrairement
/// à `String.hashCode` (non garanti stable inter-run par la spec Dart).
int _stableHash(String input) {
  const prime = 0x01000193;
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * prime) & 0xFFFFFFFF;
  }
  return hash;
}

/// Ensemble des couleurs résolues pour chaque [PropertyColorKey], décliné
/// light/dark — extension de thème Material 3, même pattern que `AppColors`
/// (`lib/core/ui/theme/app_colors.dart`).
///
/// Accès : `Theme.of(context).extension<PropertyColorPalette>()!.of(key)`,
/// ou plus simplement `key.resolveColor(context)` (voir
/// [PropertyColorKeyThemeX]).
@immutable
class PropertyColorPalette extends ThemeExtension<PropertyColorPalette> {
  const PropertyColorPalette({required this.swatches});

  final Map<PropertyColorKey, Color> swatches;

  /// Couleur résolue pour [key]. Replie sur la première teinte de la carte
  /// si jamais [key] n'y figurait pas (défense en profondeur — ne devrait
  /// pas arriver, [swatches] couvre toujours `PropertyColorKey.values`).
  Color of(PropertyColorKey key) =>
      swatches[key] ?? swatches[PropertyColorKey.values.first]!;

  /// Palette claire.
  static const PropertyColorPalette light = PropertyColorPalette(
    swatches: {
      PropertyColorKey.rouille: Color(0xFFB3612B),
      PropertyColorKey.bordeaux: Color(0xFF8C3A55),
      PropertyColorKey.prune: Color(0xFF6B4A87),
      PropertyColorKey.cobalt: Color(0xFF2E5F8A),
      PropertyColorKey.ardoise: Color(0xFF355D6E),
      PropertyColorKey.sauge: Color(0xFF4F7A54),
      PropertyColorKey.moutarde: Color(0xFF78723A),
      PropertyColorKey.rosePoudre: Color(0xFFA97A85),
    },
  );

  /// Palette sombre — teintes éclaircies pour rester lisibles sur fond encre,
  /// même logique que `oliveSoft` (dérivé de `olive`) dans `app_theme.dart`.
  static const PropertyColorPalette dark = PropertyColorPalette(
    swatches: {
      PropertyColorKey.rouille: Color(0xFFD98F5F),
      PropertyColorKey.bordeaux: Color(0xFFC97D96),
      PropertyColorKey.prune: Color(0xFFB79ACB),
      PropertyColorKey.cobalt: Color(0xFF89B4DD),
      PropertyColorKey.ardoise: Color(0xFF91B9CA),
      PropertyColorKey.sauge: Color(0xFF93C79A),
      PropertyColorKey.moutarde: Color(0xFFCDC898),
      PropertyColorKey.rosePoudre: Color(0xFFD9B7BE),
    },
  );

  @override
  PropertyColorPalette copyWith({Map<PropertyColorKey, Color>? swatches}) {
    return PropertyColorPalette(swatches: swatches ?? this.swatches);
  }

  @override
  PropertyColorPalette lerp(
    ThemeExtension<PropertyColorPalette>? other,
    double t,
  ) {
    if (other is! PropertyColorPalette) return this;
    final result = <PropertyColorKey, Color>{};
    for (final key in PropertyColorKey.values) {
      final a = swatches[key];
      final b = other.swatches[key];
      if (a != null && b != null) {
        result[key] = Color.lerp(a, b, t)!;
      } else {
        result[key] = b ?? a ?? swatches.values.first;
      }
    }
    return PropertyColorPalette(swatches: result);
  }
}

/// Raccourci de résolution thème pour un [PropertyColorKey].
extension PropertyColorKeyThemeX on PropertyColorKey {
  /// Couleur résolue dans le thème courant (light/dark).
  ///
  /// Replie sur [PropertyColorPalette.light] si l'extension n'est pas
  /// enregistrée dans le thème (défense en profondeur pour les tests
  /// widget qui construisent un `ThemeData` minimal).
  Color resolveColor(BuildContext context) {
    final palette = Theme.of(context).extension<PropertyColorPalette>();
    return (palette ?? PropertyColorPalette.light).of(this);
  }
}
