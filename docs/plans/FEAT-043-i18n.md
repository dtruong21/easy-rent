# Plan — [FEAT-043] Internationalisation (support Anglais)

> Branche : `feature/043-i18n` — Auteur du plan : Software Architect — 2026-07-06
> ⚠️ **Ce document est un plan. Aucun code produit ici.**

## Summary

Ajout du support **Anglais** à Baillan (aujourd'hui 100 % FR, chaînes en dur).
Approche recommandée : **`flutter_localizations` + `gen_l10n` (ARB + `AppLocalizations`)** —
officielle, cohérente avec `intl` déjà présent, `generate: true` déjà activé dans
`pubspec.yaml`. Résolution : **défaut = locale système**, fallback FR, **override manuel
recommandé** (sélecteur dans Profil, persisté SharedPreferences comme `themeModeProvider`).
**Décision légale critique** : UI traduite, **documents légaux FR conservés en français**
(quittance loi 6/7/1989, avis de régularisation, CGU, politique de confidentialité) —
seul l'affichage informatif peut être traduit. Effort total estimé : **12–18 j·dev**
(foundation ~2 j, puis extraction ~700–800 chaînes par module, parallélisable).

---

## 1. Scan de la surface (ampleur mesurée)

Mesures effectuées sur `lib/**` (354 fichiers Dart, commit `6367a8c`).

### Chiffres bruts

| Métrique | Valeur |
|---|---|
| Littéraux avec caractères FR (accents) — brut | **1 146** |
| dont sur lignes de **commentaire** (`//`, `///`) → hors périmètre | ~3 295 lignes (bruit, à ignorer) |
| dont sur lignes de **log** (`_log`, `Logger`, `debugPrint`) → hors périmètre | ~26 |
| Littéraux FR **hors commentaires/logs** (proxy chaînes UI) | **~931** |
| `Text('…')` / `Text("…")` littéraux | **232** |
| `labelText`/`hintText`/`helperText`/`tooltip`/`semanticLabel` littéraux | ~36 |
| `SnackBar` (usages) | 133 |
| Fichiers contenant ≥ 1 chaîne FR | **193 / 354** |

**Cible réelle des clés ARB à créer** : après retrait des pages légales (`privacy` ~155,
non traduites — cf. §6) et des chaînes déjà couvertes par `intl` (montants/dates),
on estime **~700–800 chaînes UI traduisibles**.

### Distribution par module (fichiers / occurrences FR hors commentaires)

| Module | Fichiers | Occ. | Priorité V1 | Note |
|---|---|---|---|---|
| `auth` | 26 | 139 | **P0** | Login, signup, RGPD gate, quit-demo, erreurs |
| `leases` | 18 | 112 | **P0** | Formulaires + fiche + status pills |
| `receipts` | 23 | 102 | P1 | UI receipts (⚠️ PDF quittance = FR, cf. §6) |
| `expenses` | 16 | 99 | P1 | Formulaires + natures/catégories enums |
| `simulator` | 10 | 81 | P1 | Accessible anonymes |
| `properties` | 12 | 74 | **P0** | CRUD + cartes + tableau |
| `tenants` | 9 | 56 | **P0** | CRUD |
| `charge_regularization` | 9 | 52 | P2 | UI régul. (⚠️ avis PDF = FR, cf. §6) |
| `dashboard` | 14 | 49 | **P0** | KPI, chart labels, activité |
| `documents` | 13 | 47 | P1 | Catégories, dialogs |
| `payments` | 8 | 46 | P1 | Formulaire, motif |
| `profile` | 6 | 18 | **P0** | Réglages (dont futur sélecteur langue) |
| `landing` | 2 | 10 | P1 | Page publique |
| `support` | 3 | 7 | P2 | Formulaire contact |
| `pwa` | 3 | 7 | P2 | Install prompt |
| `paid_plan` | 1 | 1 | P2 | — |
| `privacy` | 2 | 155 | **EXCLU** | CGU + politique → **restent FR** (§6) |
| `core` (hors features) | 17 | 90 | **P0 (foundation)** | Enums partagés, validators, formatters |

### Patterns actuels observés

- **UI** : `Text('…')`, `labelText:`, `hintText:`, `helperText:`, `tooltip:`,
  `AppBar(title: Text('…'))`, `SnackBar(content: Text('…'))`, `AlertDialog(title/content)`,
  boutons `TextButton/FilledButton(child: Text('…'))`.
- **Enums métier localisés en dur** : statuts de baux, `LeaseFilter` labels, natures de
  dépenses (`ExpenseNature`), catégories de documents, modes de charges — actuellement
  mappés vers des libellés FR en dur (souvent des `switch` ou des `extension` avec `label`).
  → **À router via ARB** (pas de libellé FR dans le domaine).
- **Validators** (`lib/core/utils/*_validators.dart`) : messages d'erreur FR en dur
  (`'Champ requis'`, `'Email invalide'`, etc.) → **à externaliser** (retournent une clé /
  un enum, la présentation traduit — voir §3 Risques).

### Usage `intl` existant (formatage — déjà en place)

- `lib/core/utils/money_format.dart` : `NumberFormat.currency(locale: 'fr_FR', symbol: '€')`
  — **hardcodé `fr_FR`**.
- `lib/core/utils/byte_format.dart` : `NumberFormat('#,##0.#', 'fr_FR')` — hardcodé.
- `lib/core/utils/french_date.dart` : formatage `dd/MM/yyyy` + noms de mois FR **manuels**
  (tableau `_monthNames`) — n'utilise PAS `DateFormat` localisé.
- Sélecteurs de date natifs : `showDatePicker(locale: const Locale('fr','FR'))` en dur dans
  `tenant_form.dart:341`, `property_form.dart:799,1055`.

**Aucun** `flutter_localizations`, `AppLocalizations`, ARB, `localizationsDelegates`,
`supportedLocales` ou `localeResolutionCallback` présent aujourd'hui. `generate: true`
est déjà dans `pubspec.yaml:89` (prêt pour `gen_l10n`).

### Setup MaterialApp (point de wiring)

`lib/main.dart` — `BaillanApp` (`ConsumerStatefulWidget`) → `MaterialApp.router` (lignes 65–73) :
```dart
return MaterialApp.router(
  title: 'Baillan.',
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: themeMode,          // ← modèle exact pour `locale:`
  routerConfig: router,
  debugShowCheckedModeBanner: false,
);
```
C'est **le seul** `MaterialApp` de l'app. Wiring i18n à ajouter ici.

---

## 2. Approche / package recommandé

### ✅ Recommandation : `flutter_localizations` + `gen_l10n` (ARB + `AppLocalizations`)

**Justifications** :
1. **Officiel Flutter**, zéro dépendance tierce, maintenu par l'équipe Flutter.
2. **Cohérent avec `intl` déjà présent** (gen_l10n génère du code basé sur `intl`,
   supporte ICU plurals/selects/placeholders nativement).
3. `generate: true` **déjà activé** → seul l'ajout d'`l10n.yaml` + des ARB manque.
4. **Vérification de complétude à la compilation** : `gen_l10n` warn/erreur sur clé manquante
   entre `app_fr.arb` et `app_en.arb` (avec `untranslated-messages-file`).
5. **`GlobalMaterialLocalizations`** localise gratuitement widgets natifs
   (`showDatePicker`, `MaterialLocalizations`, tri, etc.).

### Alternatives rejetées

| Package | Pourquoi rejeté |
|---|---|
| `slang` | Type-safe et ergonomique, mais dépendance tierce + codegen concurrent de build_runner ; pas de gain décisif vs officiel ; l'équipe connaît déjà `intl`. |
| `easy_localization` | Runtime-based (clés string non vérifiées à la compilation), moins sûr, patterns hors-`MaterialApp` parfois fragiles sur Web. |

### Structure ARB

- **Un couple global** : `lib/l10n/app_fr.arb` (template) + `lib/l10n/app_en.arb`.
  - Rejet du multi-ARB par feature : `gen_l10n` produit **une** classe `AppLocalizations` ;
    un fichier par feature complexifierait sans bénéfice. Namespacing par **préfixe de clé**.
- **Convention de clés** : `camelCase` préfixé par module → `authLoginTitle`,
  `leasesFormRentLabel`, `commonSave`, `commonCancel`, `expensesNatureWorks`.
  - `common*` pour les chaînes transverses (Enregistrer, Annuler, Supprimer, Confirmer…).
- **Placeholders / ICU** : utiliser les placeholders typés (`{count}`, `{name}`, `{date}`)
  et les **plurals ICU** (`{count, plural, =0{…} =1{…} other{…}}`) pour les compteurs
  (« 1 bail », « 3 baux »). Formatage de dates/nombres via placeholders `type: DateTime`/
  `type: int` avec `format:` (délègue à `intl`, respecte la locale).
- `@key` metadata : `description` obligatoire (contexte pour la traduction).

---

## 3. Résolution de locale

- `supportedLocales: const [Locale('fr'), Locale('en')]`.
- `localizationsDelegates`:
  - `AppLocalizations.delegate`
  - `GlobalMaterialLocalizations.delegate`
  - `GlobalWidgetsLocalizations.delegate`
  - `GlobalCupertinoLocalizations.delegate`
- **Défaut = locale système**, fallback FR (marché principal) via `localeResolutionCallback` :
  ```
  localeResolutionCallback: (deviceLocale, supported) {
    if (deviceLocale == null) return const Locale('fr');
    for (final l in supported) {
      if (l.languageCode == deviceLocale.languageCode) return l;
    }
    return const Locale('fr'); // fallback marché principal
  }
  ```
  (Le comportement par défaut de Flutter fallback déjà sur `supportedLocales.first` = `fr`
  si on place `fr` en tête ; le callback explicite documente l'intention et gère les
  `en-GB`/`en-US` → `en`.)
- **Override manuel** (cf. §4) : si présent, on passe `locale:` (non-null) au `MaterialApp`,
  ce qui **court-circuite** la résolution système. Si `null` → résolution système.

### Formatage `intl` à rendre locale-aware (foundation)

- `MoneyFormat.formatEurosFromCents` : remplacer `'fr_FR'` en dur par la locale active.
  ⚠️ **Décision** : la devise reste **€** (bien immobilier français). On ne convertit pas
  la monnaie ; on adapte seulement le **séparateur** (fr : `1 234,56 €` / en : `€1,234.56`
  ou `1,234.56 €`). Recommandation : garder le symbole € en **suffixe** et n'adapter que
  les séparateurs, pour rester cohérent avec le contexte FR même en EN.
- `byte_format.dart` : idem, locale active.
- `french_date.dart` : introduire une variante `DateFormat.yMd(locale)` / mois localisés
  via `intl` pour l'UI **informative**. ⚠️ Conserver le format FR figé pour les **noms de
  fichiers/sujets d'email de quittances** (usage légal/déterministe) — cf. §6.
- `initializeDateFormatting()` : appeler pour `fr` + `en` au boot (`main.dart`) avant
  `runApp` (nécessaire pour `DateFormat` non-défaut). Alternative : recours aux placeholders
  ARB `type: DateTime` qui gèrent l'init.
- `showDatePicker(locale:)` : passer la locale active au lieu de `const Locale('fr','FR')`.

---

## 4. Override manuel (décision recommandée)

### ✅ Recommandation : **OUI, sélecteur de langue dans Profil**, persisté SharedPreferences.

**Justification** :
- Coût **très faible** : le pattern existe déjà à l'identique (`themeModeProvider` +
  `ThemeModeStorage`, FEAT-023). On duplique en `localeProvider` + `LocaleStorage`.
