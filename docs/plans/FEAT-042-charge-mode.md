# Plan — [FEAT-042] Mode de charges (provisions / forfait) + éligibilité de la régularisation

## Summary

La régularisation des charges est aujourd'hui gatée sur `lease.leaseType == LeaseType.unfurnished`, ce qui est juridiquement faux : le vrai critère est le **mode de charges** (provisions vs forfait), pas le type de bail. On introduit un enum `ChargeMode { provisions, forfait }` et un champ `chargeMode` sur `leases`. La régularisation devient éligible **ssi le mode effectif est `provisions`**. Le serveur impose la cohérence type↔mode : **nu → provisions (forcé)**, **mobilité → forfait (forcé)**, **meublé/étudiant → choix (défaut provisions)**. Migration lazy sans backfill via un getter `effectiveChargeMode` qui dérive un mode correct pour les baux pré-042.

## Data model changes

> Stack Firebase (Firestore camelCase + Cloud Functions TS). `leases` est CF-exclusive. Pas de SQL/RLS : la validation vit dans les Cloud Functions callables + les Firestore rules existantes (déjà CF-exclusive pour `leases`).

### Nouvel enum Dart — `lib/features/leases/domain/charge_mode.dart`

```dart
enum ChargeMode {
  provisions,   // provisions mensuelles + régularisation annuelle
  forfait;      // forfait libératoire — pas de régularisation

  String get sqlValue => name;             // stocké en Firestore (camelCase natif = name)
  String get labelFr => switch (this) {
    ChargeMode.provisions => 'Provisions + régularisation',
    ChargeMode.forfait => 'Forfait',
  };

  /// Tolérance défensive : null/inconnu → null (le getter effectiveChargeMode dérive).
  static ChargeMode? fromSqlOrNull(String? v) {
    if (v == null) return null;
    for (final m in ChargeMode.values) {
      if (m.name == v) return m;
    }
    return null;
  }
}
```

### Champ sur le modèle `Lease` — `lib/features/leases/domain/lease.dart`

Ajouter un champ **nullable** (pas de `@Default`) pour distinguer « pré-042 » (null → dérivé) de « choisi » :

```dart
@JsonKey(name: 'charge_mode', fromJson: _chargeModeFromJson, toJson: _chargeModeToJson)
ChargeMode? chargeMode,
```

Helpers JSON (nullable, jamais de fallback silencieux vers une valeur concrète — le null est signifiant) :

```dart
ChargeMode? _chargeModeFromJson(dynamic v) => ChargeMode.fromSqlOrNull(v as String?);
String? _chargeModeToJson(ChargeMode? v) => v?.sqlValue;
```

### Migration lazy (AUCUN script / backfill)

Getter d'effectivité dans `LeaseExtension` (`lease.dart`). C'est la **source de vérité unique** du mode réel d'un bail, y compris pré-042 :

```dart
/// Mode de charges effectif. Les baux créés avant FEAT-042 n'ont pas de
/// `chargeMode` persisté (null) → on le dérive du type : mobilité = forfait
/// (obligatoire loi ELAN art. 25-18), tout le reste = provisions (défaut sûr,
/// car nu = provisions forcé et meublé pré-042 était traité comme provisions).
ChargeMode get effectiveChargeMode =>
    chargeMode ?? (leaseType == LeaseType.mobility
        ? ChargeMode.forfait
        : ChargeMode.provisions);

/// Prédicat unique d'éligibilité régularisation — SOURCE DE VÉRITÉ.
bool get canRegularizeCharges => effectiveChargeMode == ChargeMode.provisions;
```

> Note coverage : `LeaseType` a **4 valeurs** (`unfurnished, furnished, mobility, student`), pas 3. La dérivation ci-dessus est correcte pour les 4 (seule `mobility` → forfait).

### `LeaseListItem`

Aucun champ à ajouter : `LeaseListItem` embarque le `Lease` complet (`item.lease.canRegularizeCharges` marche directement). Les gates cards/table lisent déjà `lease.leaseType` via ce même `Lease`.

## Backend (Cloud Functions) — `functions/src/callable/lease_payment.ts`

