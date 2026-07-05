# FEAT-019 — Rollback Procedure (Firebase → Supabase)

**Statut** : Plan obligatoire avant cutover GO
**Cible SLA** : < 60 min de Trigger à Service Restauré
**Audience** : dev solo, exécutable à 3h du matin sans hésitation
**Date** : 2026-06-30

---

## 0. Objectif & portée

Permettre de revenir 100% sur Supabase si la migration Firebase échoue **post-cutover**. Hors scope : rollback partiel (dual-write), rollback Auth seul.

---

## 1. Pré-requis avant cutover (CHECKLIST GO/NO-GO)

Sans ces 6 cases cochées, **NE PAS cutover** :

- [ ] **Backup Supabase Phase 0 validé** — `backups/feat-019-phase-0/MANIFEST.md` présent, SHA256 racine vérifiée :
      `cd backups/feat-019-phase-0 && shasum -a 256 -c SHA256SUMS` → toutes les lignes `OK`
      Hash attendu : `fa4b7786db8e13b50dd411d20843bf6aa6675c8ef7f6f4e36e401d68d9f2d92a`
- [ ] **Dump SQL exécutable** présent (`schema_full.sql` + `data_full.sql`) — cf. "Recommended next step" du MANIFEST. Sinon, rebuild via `supabase/migrations/` (19 fichiers archivés).
- [ ] **Projet Supabase NON supprimé** post-cutover — gardé en pause minimum **30 jours** (statut `INACTIVE` autorisé, `DELETED` interdit). Vérifier dans dashboard Supabase.
- [ ] **PR de cutover identifiée** — numéro de PR + SHA du commit `feat-019-cutover` notés dans ce doc avant merge :
      - PR : `#___` — Commit : `_______________`
      - Commit du parent (avant cutover) : `_______________` ← cible du revert
- [ ] **Snapshot Firestore** post-cutover programmé (export GCS) — au cas où on doive forensic les data corrompues avant rollback.
- [ ] **Drill rollback effectué** sur staging-bis dans les 7 jours précédents (cf. §5).

---

## 2. Triggers du rollback

Décision binaire — **un seul** des signaux ci-dessous suffit pour déclencher :

| # | Signal | Seuil | Source |
|---|---|---|---|
| T1 | **Régression compliance / RGPD** | Tout incident RLS-équivalent : data leak cross-landlord, consentement perdu, quittance non conforme loi 1989 | Bug report + repro |
| T2 | **Perf catastrophique** | p95 latency API > 5s pendant 15 min OU error rate > 5% sur 10 min | Cloud Monitoring / Sentry |
| T3 | **Data corruption** | Écart de count > 0 sur n'importe quelle collection critique (landlords/properties/leases/payments/receipts) vs snapshot pré-cutover | Script `scripts/verify_counts.sh` |
| T4 | **Auth cassée** | > 20% des utilisateurs MVP testeurs ne peuvent plus se connecter pendant > 30 min | Logs Firebase Auth |
| T5 | **Décision produit** | David décide manuellement (UX intolérable, bug bloquant non patchable < 4h) | Jugement |

**Règle d'or** : si on hésite > 10 min sur T1 ou T3, **on rollback**. Compliance et data integrity ne se négocient pas.

---

## 3. Procédure étape par étape

> Tous les timings sont **wall-clock**, en partant d'une décision GO rollback prise.
> Total target : **52 min** (buffer 8 min sur SLA 60 min).

### Étape 1 — Annoncer downtime (T+0 → T+3 min)

```bash
# Bannière maintenance ON
firebase functions:config:set maintenance.enabled=true --project easyrent-prod
firebase deploy --only functions:setMaintenance --project easyrent-prod
```

- Envoyer email aux testeurs MVP via template `templates/rollback-downtime.md` (liste : `docs/state/MVP_TESTERS.md`)
- Post Slack `#easyrent-status` : "Rollback en cours, ETA 45 min, service indisponible"
- Activer status page si présente

**Durée** : 3 min

### Étape 2 — Switch Flutter app config back to Supabase (T+3 → T+13 min)