- **Valeur réelle** : un bailleur FR sur un OS/navigateur configuré en anglais (courant sur
  du matériel pro) veut pouvoir forcer le FR — et inversement pour un utilisateur anglophone
  sur navigateur FR. La résolution système seule ne couvre pas ces cas.
- **UX** : cohérent avec le hub réglages Profil (Apparence → Thème ; on ajoute Langue).

**Modèle** (copie exacte de FEAT-023) :
- `localeProvider` : `StateNotifierProvider<LocaleNotifier, Locale?>`, défaut `null`
  (= suit le système). Non-autoDispose (vivant toute la session), watché par `MaterialApp`.
- `LocaleStorage` : clé `app_locale` (`'fr'` / `'en'` / absent = système).
- Valeurs du sélecteur : **Système / Français / English** (3 options, comme le thème).

---

## 5. Wiring (fichiers exacts)

### `lib/main.dart` — `MaterialApp.router`
Ajouter :
```
final locale = ref.watch(localeProvider);   // Locale? (null = système)
...
MaterialApp.router(
  ...
  locale: locale,                             // null → résolution système
  supportedLocales: const [Locale('fr'), Locale('en')],
  localizationsDelegates: AppLocalizations.localizationsDelegates
      + [ ...Global*Localizations.delegate ],
  localeResolutionCallback: (device, supported) { ... }, // cf. §3
  onGenerateTitle: (ctx) => AppLocalizations.of(ctx)!.appTitle, // titre localisé
)
```
Ajouter aussi `initializeDateFormatting()` dans `main()` avant `runApp` (si `DateFormat`
non-placeholder utilisé).

