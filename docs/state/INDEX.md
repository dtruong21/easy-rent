# Index d'état — routeur

> **Snapshot vivant EasyRent/Baillan.** Maintenu par `state-keeper`. Source de
> vérité pour les agents. **Ce fichier est un ROUTEUR léger** : lis-le en
> premier, puis charge UNIQUEMENT le(s) shard(s) du domaine concerné. Ne charge
> pas tout l'état — c'est le point de la diète tokens (2026-07-09).

## Métadonnées

- **Dernière mise à jour** : 2026-08-02 (state-keeper FEAT-056)
- **Commit ref** : `6c74bad` (branche `feat/056-multi-tier-subscriptions`, avant merge)
- **Phase** : MVP ✅ + Post-MVP M1 ✅ + Mobile/Stores ✅ (FEAT-024/043/045/048) + Freemium ✅ (FEAT-044) + **Paiement Pro : back-end ✅ / client ❌** (FEAT-044c/d) + **Multi-paliers Pro/Max/Ultra : back-end ✅ / client 🚧** (FEAT-056 non mergé) + Growth/SEO ✅ (FEAT-049 ; FEAT-050 planifié) + **Isolation prod/staging ✅ (ADR 0003)** + **Comparaison scénarios ✅ (FEAT-055)**

### Périmètre réellement re-vérifié

| Zone | État |
|---|---|
| `functions/src/callable/{create_checkout_session,manage_subscription,scenarios}.ts` + entitlements modules | ✅ **relu ligne à ligne 2026-08-02** — FEAT-056 callables multi-paliers, 3 actions (cancel/reactivate/change_plan), quota enforce |
| `firestore.rules` (landlords : `planLevel`, `entitlements` gelés client ; investment_scenarios : `create if false`) | ✅ **re-vérifié 2026-08-02** — FEAT-056 contraintes immutabilité client, routing scenario création CF-exclusive |
| `lib/core/router/app_router.dart` — routes `/pro/*` (`success`, `cancel`) | ✅ **vérifié 2026-08-02** — routes déclarées (lignes 234-247), corrigent une fausse info de l'état 2026-07-21 |
| Domaine `account` (schéma/functions/routes) | ✅ **re-vérifié 2026-08-02** — FEAT-056 : `planLevel`, `entitlements` sur `landlords` ; `manageSubscription` callable manquant de l'état ancien ; routes `/pro/*` réelles |
| Domaines `properties`, `leases`, `expenses-documents`, `simulator` — quotas FEAT-056 | ✅ **vérifié 2026-08-02** — grille `config/entitlements.json` appliquée callables ; `investment_scenarios/create` CF-exclusive |
| `config/entitlements.json` (source canonique quotas) | ✅ **lu 2026-08-02** — 3 paliers, quotas par palier, statuts `purchasable`/`priceIndicative`, features matrix |
| `THEME.md`, `DESIGN_TOKENS.md`, `DEPENDENCIES.md` | ⚠️ **non revus** — `DEPENDENCIES.md` ignore notamment `stripe@^22.3.2` |

> La passe FEAT-056 (2026-08-02) a corrigé 2 dérives détectées dans `functions/account.md` : (1) callable `manage_subscription` manquant, (2) fausse affirmation que `/pro/success` et `/pro/cancel` « n'existent pas ». Mise à jour : tous les shards account + properties/leases/expenses-documents/simulator pour documenter quotas différenciés et la callable CF-exclusive `createScenario`. Restent ⚠️ les fichiers `THEME`/`DESIGN_TOKENS`/`DEPENDENCIES`, non revus.

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

Panoramas transverses : [`schema/README`](schema/README.md) (11 collections + patterns règles Firestore/soft-delete/index) · [`functions/README`](functions/README.md) (callables + triggers + HTTP + scheduled) · [`routes/README`](routes/README.md) (3-états + shell nav).

## Autres fichiers d'état (charge à la demande)

| Besoin | Fichier |
|---|---|
| Statut des features (matrice) | [`FEATURES.md`](FEATURES.md) |
| Changements récents (période courante, ~1k tokens) | [`CHANGELOG.md`](CHANGELOG.md) |
| Historique ancien (archives mensuelles figées, ~10k tokens — n'ouvrir que si nécessaire) | [`changelog/`](changelog/) |
| Thème Baillan papier/encre/olive (FEAT-020) + dark mode + `themeMode` | [`THEME.md`](THEME.md) |
| Design tokens (couleurs, spacing) | [`DESIGN_TOKENS.md`](DESIGN_TOKENS.md) |
| Dépendances (pubspec + functions) | [`DEPENDENCIES.md`](DEPENDENCIES.md) |

## Stack (résumé)

- **Frontend** : Flutter 3.x + Dart 3.11+ (web + Android + iOS `com.daki.baillan`), CanvasKit, EB Garamond serif.
- **State/Nav** : Riverpod 2.6 (StreamProvider) · GoRouter 14.6 (garde 3-états via sessionStateProvider).
- **Auth** : Firebase Auth natif (email/password + Google + Apple + anonyme).
- **Backend** : Firestore (11 collections, camelCase, soft-delete + **37 index composites**, règles 3 couches) + Cloud Functions Node 20 (**17 callables + 9 triggers + 1 HTTP + 2 scheduled**).
- **Paiement** : Stripe Checkout (web) + RevenueCat comme plan de gestion (entitlement `pro`) → webhook serveur-autoritaire. **Back-end seul : aucune UI, aucun `purchases_flutter`.**
- **Storage** : Firebase Storage (signed URLs 5 min ; documents ≤ 10 MiB, quota free 10). **PDF** : `pdf` + `share_plus` (quittance loi 6/07/1989). **Hosting** : Firebase **multi-site** (`prod` → baillan.com, `stage` → stage.baillan.com) ; ⚠️ **les deux partagent Firestore/Auth/Storage du même projet — un test sur staging écrit en prod**. **CI** : GitHub Actions (format + analyze + tests Flutter, + job `functions` lint/build/test).

## Quand mettre à jour cet état

- Après une feature mergée / migration → `state-keeper` met à jour le(s) shard(s) touché(s) + la ligne FEATURES + une entrée CHANGELOG.
- Avant un sprint → `/refresh-state`.
- Incohérence détectée → flag immédiat à l'utilisateur.
