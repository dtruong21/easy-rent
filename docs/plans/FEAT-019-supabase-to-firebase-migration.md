# Migration Supabase → Firebase — Plan v0

## Verdict global

**NO-GO catégorique.** Les trois lentilles d'audit convergent sans ambiguïté : (1) **effort realism** = NO-GO (~14-19 semaines solo, soit 4× la durée du MVP entier) ; (2) **domain fit** = ALTERNATIVE RECOMMANDÉE (EasyRent est un domaine fondamentalement relationnel — 9 entités, FK croisés, dashboards agrégés, invariants légaux loi 1989 + RGPD enforce au niveau DB — où Firestore impose de simuler artificiellement du relationnel par-dessus du document store) ; (3) **migration safety** = NO-GO (aucun backup explicite, aucun rollback testé, aucun test E2E de parité comportementale, fenêtre RLS bypass non chronologisée). Ton "let's start" est compréhensible vu que tu as activé les services et obtenu des crédits, mais les designs eux-mêmes — y compris ceux que tu m'as demandés — concluent indépendamment que cette migration n'a aucun driver business identifié et un ROI négatif. La recommandation honnête est : **garde Supabase, n'investis pas 4 mois là-dedans.**

## Effort réaliste

| Poste | Heures |
|---|---|
| Modèle Firestore + dénormalisation + indexes | 30 |
| Security Rules (~56 RLS → rules + tests émulateur) | 60 |
| Cloud Functions (15 fonctions remplaçant ~49 triggers + 5 RPCs) | 50 |
| Refacto repositories Flutter (~2400 LOC) + auth (~570 LOC) | 60 |
| Refacto Edge Function `generate-receipt` Deno → Cloud Function Node (1010 LOC + tests PDF visual regression compliance loi 1989) | 30 |
| Migration data + script + dry-run + validation cross-user | 40 |
| Réécriture tests (~1500 sur 1663) | 70 |
| QA staging multi-passes (2-3 cycles, 18 features dont 14 couplées) | 50 |
| Documentation (ENVIRONMENTS, SECURITY, SCHEMA, ADR) | 16 |
| Apprentissage Firestore/Cloud Functions/Security Rules (profil mobile, peu de web moderne) | 25 |
| Rework cycles post-QA (4 features à risque MAXIMAL) | 40 |
| **Sous-total** | **~470h** |
| **Risk multiplier × 1.3** (interruptions, support Supabase prod en parallèle, FEAT prioritaires roadmap, bugs imprévus) | **~610h** |

**Conversion solo dev** (7h productives/jour × 5 jours = 35h/semaine) :
- 610h / 35 = **~17 semaines = ~4 mois plein temps**
- Plage réaliste : **14-19 semaines (3.5 à 4.5 mois)**

**Ton "let's start" implique probablement quelques jours/semaines.** L'écart est de **20×**. Le CLAUDE.md indique MVP < 1 mois — cette migration consommerait 4× le budget MVP restant en gelant 100% de la roadmap features.

## Coût Firestore projeté

| Volume | Firebase mensuel | Supabase actuel | Delta annuel |
|---|---|---|---|
| Staging (5 users, 150 sessions/mois) | ~$0 (free tier) | $0 (free tier) | **0$** |
| Prod 100 users | ~$1/mois | $25/mois (Pro) | -$288/an |
| Prod 1000 users | ~$15/mois (avec realtime: ~$20) | ~$35/mois | -$240/an |
| Prod 10k users | **~$150/mois** | ~$100/mois (Team) | **+$600/an** |

**Conclusion FinOps** :
- À l'échelle staging actuelle (ton cas) : **économie = 0$**
- À l'échelle MVP réaliste (<1000 users à 12 mois) : économie max ~$240/an
- **Au-delà de 5000 users, Firebase devient PLUS CHER que Supabase** (pricing per-operation hostile aux apps data-lourdes avec joins/agrégats)
- **Break-even vs coût de migration (~30k€ en équivalent temps dev) : JAMAIS atteint** à l'échelle prévisible
- Crédits Firebase activés : utiles pour Hosting + FCM, pas pour justifier une migration data
- Piège majeur : si realtime listeners activés (remplacement des `Stream` Supabase), facture x2-3 non-prédictible