---

## Data model changes

**N/A.** Aucune migration Firestore, aucune règle, aucun index. La préférence de langue
est **locale au navigateur** (SharedPreferences), non synchronisée entre appareils — même
choix que thème/vue/rail. (Option future P2 : `landlords.preferredLocale` pour sync
multi-device — hors périmètre V1, ne pas implémenter.)

## Backend (Cloud Functions)

**N/A pour la V1 UI.** Point d'attention documenté (pas d'action V1) :
- `generateReceipt`, avis de régularisation : **restent 100 % FR** (documents légaux, §6).
- Emails transactionnels (FEAT-031 planifié, non déployé) : si un jour envoyés, prévoir
  la locale dans le futur. **Hors périmètre FEAT-043.**

---

## Flutter changes

### New files (foundation)
- `lib/l10n/app_fr.arb` — template FR (source de vérité, toutes les clés).
- `lib/l10n/app_en.arb` — traductions EN.
- `l10n.yaml` (racine projet) — config `gen_l10n` :
  ```
  arb-dir: lib/l10n
  template-arb-file: app_fr.arb
  output-localization-file: app_localizations.dart
  output-class: AppLocalizations
  nullable-getter: false
  untranslated-messages-file: l10n_untranslated.json
  ```
- `lib/core/i18n/locale_provider.dart` — `localeProvider` + `LocaleNotifier` (calque FEAT-023).
- `lib/core/i18n/locale_storage.dart` — `LocaleStorage` (clé `app_locale`).
- `lib/core/i18n/l10n_extensions.dart` (optionnel) — helper `context.l10n` (raccourci
  `AppLocalizations.of(context)!`).

