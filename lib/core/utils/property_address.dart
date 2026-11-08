/// Composition de l'adresse complète d'un bien (rue + code postal + ville).
///
/// ## Pourquoi
///
/// Un `Property` porte TROIS champs séparés : `address`, `postalCode`, `city`.
/// Le formulaire de création étiquette `address` « Adresse complète » mais son
/// hint est « Ex. : 12 rue de la Paix » et il expose juste en dessous deux
/// champs distincts « Code postal » / « Ville » : en pratique les bailleurs
/// n'y saisissent QUE la rue. Afficher `property.address` seul tronque donc
/// l'adresse partout où elle apparaît (bandeau de quittances, en-tête de bail,
/// texte de partage, PDF de régularisation de charges).
///
/// ## Pourquoi ce n'est pas une simple concaténation
///
/// Rien n'empêche un bailleur d'avoir saisi l'adresse complète dans le seul
/// champ `address` (« 48 avenue du Hazay, 95000 Cergy ») ET renseigné
/// `postalCode`/`city`. Concaténer aveuglément donnerait
/// « 48 avenue du Hazay, 95000 Cergy, 95000 Cergy ». On n'ajoute donc que les
/// composants ABSENTS de `address`, détectés sur une forme repliée
/// (minuscules, sans accents, ponctuation → espaces) et à la frontière de mot.
///
/// ## ⚠️ Miroir TypeScript
///
/// Jumeau de `functions/src/utils/property_address.ts`, dupliqué faute de
/// chemin de partage de LOGIQUE entre Dart et TypeScript dans ce dépôt (le
/// seul pont existant, `config/entitlements.json` → `plan_matrix.g.dart`,
/// transporte des DONNÉES, pas du code). Les deux implémentations portent le
/// même jeu de cas de test (`test/unit/property_address_test.dart` ↔
/// `functions/src/__tests__/property_address.test.ts`) : le serveur fige la
/// valeur sur le bail à sa création, le client affiche la même chose en
/// relisant le bien. Une divergence donnerait deux adresses différentes pour
/// le même logement — toute modification ici doit être répercutée là-bas.
library;

/// Repli des diacritiques latins vers leur lettre de base.
///
/// Équivalent Dart de `normalize("NFD")` + suppression des marques combinantes
/// côté TypeScript, que la bibliothèque standard Dart n'expose pas. Couvre le
/// Latin-1 Supplement (français et langues voisines) ; les ligatures sont
/// repliées sur UNE lettre pour préserver la longueur (cf. `_fold`).
const Map<String, String> _diacritics = <String, String>{
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ð': 'd',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'œ': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ß': 's',
  'þ': 't',
};

/// Caractères considérés comme « de mot » après repli.
final RegExp _wordChar = RegExp(r'[a-z0-9-]');

/// Séparateurs internes d'un composant recherché (espaces et traits d'union).
final RegExp _needleSeparators = RegExp(r'[\s-]+');

/// Espaces et séparateurs en fin de chaîne.
final RegExp _trailingSeparators = RegExp(r'[\s,;]+$');

/// Repli d'UNE unité de code UTF-16 : minuscule, sans accent, tout ce qui
/// n'est pas alphanumérique devient un espace — SAUF le trait d'union.
///
/// Pourquoi garder le trait d'union : il est à la fois séparateur INTERNE d'un
/// nom de commune (« Saint-Leu-la-Forêt » ≡ « Saint Leu la Forêt », qu'il faut
/// reconnaître comme identiques) et frontière SIGNIFIANTE entre deux communes
/// distinctes (« Cergy » ≠ « Cergy-Pontoise », qu'il ne faut PAS confondre).
///
/// Contrat critique : la sortie fait TOUJOURS exactement un caractère, donc
/// `_fold` préserve les index — une position trouvée dans la chaîne repliée
/// désigne le même caractère dans la chaîne brute. C'est ce qui permet
/// d'insérer le code postal devant la ville sans recalcul fragile.
String _foldUnit(String unit) {
  final String lower = unit.toLowerCase();
  // `toLowerCase` peut rendre plusieurs caractères (ex. « İ ») — d'où le [0].
  final String single = lower.isEmpty ? ' ' : lower[0];
  final String base = _diacritics[single] ?? single;
  return _wordChar.hasMatch(base) ? base : ' ';
}