## Risques majeurs (top 5)

1. **Compliance loi 6 juillet 1989 (quittances immuables) — SÉVÉRITÉ CRITIQUE.** L'immutabilité passe de constraints DB hard (triggers `protect_immutable_documents`, `protect_sent_columns_receipts`, RLS sans UPDATE/DELETE) à des Security Rules + Cloud Functions contournables via Admin SDK. *Mitigation* : Callable Cloud Functions exclusives + tests émulateur exhaustifs + audit code obligatoire en PR. Mais perte de garantie schéma-level irréversible.

2. **Compliance RGPD : atomicité consent + rétention 5 ans — SÉVÉRITÉ CRITIQUE.** Le trigger `handle_new_user()` AFTER INSERT atomique (signup + landlord_insert + rgpd_consent_version dans la même transaction) devient eventually-consistent en Firebase Auth + Cloud Function `onCreate(user)`. FK NO ACTION (rétention 5 ans) n'a pas d'équivalent Firebase Auth strict. *Mitigation* : `beforeUserCreated` blocking function + reconciliation job. Mais fenêtre de race condition possible.

3. **Cross-tenant data leak — SÉVÉRITÉ ÉLEVÉE.** Les triggers `assert_payment_lease_ownership` et `assert_receipt_lease_ownership` (SECURITY DEFINER, BEFORE INSERT, atomiques) garantissent qu'on ne peut pas écrire un payment avec lease_id pointant chez un autre landlord. Firestore Security Rules ne peuvent pas faire de cross-doc lookup transactionnel. *Mitigation* : `get()` chain dans rules (coût reads) ou Cloud Functions Callable forcées. Fenêtre d'incohérence ~1-2s sur compensation post-write.

4. **Aucun rollback testé — SÉVÉRITÉ ÉLEVÉE.** Le plan implicite est un cutover sec sans procédure documentée. Une fois `firebase auth:import` exécuté et bcrypt re-hashé en scrypt au premier login, revenir à Supabase Auth force les users à recréer leur compte. Pas de script `flip_backend.sh`, pas de drill testé. *Mitigation* obligatoire : Supabase laissé read-only 14j post-migration + rollback scripté + drill complet sur staging-bis AVANT go.

5. **Régression silencieuse `is_stale` quittances — SÉVÉRITÉ MOYENNE.** Le trigger `recompute_receipt_stale_on_payment_archive` (AFTER UPDATE OF deleted_at sur payments → recalcul via GIN index `payment_ids[]`) devient une Cloud Function `onUpdate(payments)` qui scan `receipts where paymentIds array-contains` — asynchrone, latence, possibilité d'échec silencieux. Audit révision quittance peut afficher `is_stale=false` à tort. *Mitigation* : monitoring Cloud Functions + reconciliation périodique + tests E2E parité.

## Plan phasé recommandé

**Pas de plan d'exécution. Le verdict est NO-GO.**

Engager 4 mois de réécriture sans driver business identifié, en sacrifiant la roadmap MVP, pour économiser au mieux $20/mois, avec risque de régression sur la compliance loi 1989 + RGPD, n'est pas une décision défendable.

Si tu veux quand même y aller (décision politique irrévocable), les **7 conditions bloquantes minimales** avant tout commit de code :