### Modified files (foundation)
- `pubspec.yaml` — ajouter `flutter_localizations: { sdk: flutter }` (dev deps `intl` déjà là).
- `lib/main.dart` — wiring délégués + `locale` + `supportedLocales` + resolution callback
  + `onGenerateTitle` + `initializeDateFormatting`.
- `lib/core/utils/money_format.dart` — locale active (garder € suffixe, adapter séparateurs).
- `lib/core/utils/byte_format.dart` — locale active.
- `lib/core/utils/french_date.dart` — variante localisée pour l'UI (conserver la variante
  FR figée pour noms de fichiers/emails de quittance).
- `lib/core/utils/*_validators.dart` (7 fichiers) — externaliser les messages : renvoyer un
  enum/clé de validation, la couche présentation traduit via `AppLocalizations`.
  ⚠️ **Décision architecturale** : les validators sont des fonctions pures testées sans
  `BuildContext` ; ils **ne doivent pas** dépendre d'`AppLocalizations`. Pattern retenu :
  validator retourne `ValidationError?` (enum), le widget mappe enum → chaîne traduite.
- Date pickers : `tenant_form.dart`, `property_form.dart` (×2) — locale active.
- **Enums métier** : retirer les `label` FR en dur des domaines (`ExpenseNature`,
  statuts baux, `LeaseFilter`, catégories documents, `chargeMode`) → mapper enum → clé ARB
  dans la couche présentation.

### Modified files (extraction par module — P0→P2, ~193 fichiers)
Remplacement de chaque littéral UI par `AppLocalizations.of(context)!.<clé>` (ou
`context.l10n.<clé>`), module par module (cf. §7 phasage).

### Providers
- `localeProvider` (nouveau) — `StateNotifierProvider<LocaleNotifier, Locale?>`.
- `localeStorageProvider` (nouveau) — `Provider<LocaleStorage>`.

### Routes
**Aucune nouvelle route.** Le sélecteur de langue s'intègre dans `ProfilePage`
(`/profile`) — section « Apparence & langue » aux côtés du sélecteur de thème
(`profile_settings_sections.dart`).

---

## 6. Formatage & LÉGAL (décision critique) — À FAIRE VALIDER PRODUCT-OWNER

### ✅ Recommandation : **UI traduite (FR/EN) — Documents légaux FR conservés en français.**