### Constante + helper de cohérence (nouveau, en tête du fichier)

```ts
const CHARGE_MODES = new Set(["provisions", "forfait"]);

/**
 * Impose la cohérence type↔mode et renvoie le mode canonique à persister.
 * - unfurnished → provisions (forcé, art. 23 loi 1989)
 * - mobility    → forfait   (forcé, loi ELAN art. 25-18)
 * - furnished / student → libre ; défaut provisions
 * Rejette un mode explicitement invalide pour un type forcé.
 */
function resolveChargeMode(leaseType: string, requested: unknown): string {
  if (leaseType === "unfurnished") {
    if (requested != null && requested !== "provisions") {
      throw new HttpsError("invalid-argument",
        "unfurnished lease must use provisions charge mode");
    }
    return "provisions";
  }
  if (leaseType === "mobility") {
    if (requested != null && requested !== "forfait") {
      throw new HttpsError("invalid-argument",
        "mobility lease must use forfait charge mode");
    }
    return "forfait";
  }
  // furnished | student : libre, défaut provisions
  if (requested == null) return "provisions";
  if (typeof requested !== "string" || !CHARGE_MODES.has(requested)) {
    throw new HttpsError("invalid-argument", `invalid chargeMode: ${requested}`);
  }
  return requested;
}
```

### `createLease`
- Lire `data.chargeMode` (optionnel), appeler `const chargeMode = resolveChargeMode(leaseType, data.chargeMode);`.
- Ajouter `chargeMode` au `tx.set(leaseRef, { ... })`.

### `updateLease`
- Ajouter `"chargeMode"` à `LEASE_MUTABLE_FIELDS`.
- Le type de bail (`leaseType`) est mutable → recalculer la cohérence sur l'**état final** dans la transaction (après `tx.get`) : `const finalType = (cleanPatch.leaseType as string) ?? lease.leaseType;` puis `cleanPatch.chargeMode = resolveChargeMode(finalType, cleanPatch.chargeMode ?? lease.chargeMode);`. Cela **coerce** aussi les baux existants qui basculent vers un type forcé (ex. meublé forfait → mobilité reste forfait ; meublé forfait → nu devient provisions).
- Décision (voir § Décisions) : la coercion doit-elle être silencieuse ou lever une erreur si `chargeMode` explicite entre en conflit avec le nouveau `leaseType` ? Recommandation : lever une erreur uniquement si le client envoie **explicitement** un mode incompatible ; sinon coercer.

## Éligibilité régularisation — RECENSEMENT EXHAUSTIF des points à modifier

Le prédicat `leaseType == LeaseType.unfurnished` doit être remplacé par `lease.canRegularizeCharges` (extension unique). **4 points de gate + 1 doc** :

1. **`lib/features/leases/presentation/widgets/lease_card.dart`** (~L65) — menu overflow « Régulariser les charges » : `if (lease.leaseType == LeaseType.unfurnished)` → `if (lease.canRegularizeCharges)`. Mettre à jour le commentaire (L59-64).
2. **`lib/features/leases/presentation/widgets/leases_table_view.dart`** (~L188) — même menu côté tableau : idem. MAJ commentaire (L183-187).
3. **`lib/features/leases/presentation/lease_detail_page.dart`** (~L163) — auto-ouverture du dialog via `?action=regularize` : `lease.leaseType == LeaseType.unfurnished` → `lease.canRegularizeCharges`. MAJ commentaire (L153-160).
4. **`lib/features/charge_regularization/presentation/widgets/charge_regularization_section.dart`** (~L45) — `final isUnfurnished = lease.leaseType == LeaseType.unfurnished;` → `final canRegularize = lease.canRegularizeCharges;` ; renommer la variable et adapter le texte « pas applicable » (voir ci-dessous). MAJ docstring de classe (L7-18).

**Import** : ces 4 fichiers importent aujourd'hui `lease_type.dart` pour la comparaison ; après refactor, seul l'accès à l'extension via `lease.dart` (déjà importé) est requis. Retirer les imports `lease_type.dart` devenus inutiles pour éviter un warning `flutter analyze` (à confirmer fichier par fichier — `lease_detail_page.dart` et le form en ont d'autres usages).