```bash
# Revert du commit de cutover
git checkout main
git revert --no-edit <SHA_commit_cutover>   # cf. §1, ligne PR identifiée
git push origin main
# CI/CD déploie Firebase Hosting automatiquement (Workflow .github/workflows/deploy-prod.yml)
```

Vérifier que `lib/core/config/env.dart` repointe `supabaseUrl` + `supabaseAnonKey` (et non Firebase). Si revert pollue d'autres fichiers, faire un commit manuel ciblé sur :
- `lib/core/config/env.dart`
- `lib/main.dart` (init Supabase au lieu de Firebase)
- `web/index.html` (CSP : retirer `*.googleapis.com` si gênant, ajouter `*.supabase.co`)

**Durée** : 10 min (incluant build + déploy Hosting ~6 min)

### Étape 3 — Restaurer la DB Supabase (T+13 → T+28 min)

**Cas A — Aucune écriture post-cutover** (cas nominal si cutover < 24h) :
```bash
# La DB Supabase est intacte (gardée en pause). Juste la réveiller :
# Dashboard Supabase → Restore project → status RUNNING
```
**Durée** : 5 min

**Cas B — Écritures post-cutover détectées** (rare, si lecture/écriture restée ouverte) :
```bash
cd backups/feat-019-phase-0
# Si dump SQL exécutable présent :
psql "$SUPABASE_DB_URL" -f schema_full.sql   # idempotent (DROP CASCADE inside)
psql "$SUPABASE_DB_URL" -f data_full.sql
# Sinon : rebuild via migrations
supabase link --project-ref tbgttutodbqffrvsvkoz
supabase db reset --linked   # rejoue les 19 migrations
# Puis réimporter data depuis data/*.json via scripts/restore_data.dart
```
**Durée** : 15 min

### Étape 4 — Vérifier intégrité data (T+28 → T+38 min)

```bash
./scripts/verify_counts.sh --source backup --target supabase
# Doit afficher OK pour les 8 tables × 2 schémas (16 lignes)
```

Cross-check manuel SQL :
```sql
SELECT 'landlords' AS t, COUNT(*) FROM public.landlords
UNION ALL SELECT 'properties', COUNT(*) FROM public.properties
UNION ALL SELECT 'tenants',    COUNT(*) FROM public.tenants
UNION ALL SELECT 'leases',     COUNT(*) FROM public.leases
UNION ALL SELECT 'payments',   COUNT(*) FROM public.payments
UNION ALL SELECT 'receipts',   COUNT(*) FROM public.receipts;
```

Comparer aux counts du MANIFEST (actuellement : 0 partout — DB vide post-purge, donc trivial). Quand la DB ne sera plus vide, comparer au snapshot pré-cutover.

**Durée** : 10 min

### Étape 5 — Smoke test E2E 15 scenarios parité (T+38 → T+50 min)

Exécuter `test/e2e/parity_15.dart` (référence : doc `FEAT-019-supabase-to-firebase-migration.md` §parité fonctionnelle).

Scénarios obligatoires :
1. Login magic link
2. Login password
3. Créer landlord
4. Créer property
5. Créer tenant
6. Créer lease
7. Enregistrer payment
8. Générer quittance PDF
9. Email quittance
10. Upload document
11. Dashboard load
12. RLS cross-user (négatif : doit échouer)
13. Export RGPD
14. Suppression compte RGPD
15. Dual-language fallback (FR/EN)

**Critère pass** : 15/15. Si même 1 échec → **escalade** (cf. §6).

**Durée** : 12 min

### Étape 6 — Annoncer service restauré (T+50 → T+52 min)

```bash
firebase functions:config:set maintenance.enabled=false --project easyrent-prod
firebase deploy --only functions:setMaintenance --project easyrent-prod
```

- Email testeurs MVP via `templates/rollback-restored.md`
- Slack `#easyrent-status` : "Service restauré sur Supabase. Post-mortem demain."
- Créer issue GitHub `[POST-MORTEM] Rollback FEAT-019 <date>` avec timeline.

**Durée** : 2 min

---

## 4. Estimation temps — récap