| Élément | Traduit EN ? | Justification |
|---|---|---|
| **Quittance PDF** (`receipt_pdf_renderer.dart`, loi 6/7/1989 art. 21) | ❌ **NON — reste FR** | Document à valeur légale FR. Les mentions obligatoires (« quittance et solde de tout compte pour la période susvisée », « Loi du 6 juillet 1989 ») ont une portée juridique en français. |
| **Avis de régularisation** (`charge_regularization_pdf_renderer.dart`) | ❌ **NON — reste FR** | Document opposable au locataire (décret 87-713). |
| **CGU** (`terms_page.dart`) | ❌ **NON — reste FR (V1)** | Contrat. Une traduction EN engagerait juridiquement Baillan. FR fait foi. Option P2 : version EN **informative** avec disclaimer « la version française fait foi ». |
| **Politique de confidentialité** (`privacy_page.dart`) | ❌ **NON — reste FR (V1)** | RGPD — idem. |
| **Noms de fichiers / sujets d'email de quittance** (`french_date.dart` `frenchMonthYear`) | ❌ **NON — reste FR** | Cohérence avec le document légal FR + déterminisme. |
| **Chrome/UI autour du PDF** (boutons « Générer », « Partager », titres de page, SnackBars) | ✅ **OUI** | Ce n'est pas le document légal, juste l'interface. |
| **Montants / dates dans l'UI** | ✅ **format localisé** (devise € conservée) | `intl` locale-aware. |