1. Driver business documenté (OAuth Apple/Google ? MFA enterprise ? scale prévu >10k users ?) — sans ça, stop
2. Backup complet : `pg_dump` schemas public+dev+auth+storage + `gcloud storage rsync` buckets, archivé 90j
3. Rollback scripté + testé sur staging-bis (drill complet AVANT go)
4. Ordre cutover chronologique documenté (freeze writes → export → import → smoke tests → bascule config Flutter)
5. Suite E2E parité comportementale (15 scénarios min : cross-tenant deny, is_stale propagation, immutabilité receipt, atomicité consent, legal_hold, soft-delete landlord RESTRICT, checksum PDF byte-à-byte)
6. Communication testeurs MVP : fenêtre downtime ~3-4h annoncée 48h avant
7. Gel formel de la roadmap features pendant 16-20 semaines accepté par toi explicitement

## Alternatives à considérer

**Question centrale : quelle est ta VRAIE motivation ?** Tu as activé Firebase + obtenu des crédits + dit "let's start" — mais les designs montrent qu'aucun besoin fonctionnel non couvert par Supabase n'a été identifié. Hypothèses :

- **A. Tu veux utiliser tes crédits Firebase** → Bonne idée, mais pas pour le data layer. Utilise Firebase pour **Hosting** (tu y es déjà), **FCM** (push notifications futures), **App Check** (anti-abuse), **Analytics**. Garde Supabase pour Postgres + Auth.

- **B. Tu veux OAuth Google/Apple (signup social)** → **Supabase Auth supporte déjà OAuth Google/Apple/etc. nativement** (config console, 0 LOC backend). Active-le en 1h, pas en 4 mois.

- **C. Tu veux maîtriser les coûts** → Supabase Pro à $25/mois flat couvre jusqu'à ~5000 users. Firebase ne devient compétitif qu'entre 100-1000 users avec une économie max $240/an, hors-comparaison avec le coût opportunité de la migration.

- **D. Tu veux apprendre Firebase** → Légitime, mais fais-le sur un side-project, pas sur EasyRent en pleine traction MVP. Le profil de ton MEMORY.md indique "peu de web framework moderne" — l'apprentissage Firestore Rules + Cloud Functions v2 + Multi-DB ajouterait 25h+ rien qu'en montée en compétence.

- **E. Tu veux du real-time multi-device** → Supabase Realtime existe nativement (postgres_changes via WebSocket). Pas besoin de migrer.

- **F. Tu veux du offline-first PWA** → Légitime besoin, mais Firestore offline persistence est limité côté web (IndexedDB), et un cache Riverpod local sur Supabase fait 80% du travail pour 5% de l'effort.

## Décision attendue du user

**Option 1 — Recommandée fortement : RESTER sur Supabase.**
- Effort : 0h
- Risque : 0
- Utilise crédits Firebase pour Hosting (déjà fait) + FCM + Analytics + App Check
- Si besoin OAuth : active providers Supabase Auth natif (1-2h)
- Investis les 4 mois libérés dans la roadmap P1 (analytics bailleur, vue comptable, export PDF batch)

**Option 2 — Compromis : Hybride sans toucher au data layer.**
- Effort : 8-16h
- Garder Supabase Postgres + Supabase Auth intacts
- Ajouter Firebase Hosting (déjà) + FCM pour push notifications + Firebase Analytics
- Surface fonctionnelle nouvelle sans réécriture, crédits Firebase utilisés utilement

**Option 3 — Déconseillée : Migration complète.**
- Effort : **14-19 semaines plein temps** (3.5-4.5 mois)
- Gel total roadmap features
- Économie infra : 0$ staging, ~$20/mois max prod ≤1000 users, **plus cher au-delà 5000 users**
- Risque compliance loi 1989 + RGPD pendant la fenêtre
- Pré-requis 7 conditions bloquantes ci-dessus
- **Aucun driver business identifié à ce jour**

Mon conseil direct : **Option 1**. Si tu veux absolument toucher à Firebase, **Option 2**. L'**Option 3** n'est défendable que si tu réponds clairement à "quel besoin fonctionnel précis Firebase couvre que Supabase ne couvre pas ?" — et à ce jour, dans ton footprint et tes docs, cette réponse n'existe pas.