/// Repli d'une chaîne, unité de code par unité de code (longueur préservée).
String _fold(String value) {
  final StringBuffer out = StringBuffer();
  for (final int unit in value.codeUnits) {
    out.write(_foldUnit(String.fromCharCode(unit)));
  }
  return out.toString();
}

/// Dernière occurrence de [needle] dans la chaîne repliée [folded], à la
/// frontière de mot. Les séparateurs internes du besoin sont élastiques
/// (« Saint Leu » matche « Saint-Leu »), mais les frontières sont strictes :
/// « Cergy » ne matche NI « Cergyville » NI « Cergy-Pontoise ».
Match? _lastMatch(String folded, String needle) {
  final List<String> tokens = _fold(
    needle,
  ).split(_needleSeparators).where((String t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return null;
  // Les tokens sortent de `_fold` : uniquement [a-z0-9], rien à échapper.
  final String body = tokens.join(r'[\s-]+');
  final RegExp re = RegExp('(?<![a-z0-9-])$body(?![a-z0-9-])');
  Match? found;
  for (final Match m in re.allMatches(folded)) {
    found = m;
  }
  return found;
}

/// Vrai si plus aucun caractère de mot après [match].
bool _isTrailing(String folded, Match match) =>
    !_wordChar.hasMatch(folded.substring(match.end));

/// Retire espaces et séparateurs de fin, pour ne pas produire « rue X,, 95 ».
String _trimSeparators(String value) =>
    value.replaceAll(_trailingSeparators, '');

/// Adresse complète d'un bien : [address], complété par [postalCode] et [city]
/// UNIQUEMENT s'ils n'y figurent pas déjà.
///
/// Exemples :
/// ```
/// ('48 avenue du Hazay', '95000', 'Cergy')        → '48 avenue du Hazay, 95000 Cergy'
/// ('48 avenue du Hazay, 95000 Cergy', '95000', 'Cergy') → inchangé
/// ('48 avenue du Hazay, Cergy', '95000', 'Cergy') → '48 avenue du Hazay, 95000 Cergy'
/// ('48 avenue du Hazay', null, null)              → '48 avenue du Hazay'
/// ```
String composePropertyAddress({
  String? address,
  String? postalCode,
  String? city,
}) {
  final String street = (address ?? '').trim();
  final String zip = (postalCode ?? '').trim();
  final String town = (city ?? '').trim();

  // Bien sans rue : on rend ce qu'on a plutôt qu'une chaîne vide.
  if (street.isEmpty) {
    return <String>[zip, town].where((String s) => s.isNotEmpty).join(' ');
  }

  final String folded = _fold(street);
  final Match? zipMatch = zip.isEmpty ? null : _lastMatch(folded, zip);
  final Match? townMatch = town.isEmpty ? null : _lastMatch(folded, town);

  final bool needsZip = zip.isNotEmpty && zipMatch == null;
  final bool needsTown = town.isNotEmpty && townMatch == null;

  // Rien à ajouter : l'adresse est déjà complète (ou les champs sont vides).
  if (!needsZip && !needsTown) return street;

  final String base = _trimSeparators(street);

  if (needsZip && needsTown) return '$base, $zip $town';

  if (needsTown) {
    // Le code postal est déjà là. S'il TERMINE l'adresse, la ville se colle
    // derrière sans virgule : « 48 avenue du Hazay, 95000 Cergy ».
    final bool glued = zipMatch != null && _isTrailing(folded, zipMatch);
    return glued ? '$base $town' : '$base, $town';
  }

  // Seul le code postal manque : l'adresse nomme déjà la ville. Si elle la
  // TERMINE, on insère le code postal juste devant, à sa place canonique.
  if (townMatch != null && _isTrailing(folded, townMatch)) {
    final String head = _trimSeparators(street.substring(0, townMatch.start));
    final String tail = street.substring(townMatch.start).trim();
    return head.isEmpty ? '$zip $tail' : '$head, $zip $tail';
  }
  return '$base, $zip';
}
