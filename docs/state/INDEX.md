# Index d'état — routeur

> **Snapshot vivant EasyRent/Baillan.** Maintenu par `state-keeper`. Source de
> vérité pour les agents. **Ce fichier est un ROUTEUR léger** : lis-le en
> premier, puis charge UNIQUEMENT le(s) shard(s) du domaine concerné. Ne charge
> pas tout l'état — c'est le point de la diète tokens (2026-07-09).

## Métadonnées

- **Dernière mise à jour** : 2026-07-10
- **Commit ref** : `5a43e58` (develop, post PR #94 : verrouillage réactivation bail ; shards FEAT-044/PR #94 actualisés)
- **Phase** : MVP ✅ + Post-MVP M1 ✅ + Mobile/Stores ✅ (FEAT-024/043/045/048) + Freemium ✅ (FEAT-044) + Growth/SEO ✅ (FEAT-049 ; FEAT-050 planifié)

## Comment charger l'état (règle tokens)

1. Lis cet INDEX. Repère le domaine de ta tâche.
2. Charge **seulement** les shards utiles (schéma/functions/routes du domaine) — chacun ~0,2–1,5k tokens.
3. Besoin d'un panorama transverse ? Lis le `README.md` du dossier concerné (schema/functions/routes).
4. Statut d'une feature → [`FEATURES.md`](FEATURES.md) (matrice). Historique détaillé → [`CHANGELOG.md`](CHANGELOG.md) (rare).
5. Ne grep/scan le code QUE si l'état ne couvre pas ton besoin (cf. CLAUDE.md).

## Domaines (charge le shard = ton domaine)

| Domaine | Schéma | Functions | Routes |
|---|---|---|---|
| **account** (landlords, profil, auth, suppression, support, paid_plan_interest, i18n) | [schema/account](schema/account.md) | [functions/account](functions/account.md) | [routes/account](routes/account.md) |
| **properties** (properties + tenants) | [schema/properties](schema/properties.md) | [functions/properties](functions/properties.md) | [routes/properties](routes/properties.md) |
| **leases** (leases, chargeMode, régularisation) | [schema/leases](schema/leases.md) | [functions/leases](functions/leases.md) | [routes/leases](routes/leases.md) |
| **payments-receipts** | [schema/…](schema/payments-receipts.md) | [functions/…](functions/payments-receipts.md) | [routes/…](routes/payments-receipts.md) |
| **expenses-documents** | [schema/…](schema/expenses-documents.md) | [functions/…](functions/expenses-documents.md) | [routes/…](routes/expenses-documents.md) |
| **simulator** (investment_scenarios) | [schema/simulator](schema/simulator.md) | [functions/simulator](functions/simulator.md) | [routes/simulator](routes/simulator.md) |
| **dashboard** (accueil) | — | — | [routes/dashboard](routes/dashboard.md) |

Panoramas transverses : [`schema/README`](schema/README.md) (11 collections + patterns RLS/soft-delete/index) · [`functions/README`](functions/README.md) (callables + triggers + scheduled) · [`routes/README`](routes/README.md) (3-états + shell nav).

## Autres fichiers d'état (charge à la demande)

| Besoin | Fichier |
|---|---|
| Statut des features (matrice) | [`FEATURES.md`](FEATURES.md) |
| Historique détaillé des changements | [`CHANGELOG.md`](CHANGELOG.md) |
| Thème Baillan papier/encre/olive (FEAT-020) + dark mode + `themeMode` | [`THEME.md`](THEME.md) |
| Design tokens (couleurs, spacing) | [`DESIGN_TOKENS.md`](DESIGN_TOKENS.md) |
| Dépendances (pubspec + functions) | [`DEPENDENCIES.md`](DEPENDENCIES.md) |

## Stack (résumé)

- **Frontend** : Flutter 3.x + Dart 3.11+ (web + Android + iOS `com.daki.baillan`), CanvasKit, EB Garamond serif.
- **State/Nav** : Riverpod 2.6 (StreamProvider) · GoRouter 14.6 (garde 3-états via sessionStateProvider).
- **Auth** : Firebase Auth natif (email/password + Google + Apple + anonyme).
- **Backend** : Firestore (11 collections, camelCase, soft-delete + 28 index composites, rules 3 couches) + Cloud Functions Node 20 (callables + triggers + 1 scheduled).
- **Storage** : Firebase Storage (signed URLs 5 min). **PDF** : `pdf` + `share_plus` (quittance loi 6/07/1989). **Hosting** : Firebase (staging channel + prod), CSP fonts.gstatic.com. **CI** : GitHub Actions (format + analyze + tests, Flutter pin 3.41.2).

## Quand mettre à jour cet état

- Après une feature mergée / migration → `state-keeper` met à jour le(s) shard(s) touché(s) + la ligne FEATURES + une entrée CHANGELOG.
- Avant un sprint → `/refresh-state`.
- Incohérence détectée → flag immédiat à l'utilisateur.