**Conséquence de périmètre** : le module `privacy` (155 occ.) est **hors périmètre**.
Les PDF renderers ne sont **pas** touchés dans leur contenu (seule leur invocation UI l'est).

**À surfacer au product-owner** : confirmer que garder CGU/politique en FR-only est
acceptable pour un lancement EN (recommandé), ou s'il faut une version EN informative
disclaimée (P2, effort additionnel ~1 j + relecture juriste).

---

## 7. Phasage

### Phase 0 — Foundation (bloquante, séquentielle) — ~2 j
1. `pubspec.yaml` + `l10n.yaml` + `lib/l10n/app_{fr,en}.arb` (squelette + `common*`).
2. `localeProvider` + `LocaleStorage` (calque FEAT-023).
3. Wiring `main.dart` (délégués, résolution système, override, `onGenerateTitle`).
4. Rendre `MoneyFormat`/`byteFormat`/dates locale-aware + date pickers.
5. Externaliser les messages des validators (enum → présentation).
6. Sélecteur de langue dans Profil (Système / Français / English).
7. **1er module pilote = `profile` + `core`** (le plus petit chemin qui valide la chaîne
   complète bout-en-bout, y compris le sélecteur lui-même).

### Phase 1 — Modules P0 (parcours critique) — parallélisable — ~4–6 j
`auth`, `properties`, `tenants`, `leases`, `dashboard`.
(Inclut la localisation des **enums métier** : statuts baux, `LeaseFilter`.)

### Phase 2 — Modules P1 — parallélisable — ~4–5 j
`receipts` (UI only, PDF FR intact), `expenses` (+ `ExpenseNature`), `payments`,
`documents` (+ catégories), `simulator`, `landing`.

### Phase 3 — Modules P2 + finition — ~2 j
`charge_regularization` (UI only), `support`, `pwa`, `paid_plan`.
Revue de complétude ARB, `l10n_untranslated.json` vide, QA multi-locale.

**Parallélisation** : après la Phase 0, chaque module est indépendant (un dev/agent par
module). Contrainte : sérialiser les écritures dans `app_fr.arb`/`app_en.arb` OU découper
le travail par préfixe de clé pour éviter les conflits de merge (recommandé : chaque module
ajoute ses clés dans une section délimitée par des commentaires ARB).

---

## 8. Tests

- **Résolution de locale** (unit, `localeResolutionCallback`) :
  - device `en-US` → `en`, device `en-GB` → `en`, device `de-DE` → `fr` (fallback),
    device `null` → `fr`.
- **Override** : `localeProvider = en` court-circuite un device `fr` ; `null` → système.
- **Persistence** : `LocaleStorage` read/write round-trip (comme `theme_mode_storage_test`).
- **Complétude ARB** (test automatisé) : parser `app_fr.arb` et `app_en.arb`, asserter
  **égalité des ensembles de clés** (aucune clé manquante/orpheline). Alternativement,
  vérifier en CI que `l10n_untranslated.json` est vide.
- **Widget tests par locale** : quelques écrans clés (`LoginPage`, `DashboardPage`,
  `LeaseFormPage`) pompés sous `Locale('fr')` puis `Locale('en')` → asserter la présence
  des chaînes traduites (via `find.text`) et l'absence de `AppLocalizations` null.
- **Formatage** : `MoneyFormat` fr → `1 234,56 €`, en → séparateurs EN, devise € conservée.
- **Non-régression légale** : test asserant que `receipt_pdf_renderer` produit toujours les
  mentions FR **quelle que soit** la locale UI (verrou anti-régression).
- **CI** : `flutter analyze` clean, `dart format` (⚠️ inclure les fichiers ARB/générés —
  le code `app_localizations.dart` est généré, exclu du format mais présent au build).

---

## Risks

- **R1 — Ampleur (~700–800 chaînes / 193 fichiers)** : gros volume mécanique.
  *Mitigation* : phasage par module parallélisable, foundation d'abord, `common*` mutualisés.
- **R2 — Validators purs vs contexte** : les validators sont testés sans `BuildContext` ;
  les coupler à `AppLocalizations` casserait les tests unitaires.
  *Mitigation* : validators renvoient un enum d'erreur, la présentation traduit. Refactor
  ciblé en Phase 0.
- **R3 — Enums métier avec `label` FR en dur** dans le domaine : viole la séparation
  domaine/présentation une fois i18n.
  *Mitigation* : déplacer le mapping enum→libellé vers la couche présentation (clé ARB).
- **R4 — Confusion légale** : risque de traduire par erreur un document opposable.
  *Mitigation* : décision §6 explicite + test de non-régression R (PDF toujours FR).
- **R5 — Conflits de merge sur les ARB** en travail parallèle.
  *Mitigation* : sections délimitées par module, ou merges sérialisés du template.
- **R6 — Devise/format** : convertir € en $ serait une faute métier (biens FR).
  *Mitigation* : devise € **figée**, seuls les séparateurs suivent la locale.
- **R7 — `initializeDateFormatting`** oublié → `DateFormat` non-défaut plante à froid.
  *Mitigation* : init au boot OU privilégier les placeholders ARB `type: DateTime`.
- **R8 — CSP fonts** : EN n'introduit pas de glyphes hors latin → aucun impact CSP/fonts
  (EB Garamond subset latin OK). Pas d'action.

---

## ❓ Décisions à trancher (product-owner)

1. **Package** — Recommandé : **`flutter_localizations` + `gen_l10n` (ARB)**. ✅ à confirmer.
2. **Override manuel vs système-only** — Recommandé : **override manuel** (sélecteur Profil,
   persisté, défaut = système). Coût faible, pattern FEAT-023 déjà en place. ✅ à confirmer.
3. **Documents légaux FR** — Recommandé : **UI traduite, CGU / politique / quittance / avis
   restent FR** (V1). Option P2 : CGU/politique EN **informative** disclaimée (effort +1 j
   + relecture juriste). ✅ à confirmer.
4. **Périmètre V1** — Recommandé : **toute l'app** (foundation + P0 + P1 + P2), `privacy`
   exclu. Alternative « minimale » : foundation + P0 seulement (parcours critique bilingue,
   reste FR temporairement). ✅ à confirmer (impacte l'effort : 6 j vs 12–18 j).
5. **Persistence de la langue** — Recommandé : **locale (SharedPreferences)**, pas de sync
   Firestore V1. Option P2 : `landlords.preferredLocale`. ✅ à confirmer.

---

## Step-by-step execution order

1. **Foundation** (`flutter-dev`) : pubspec + `l10n.yaml` + ARB squelette + `localeProvider`
   + wiring `main.dart` + formatters locale-aware + validators enum + sélecteur Profil +
   module pilote `profile`/`core`.
2. **Extraction P0** (`flutter-dev`, parallèle) : auth, properties, tenants, leases, dashboard
   (+ enums métier).
3. **Extraction P1** (`flutter-dev`, parallèle) : receipts (UI), expenses, payments, documents,
   simulator, landing.
4. **Extraction P2** (`flutter-dev`) : charge_regularization (UI), support, pwa, paid_plan.
5. **Tests** (`qa-tester`) : résolution locale, complétude ARB, widget tests bilingues,
   non-régression PDF légal FR.
6. **Revue** (`code-reviewer` + `security-auditor` — surface sécurité faible : pas de RLS/
   backend touché ; vérifier surtout la non-régression légale et l'absence de fuite de
   chaîne non traduite).
7. **Deploy** staging → validation → prod (avec confirmation utilisateur).