Texte « non applicable » de la section (L66-73) — le durcir pour refléter le vrai motif (forfait, pas type de bail) :
> « Ce bail est au forfait de charges : le forfait est libératoire et ne donne pas lieu à régularisation (loi du 6 juillet 1989, art. 23 a contrario). »

5. **Docstring uniquement** (pas de logique) : `charge_regularization_dialog.dart` L18 mentionne « baux nus (`leaseType == unfurnished`) » → reformuler « baux en mode provisions (`canRegularizeCharges`) ».

> Il n'existe **aucun** autre helper `canRegularize` préexistant (grep confirmé) : ce plan en crée le premier et unique. Aucun autre point de gate n'utilise `unfurnished` dans un contexte de régularisation.

## Interaction FEAT-036 (chargesAmountCents récupérable + nonRecoverableChargesCents)

FEAT-036 ventile les charges en **récupérable** (`chargesAmountCents`) vs **non récupérable** (`nonRecoverableChargesCents`). Cette ventilation n'a de sens qu'en **mode provisions** : la part récupérable est ce qui sera régularisé, la non-récupérable reste informative bailleur.

En **mode forfait**, juridiquement le forfait est un **montant unique libératoire** : pas de ventilation récup/non-récup, pas de régularisation. Recommandation retenue (à valider § Décisions) :

- **Réutiliser `chargesAmountCents`** comme montant du forfait (pas de nouveau champ). Sémantique : « en provisions = provision mensuelle récupérable ; en forfait = montant du forfait mensuel ». Le calcul du loyer TTC (`totalAmountCents = rent + chargesAmountCents`) reste correct dans les deux modes (le forfait est bien facturé au locataire).
- En forfait, **masquer/neutraliser** `nonRecoverableChargesCents` dans le formulaire (le forcer à 0 côté serveur ou le laisser mais le cacher). Recommandation : le **masquer dans l'UI** et le **forcer à 0 côté CF** quand `chargeMode == forfait`, pour éviter des données incohérentes (un « forfait » ne se décompose pas). À trancher.
- Adapter le **libellé** du champ charges selon le mode (voir UX).

Aucun impact sur la quittance : `chargesAmountCents` reste le montant de charges facturé, quel que soit le mode.

## UX formulaire de bail

Fichiers : `lib/features/leases/presentation/widgets/lease_form.dart` (widget + état), `lease_form_page.dart` (câblage submit), `lease_form_controller.dart` (param `chargeMode`), `lease_repository.dart` (payload `chargeMode`).

### Sélecteur de mode (nouveau, section « Loyer et charges » ou « Type de bail »)

Ajouter un état `ChargeMode? _chargeMode;` dans `_LeaseFormState`, initialisé depuis `widget.initialChargeMode` (nouveau) ou dérivé. Comportement piloté par `_leaseType` :

- **Nu (`unfurnished`)** : mode = provisions, **verrouillé** (segment désactivé ou simple note) + note « Bail vide : provisions + régularisation annuelle obligatoire (art. 23) ».
- **Meublé / Étudiant (`furnished` / `student`)** : `SegmentedButton<ChargeMode>` **Provisions | Forfait**, défaut Provisions. Note « Meublé : provisions (régularisables) ou forfait (libératoire, art. 25-10). »
- **Mobilité (`mobility`)** : mode = forfait, **verrouillé** + note « Bail mobilité : forfait obligatoire, non régularisable (loi ELAN art. 25-18). »

Sur `onChanged` du type de bail (`_buildLeaseTypeField`, L548-562), **recalculer** `_chargeMode` pour respecter les contraintes (nu→provisions, mobilité→forfait, sinon conserver le choix ou repasser au défaut). Exposer `ChargeMode? get currentChargeMode`.

### Adaptation du libellé du champ charges (`_buildChargesField`, L436-461)

Le label/helper devient dynamique selon `_chargeMode` effectif :
- **Provisions** : « Provisions pour charges récupérables (€) * » + helper actuel (décret 87-713).
- **Forfait** : « Forfait de charges (€) * » + helper « Forfait mensuel libératoire — non régularisable. »

