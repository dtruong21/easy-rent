# Checklist — 1er déploiement production EasyRent

> Cocher chaque item avant / pendant / après le déploiement.
> Durée estimée : 30 min (smoke test) + 1–2h (provisionnement initial).

---

## A. Secrets GitHub (environnement `production`)

Aller dans GitHub → Settings → Environments → `production`.

- [ ] `SUPABASE_URL` provisionné
- [ ] `SUPABASE_ANON_KEY` provisionné
- [ ] `FIREBASE_SERVICE_ACCOUNT` provisionné (JSON service account)
- [ ] `FIREBASE_PROJECT_ID` provisionné (`easy-rent-54cd4`)
- [ ] `SUPABASE_PROJECT_REF` provisionné (`tbgttutodbqffrvsvkoz`)
- [ ] `SUPABASE_ACCESS_TOKEN` provisionné (`sbp_xxx...`)
- [ ] `SUPABASE_DB_PASSWORD` provisionné
- [ ] Environnement `production` configuré avec "Required reviewers" (optionnel mais recommandé)

> Note : RESEND_API_KEY et RESEND_FROM_EMAIL sont des secrets Supabase, pas GitHub.

---

## B. Resend — Email (peut être fait après go-live)

- [ ] Compte Resend créé sur resend.com
- [ ] Domaine vérifié (enregistrements DNS ajoutés + propagation OK)
- [ ] DPA signée sur resend.com/legal/dpa
- [ ] API Key dédiée production créée (nommer `easyrent-prod`)
- [ ] Secrets Supabase provisionnés : `RESEND_API_KEY` + `RESEND_FROM_EMAIL`
- [ ] Edge Function `send-receipt` déployée sur le projet prod

> Sans Resend configuré, l'envoi d'emails de quittances échouera.
> Le reste de l'app fonctionne normalement.

---

## C. Supabase Auth — Configuration URL

- [ ] Site URL configuré : `https://easy-rent-54cd4.web.app`
- [ ] Redirect Allow-List configurée : `https://easy-rent-54cd4.web.app/**`

> Aller dans Dashboard Supabase → Authentication → URL Configuration.
> Sans cela, les magic links ne fonctionneront pas en prod.

---

## D. Migrations

- [ ] `migrate-prod.yml` lancé en `dry_run=true` → liste de migrations vérifiée
- [ ] `migrate-prod.yml` lancé en `dry_run=false, confirmation=yes` → appliqué OK
- [ ] Vérification dans Supabase Dashboard → Table Editor (tables visibles)

---

## E. Build + Deploy

- [ ] Merge `feature/dashboard-pwa-prod-setup` → `develop` → staging déployé
- [ ] Tests manuels en staging passent
- [ ] Merge `develop` → `main` → workflow `deploy.yml` prod déclenché
- [ ] Build GitHub Actions : pas d'erreur dans les logs
- [ ] Firebase Hosting : déploiement canal `live` réussi

---

## F. Smoke test (15 étapes — ~30 min)

Ouvrir `https://easy-rent-54cd4.web.app` dans Chrome.

- [ ] La page de login s'affiche correctement (pas de page blanche)
- [ ] Cliquer "Politique de confidentialité" → page `/privacy` complète s'affiche sans login
- [ ] Demander un magic link avec un email réel → email reçu en moins de 30s
- [ ] Cliquer le lien email → redirect vers dashboard, session active, pas d'erreur
- [ ] Dashboard affiche l'onboarding "Premiers pas" (3 étapes visibles)
- [ ] Cliquer étape 1 → page `/properties/new` → créer un bien → retour dashboard OK
- [ ] Cliquer étape 2 → page `/tenants/new` → créer un locataire → retour dashboard OK
- [ ] Cliquer étape 3 → page `/leases/new` → créer un bail → retour dashboard OK
- [ ] Retour dashboard → 4 KPI cards affichées (loyers, retards, renouvellements, docs)
- [ ] Naviguer vers le bail créé → enregistrer un paiement → dashboard KPI mis à jour
- [ ] Sur la page quittances → générer une quittance PDF → preview PDF s'ouvre OK
- [ ] Cliquer "Envoyer par email" → email reçu (vérifier dossier spam) _(nécessite Resend configuré)_
- [ ] Uploader un document PDF de test (catégorie "autre") → visible dans la liste
- [ ] Retour dashboard → activité récente affiche le paiement + la quittance
- [ ] Chrome desktop : PWA install prompt visible → cliquer "Installer" → app installée

---

## G. Vérifications post-deploy (48h)

- [ ] Supabase Dashboard → Logs : aucune erreur Auth ou Edge Function
- [ ] Resend Dashboard : emails délivrés sans rebond
- [ ] Test logout + re-login : magic link fonctionne toujours
- [ ] Rafraîchissement forcé (Ctrl+Shift+R) : nouvelle version servie (pas de cache stale SW)

---

## H. Documentation

- [ ] `docs/state/FEATURES.md` : FEAT-010 marqué ✅ déployé
- [ ] `docs/state/INDEX.md` : timestamp mis à jour
- [ ] Équipe informée du go-live

---

## Rollback rapide si nécessaire

```bash
# Lister les versions Firebase
firebase hosting:versions:list --project easy-rent-54cd4

# Revenir à la version précédente
firebase hosting:clone easy-rent-54cd4:live easy-rent-54cd4:live \
  --version-id=<PREVIOUS_VERSION_ID>
```

Voir `docs/RUNBOOK_PROD_DEPLOY.md` §4 pour les détails.
