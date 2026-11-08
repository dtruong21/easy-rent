/**
 * Composition de l'adresse complète d'un bien (rue + code postal + ville).
 *
 * ## Pourquoi
 *
 * `properties` porte TROIS champs séparés : `address`, `postalCode`, `city`.
 * Le formulaire de création (`property_form.dart`) étiquette `address`
 * « Adresse complète » mais son hint est « Ex. : 12 rue de la Paix » et il
 * expose juste en dessous deux champs distincts « Code postal » / « Ville » :
 * en pratique les bailleurs n'y saisissent QUE la rue. Recopier `address`
 * seul sur le bail produit une quittance dont le champ « Logement : » ne
 * permet pas d'identifier le logement — un défaut vis-à-vis de la loi du
 * 6 juillet 1989.
 *
 * ## Pourquoi ce n'est pas une simple concaténation
 *
 * Rien n'empêche un bailleur d'avoir saisi l'adresse complète dans le seul
 * champ `address` (« 48 avenue du Hazay, 95000 Cergy ») ET renseigné
 * `postalCode`/`city`. Concaténer aveuglément donnerait
 * « 48 avenue du Hazay, 95000 Cergy, 95000 Cergy ». On n'ajoute donc que les
 * composants ABSENTS de `address`, détectés sur une forme repliée
 * (minuscules, sans accents, ponctuation → espaces) et à la frontière de mot
 * — « Cergy » ne doit matcher ni « Cergy-Pontoise » ni « 95000 » le numéro de
 * rue « 950001 ».
 *
 * ⚠️ Miroir Dart : `lib/core/utils/property_address.dart`. Les deux
 * implémentations doivent rester d'accord (mêmes cas de test des deux côtés) :
 * le serveur fige la valeur sur le bail, le client affiche la même chose
 * depuis le bien.
 */

/** Champs d'adresse d'un doc `properties`, tels que lus depuis Firestore. */
export interface PropertyAddressParts {
  address?: unknown;
  postalCode?: unknown;
  city?: unknown;
}

/** Diacritiques Unicode isolés par NFD (U+0300–U+036F). */
const COMBINING_MARKS = /[\u0300-\u036f]/g;

/** Position d'une occurrence dans la chaîne repliée (= index bruts). */
interface Match {
  start: number;
  end: number;
}

/** `unknown` Firestore → texte exploitable ("" si absent/non textuel). */
function asText(value: unknown): string {
  if (typeof value === "string") return value.trim();
  // Un code postal saisi comme nombre reste un code postal.
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return "";
}

/**
 * Repli d'UN caractère : minuscule, sans accent, tout ce qui n'est pas
 * alphanumérique devient un espace — SAUF le trait d'union, conservé tel quel.
 *
 * Pourquoi garder le trait d'union : il est à la fois séparateur INTERNE d'un
 * nom de commune (« Saint-Leu-la-Forêt » ≡ « Saint Leu la Forêt », qu'il faut
 * reconnaître comme identiques) et frontière SIGNIFIANTE entre deux communes
 * distinctes (« Cergy » ≠ « Cergy-Pontoise », qu'il ne faut PAS confondre).
 * L'aplatir en espace rendrait le second cas indétectable. On le garde donc
 * comme caractère de mot pour les frontières, et on l'accepte comme séparateur
 * élastique à l'intérieur du besoin recherché.
 *
 * Contrat critique : la sortie fait TOUJOURS exactement un caractère, donc
 * `fold()` préserve les index — une position trouvée dans la chaîne repliée
 * désigne le même caractère dans la chaîne brute. C'est ce qui permet
 * d'insérer le code postal devant la ville sans recalcul fragile.
 */
function foldChar(ch: string): string {
  // NFD sépare la lettre de son diacritique ; on garde la lettre de base.
  // `toLowerCase` peut rendre plusieurs caractères (ex. « İ ») — d'où le [0].
  const base = ch.toLowerCase().normalize("NFD").replace(COMBINING_MARKS, "");
  // `charAt` (et non `[0]`) : rend "" et jamais `undefined` sur chaîne vide,
  // donc pas de trou sous `noUncheckedIndexedAccess`.
  const first = base.charAt(0);
  return /[a-z0-9-]/.test(first) ? first : " ";
}