### Champ non-récupérable (`_buildNonRecoverableChargesField`, L463-488)

- **Provisions** : inchangé (visible).
- **Forfait** : **masquer** (le forfait ne se ventile pas). Penser à ne pas valider/soumettre ce champ quand masqué (le remettre à 0). À trancher (§ Décisions).

### Threading du champ (call sites à toucher)

- `lease_form_page.dart` : passer `formState.currentChargeMode` dans les deux appels `_doSubmit` (L191-208 et L212-229) et dans la signature `_doSubmit` (L233-249).
- `lease_form_controller.dart::submit` : nouveau param `ChargeMode? chargeMode`, propagé à `repo.create(...)` (L63-80) et au `copyWith` d'édition (L84-101).
- `lease_repository.dart::create` (L214-258) : nouveau param `ChargeMode? chargeMode`, ajouté au payload callable (`'chargeMode': chargeMode?.sqlValue` — omis si null pour laisser le serveur dériver le défaut). `update` (L260+) : ajouter `'chargeMode': lease.chargeMode?.sqlValue` au patch.
- `lease_form.dart` : nouveau param constructeur `ChargeMode? initialChargeMode` (rempli depuis `widget.initial?.chargeMode` dans `lease_form_page.dart` ~L378 à côté de `initialLeaseType`).

## Testing strategy

### Cloud Functions (`functions/src/__tests__/lease_payment.test.ts`)
- `resolveChargeMode` : unfurnished→provisions (et rejet si forfait demandé) ; mobility→forfait (et rejet si provisions) ; furnished/student→défaut provisions + acceptation forfait ; valeur inconnue rejetée.
- `createLease` : persiste `chargeMode` cohérent ; forfait demandé sur nu → `invalid-argument`.
- `updateLease` : bascule leaseType meublé(forfait)→mobilité coerce forfait ; →nu coerce provisions ; `chargeMode` explicite incompatible rejeté ; forfait ⇒ `nonRecoverableChargesCents` forcé 0 (si décision retenue).

### Dart unit
- `test/unit/charge_mode_test.dart` (nouveau) : `fromSqlOrNull` (valide/null/inconnu), `labelFr`.
- `test/unit/lease_test.dart` : `effectiveChargeMode` (null+mobility→forfait ; null+nu→provisions ; null+meublé→provisions ; valeur explicite prioritaire) ; `canRegularizeCharges` (provisions→true, forfait→false) pour les 4 types × modes.
- `test/unit/lease_serialization_test.dart` : round-trip JSON `charge_mode` (présent, null, inconnu tolérant).

### Widget
- `charge_regularization_section_test.dart` : bouton présent ssi `canRegularizeCharges` — couvrir nu(null), meublé(provisions), meublé(forfait), mobilité(null) → attendu bouton / message pour chaque.
- `leases_card_view_test.dart` + `leases_table_view_test.dart` : menu « Régulariser » présent/absent selon mode effectif (pas selon type).
- `lease_detail_page_test.dart` : `?action=regularize` n'auto-ouvre le dialog que si `canRegularizeCharges`.
- `lease_form_page_test.dart` : sélecteur verrouillé pour nu/mobilité, toggle pour meublé ; libellé charges provisions vs forfait ; non-récupérable masqué en forfait ; `chargeMode` transmis au submit.

### Manual QA
- Créer meublé forfait → pas de menu régulariser (carte, tableau, fiche) ; URL `?action=regularize` tapée à la main n'ouvre rien.
- Bail nu pré-042 (chargeMode null en base) → régularisation toujours disponible.
- Bail mobilité pré-042 → jamais de régularisation.
- Éditer un meublé provisions→forfait puis re-provisions : le menu apparaît/disparaît correctement.

## Risks