| Étape | Action | Cumul (min) |
|---|---|---|
| 1 | Annoncer downtime | 3 |
| 2 | Revert PR cutover + redeploy Hosting | 13 |
| 3 | Restaurer DB Supabase (Cas A) | 18 |
| 3' | Restaurer DB Supabase (Cas B) | 28 |
| 4 | Vérifier intégrité data | 28 / 38 |
| 5 | Smoke test 15 scenarios parité | 40 / 50 |
| 6 | Annoncer service restauré | 42 / 52 |

**SLA** : < 60 min. Cas A confortable (42 min), Cas B serré (52 min, buffer 8 min).

---

## 5. Drill — tester ce rollback sans toucher prod

### 5.1 Environnement dédié : "staging-bis"

Créer un environnement isolé qui mime la prod :
- **Supabase** : projet `easy-rent-staging-bis` (clone de prod via `supabase db dump | psql`)
- **Firebase** : projet `easyrent-staging-bis` (Firestore + Hosting + Functions)
- **Flutter** : flavor `stagingBis` avec ses propres env vars (`env_staging_bis.json`)
- **Domaine** : `staging-bis.easyrent.app` (Hosting custom domain)

### 5.2 Procédure du drill (à exécuter J-7 avant cutover prod)

1. Cutover staging-bis (Supabase → Firebase) **avec data réaliste** (seed via `scripts/seed_realistic.dart` : 5 landlords, 30 properties, 100 leases, 500 payments).
2. Attendre 24h pour simuler l'opération nominale + quelques écritures.
3. **Injecter un trigger artificiel** (au choix) :
   - T2 simulé : `gcloud functions deploy` une version qui sleep 6s → p95 > 5s
   - T3 simulé : `firestore:delete` une collection au hasard → mismatch counts
4. Exécuter §3 (étapes 1 à 6) en conditions réelles, **chronomètre en main**.
5. Mesurer le temps total. Si > 60 min → identifier le goulot et patcher la procédure **avant** cutover prod.

### 5.3 Critères de succès du drill

- [ ] Total drill < 60 min
- [ ] 15/15 smoke tests passent post-rollback
- [ ] Aucune intervention manuelle hors procédure
- [ ] Procédure exécutable à partir du seul ce doc (pas besoin de lire le code)

Le drill **doit** être refait si une étape de la procédure change.

---

## 6. Escalade — quand le rollback lui-même échoue

Si étape 4 ou 5 échoue :

1. **NE PAS** improviser sur la prod. Remettre le mode maintenance ON.
2. Ouvrir un fil Slack dédié `#incident-rollback-<date>`.
3. Restaurer **manuellement** depuis `backups/feat-019-phase-0/data/*.json` (script `scripts/restore_data.dart --dry-run` puis sans flag).
4. Si rien ne marche : restaurer le projet Supabase entier depuis le **PITR (Point-in-Time Recovery)** Supabase Pro plan (si activé) — fenêtre 7 jours.
5. Dernier recours : recréer un projet Supabase from scratch via `supabase/migrations/` + import data, et patcher l'URL projet dans `env.dart`.

---

## 7. Annexes

- **Backup MANIFEST** : `backups/feat-019-phase-0/MANIFEST.md`
- **Plan de migration** : `docs/plans/FEAT-019-supabase-to-firebase-migration.md`
- **Data model Firestore** : `docs/plans/FEAT-019-firestore-data-model.md`
- **Scripts à créer** :
  - `scripts/verify_counts.sh` (étape 4)
  - `scripts/restore_data.dart` (cas B / escalade)
  - `scripts/seed_realistic.dart` (drill)
  - `test/e2e/parity_15.dart` (étape 5)
- **Templates communication** :
  - `templates/rollback-downtime.md`
  - `templates/rollback-restored.md`

---

## 8. Sign-off pre-cutover

À signer (commit dans ce doc) avant de lancer la migration prod :

- [ ] Drill réussi le : `__________` (lien session)
- [ ] Backup Phase 0 vérifié le : `__________`
- [ ] Dump SQL exécutable présent : `oui / non`
- [ ] Templates communication rédigés : `oui / non`
- [ ] Scripts verify/restore testés : `oui / non`

**Sans toutes ces cases : NO-GO cutover.**