/** Repli d'une chaîne, caractère par caractère (longueur préservée). */
function fold(value: string): string {
  let out = "";
  // Itération par unité de code UTF-16 (et non par point de code) : une paire
  // de substitution doit produire deux caractères pour garder l'alignement.
  for (let i = 0; i < value.length; i++) out += foldChar(value.charAt(i));
  return out;
}

/**
 * Dernière occurrence de `needle` dans la chaîne repliée `folded`, à la
 * frontière de mot. Les séparateurs internes du besoin sont élastiques
 * (« Saint Leu » matche « Saint-Leu »), mais les frontières sont strictes :
 * « Cergy » ne matche NI « Cergyville » NI « Cergy-Pontoise ». `null` si
 * absent.
 */
function lastMatch(folded: string, needle: string): Match | null {
  // Découpage sur espaces ET traits d'union : « Saint-Leu-la-Forêt » et
  // « Saint Leu la Forêt » donnent la même liste de tokens.
  const tokens = fold(needle).split(/[\s-]+/).filter((t) => t.length > 0);
  if (tokens.length === 0) return null;
  // Les tokens sortent de `fold` : uniquement [a-z0-9], rien à échapper.
  const body = tokens.join("[\\s-]+");
  const re = new RegExp(`(?<![a-z0-9-])${body}(?![a-z0-9-])`, "g");
  let found: Match | null = null;
  for (const m of folded.matchAll(re)) {
    found = {start: m.index, end: m.index + m[0].length};
  }
  return found;
}

/** Vrai si plus aucun caractère de mot après `match`. */
function isTrailing(folded: string, match: Match): boolean {
  return !/[a-z0-9-]/.test(folded.slice(match.end));
}

/** Retire espaces et séparateurs de fin, pour ne pas produire « rue X,, 95 ». */
function trimSeparators(value: string): string {
  return value.replace(/[\s,;]+$/, "");
}

/**
 * Adresse complète d'un bien : `address`, complété par `postalCode` et `city`
 * UNIQUEMENT s'ils n'y figurent pas déjà.
 *
 * Exemples :
 *   ("48 avenue du Hazay", "95000", "Cergy")        → "48 avenue du Hazay, 95000 Cergy"
 *   ("48 avenue du Hazay, 95000 Cergy", "95000", "Cergy") → inchangé
 *   ("48 avenue du Hazay, Cergy", "95000", "Cergy") → "48 avenue du Hazay, 95000 Cergy"
 *   ("48 avenue du Hazay", null, null)              → "48 avenue du Hazay"
 */
export function composePropertyAddress(parts: PropertyAddressParts): string {
  const address = asText(parts.address);
  const postalCode = asText(parts.postalCode);
  const city = asText(parts.city);

  // Bien sans rue : on rend ce qu'on a plutôt qu'une chaîne vide.
  if (address === "") {
    return [postalCode, city].filter((s) => s !== "").join(" ");
  }

  const folded = fold(address);
  const pcMatch = postalCode === "" ? null : lastMatch(folded, postalCode);
  const cityMatch = city === "" ? null : lastMatch(folded, city);

  const needsPostalCode = postalCode !== "" && pcMatch === null;
  const needsCity = city !== "" && cityMatch === null;

  // Rien à ajouter : l'adresse est déjà complète (ou les champs sont vides).
  if (!needsPostalCode && !needsCity) return address;

  const base = trimSeparators(address);

  if (needsPostalCode && needsCity) return `${base}, ${postalCode} ${city}`;

  if (needsCity) {
    // Le code postal est déjà là. S'il TERMINE l'adresse, la ville se colle
    // derrière sans virgule : « 48 avenue du Hazay, 95000 Cergy ».
    const glued = pcMatch !== null && isTrailing(folded, pcMatch);
    return glued ? `${base} ${city}` : `${base}, ${city}`;
  }

  // Seul le code postal manque : l'adresse nomme déjà la ville. Si elle la
  // TERMINE, on insère le code postal juste devant, à sa place canonique.
  if (cityMatch !== null && isTrailing(folded, cityMatch)) {
    const head = trimSeparators(address.slice(0, cityMatch.start));
    const tail = address.slice(cityMatch.start).trim();
    return head === "" ? `${postalCode} ${tail}` : `${head}, ${postalCode} ${tail}`;
  }
  return `${base}, ${postalCode}`;
}