- **Régression de gate** : oublier un des 4 points → un bail forfait resterait régularisable ou un bail provisions perdrait l'accès. Mitigation : prédicat unique `canRegularizeCharges` + tests widget sur les 4 surfaces.
- **Baux pré-042 (chargeMode null)** : si la dérivation `effectiveChargeMode` est fausse, un bail meublé forfait *legacy* (créé avant 042, sans notion de mode) redeviendrait régularisable. Réalité : avant 042 aucun meublé n'était régularisable (gate `unfurnished`), et la dérivation par défaut donne `provisions` (donc régularisable) pour un meublé legacy. **Léger changement de comportement** : un meublé legacy devient régularisable par défaut. Acceptable juridiquement (meublé au provisions EST régularisable) mais à signaler au PO. Alternative rejetée : backfill script (contrainte utilisateur = migration lazy sans script).
- **Cohérence édition de type** : changer le type d'un bail existant peut invalider son mode. La coercion serveur dans `updateLease` couvre ça, mais attention à ne pas casser un `chargeMode` explicite légitime → d'où l'option « rejeter si conflit explicite, coercer sinon ».
- **FEAT-036 en forfait** : si on ne masque pas / ne force pas 0 le non-récupérable en forfait, on stocke une ventilation d'un montant non ventilable → données trompeuses. Décision à trancher.
- **Firestore camelCase vs snake_case Dart** : le champ est `chargeMode` en Firestore (camelCase natif) et `charge_mode` côté `@JsonKey` (le helper `firestoreDocToSnakeJson` fait la conversion, comme pour `nonRecoverableChargesCents`/`non_recoverable_charges_cents`). Vérifier que `charge_mode` ↔ `chargeMode` est bien géré par `snakeJsonToFirestoreDoc` / `firestoreDocToSnakeJson` (`lib/core/firestore_helpers.dart`).

## ❓ Décisions à trancher (product-owner / utilisateur)

1. **Charges en mode forfait vs FEAT-036** — recommandation : réutiliser `chargesAmountCents` comme montant du forfait (pas de champ dédié `forfaitAmountCents`). Alternative : champ distinct (plus explicite, mais duplique la logique loyer TTC et les 15 points de lecture existants). **→ Réutiliser `chargesAmountCents` ?**
2. **`nonRecoverableChargesCents` en forfait** — le masquer dans l'UI ET le forcer à 0 côté CF quand `chargeMode == forfait` ? (recommandé, évite données incohérentes) OU le laisser saisissable (informatif bailleur même en forfait) ?
3. **Libellés** — valider :
   - Enum : « Provisions + régularisation » / « Forfait ».
   - Champ charges provisions : « Provisions pour charges récupérables (€) ».
   - Champ charges forfait : « Forfait de charges (€) ».
   - Texte non-applicable : « Ce bail est au forfait de charges : le forfait est libératoire et ne donne pas lieu à régularisation. »
4. **Coercion vs rejet à l'update** quand le nouveau `leaseType` force un mode contraire à un `chargeMode` explicite envoyé : rejeter (erreur claire) ou coercer silencieusement ? Recommandation : rejeter si explicite + incompatible, coercer si le mode n'est pas fourni.
5. **Changement de comportement legacy** : accepter que les baux **meublés créés avant FEAT-042** deviennent régularisables par défaut (dérivés en provisions) ? (juridiquement correct pour un meublé au provisions).

## Step-by-step execution order

1. **CF** (`supabase-dev`/backend) : `resolveChargeMode` + `chargeMode` dans `createLease`/`updateLease` (`lease_payment.ts`) + tests vitest. Déployer functions.
2. **Domain Dart** (`flutter-dev`) : `charge_mode.dart` (enum) + champ `chargeMode` + getters `effectiveChargeMode`/`canRegularizeCharges` (`lease.dart`) ; `build_runner` (freezed/json).
3. **Gates** : remplacer les 4 points par `canRegularizeCharges` (lease_card, leases_table_view, lease_detail_page, charge_regularization_section) + docstring dialog.
4. **Formulaire** : sélecteur de mode + libellés dynamiques + masquage non-récup en forfait ; threading `chargeMode` (form → page → controller → repository).
5. **Tests** (`qa-tester`) : unit (charge_mode, lease, serialization) + widget (section, cards, table, detail, form) + CF vitest.
6. **Revue** : `code-reviewer` + `security-auditor` (cohérence serveur = seule barrière — vérifier qu'aucun chemin client ne peut persister un mode incohérent).
7. `dart format` + `flutter analyze` clean ; MAJ `docs/state/*` via `state-keeper`.
