# Runbook — bascule de domaine (FEAT-050e)

> Migration de l'app Flutter de la racine du domaine vers un sous-domaine, pour
> laisser la racine à la vitrine. État cible :
>
> ```
> baillan.com          → vitrine Astro (indexable)      cible Hosting `marketing`
> www.baillan.com      → 301 vers baillan.com
> app.baillan.com      → app Flutter (noindex)          cible Hosting `prod`
>
> staging.baillan.com      → vitrine (noindex)          cible `marketing-stage`
> app.staging.baillan.com  → app (noindex)              cible `stage`
> ```
>
> **Nature de ce document** : une partie des étapes est **manuelle** (registrar
> DNS, console Firebase, Play Console) — elles ne peuvent pas être faites par un
> agent et sont marquées 👤. Les étapes de **code** sont préparées sur la branche
> `chore/050e-bascule-domaine` (2 commits, un par phase) et marquées 💻.
>
> **Règle d'or, non négociable** : à chaque phase, **mettre à jour les domaines
> autorisés Firebase Auth AVANT de router le DNS**. Si le DNS bascule d'abord,
> les connexions Google/Apple et les liens email cassent sur le nouvel hôte tant
> que le domaine n'est pas autorisé.

## Prérequis (avant de commencer)

- [x] `baillan.com` acheté, DNS accessible côté registrar (confirmé 2026-09-06).
- [x] **#157 mergé dans `develop`** (2026-09-06) — le fix #138 (`stripe_env.ts`,
      `PROD_ORIGINS`) est sur `develop`, et `develop` a été mergé dans cette
      branche. Le resserrage P6 est donc **déjà écrit** sur `chore/050e-bascule-domaine`
      (commit `173ec5a`). Reste à promouvoir `develop` → `main` pour la prod.
- [ ] Mentions légales de la vitrine complétées — `site/src/pages/mentions-legales.astro`
      porte un encadré « à compléter » (raison sociale, SIREN, adresse,
      directeur de publication) qui bloque volontairement la mise en ligne de
      cette page sur `baillan.com`. Sans structure juridique, la vitrine prod ne
      doit pas partir indexable.
- [ ] Sauvegarde mentale : rien ici n'est réellement irréversible côté données
      (Firestore/Auth/Storage inchangés), mais le DNS et l'URL Play Console ont
      une inertie de propagation — prévoir une fenêtre calme.

---

## Phase 1 — Staging (répéter la bascule à blanc, sans risque prod)

Faire la bascule d'abord sur staging valide toute la mécanique sur un
environnement jetable avant de toucher la prod.

- [ ] **S1** 👤 Registrar : créer l'entrée DNS de `app.staging.baillan.com`
      (l'app de staging). Ne pas encore toucher `staging.baillan.com` si elle
      sert déjà la vitrine via `marketing-stage`.
- [ ] **S2** 👤 Firebase Console → Authentication → Settings → Authorized
      domains : **ajouter `app.staging.baillan.com`** (et `staging.baillan.com`
      si absent). **Faire ceci AVANT S3.**
- [ ] **S3** 👤 Firebase Console → Hosting → site `baillan-stage` → Add custom
      domain → `app.staging.baillan.com`. Suivre les enregistrements A/TXT
      proposés côté registrar, attendre la vérification + le certificat.
- [ ] **S4** 💻 Merger le commit **phase staging** de `chore/050e-bascule-domaine`
      (`413819a`) : `STAGING_ORIGIN` → `app.staging.baillan.com`, `deploy.yml`
      develop `public_url` → `app.staging.baillan.com`. Le push sur `develop`
      redéploie staging avec la nouvelle origine.
      ⚠️ Ne merger qu'une fois S3 vérifié — sinon le routage Firestore de staging
      (qui compare l'`Origin`) cesse de reconnaître staging.
- [ ] **S5** ✅ Vérifier sur `app.staging.baillan.com` : connexion Google/Apple,
      un paiement Stripe de test (mode test, via l'émulateur idéalement),
      création d'un bien → confirme que l'écriture va bien dans la base
      `staging` et non `(default)`. Vérifier que `staging.baillan.com` sert
      toujours la vitrine en `noindex`.
- [ ] **S6** 👤 (optionnel) Retirer l'ancien domaine `stage.baillan.com` du site
      `baillan-stage` une fois `app.staging.baillan.com` stable, ou le laisser en
      301 le temps de la transition.

---

## Phase 2 — Production

Ne démarrer qu'une fois la Phase 1 validée et les prérequis cochés (#157, légal).

- [ ] **P1** 👤 Registrar : préparer les entrées DNS de `app.baillan.com` (app)
      et de `baillan.com` / `www.baillan.com` (vitrine). L'apex `baillan.com`
      exige des enregistrements A/AAAA (pas de CNAME sur l'apex) ; `www` sera un
      301 vers l'apex.
- [ ] **P2** 👤 Firebase Console → Authentication → Authorized domains :
      **ajouter `app.baillan.com`** (et `baillan.com`, `www.baillan.com`).
      **AVANT P3 et P4.** Ne rien retirer encore.
- [ ] **P3** 👤 Firebase Console → Hosting → site `easy-rent-54cd4` (cible
      `prod`) → Add custom domain → `app.baillan.com`. Vérifier + certificat.
- [ ] **P4** 👤 Firebase Console → Hosting → site `baillan-marketing` (cible
      `marketing`) → Add custom domain → `baillan.com` **et** `www.baillan.com`
      (configurer `www` en redirection vers l'apex). Vérifier + certificat.
- [x] **P5** 💻 #157 (fix #138) mergé dans `develop` le 2026-09-06 — prérequis de P6 levé.
- [x] **P6** 💻 **FAIT** sur `chore/050e-bascule-domaine` (commit `173ec5a`) —
      resserrage des origines Stripe, à déployer via P8 :
      - `PROD_ORIGINS` = `["https://app.baillan.com"]` seul (baillan.com et
        www.baillan.com retirés : ils servent la vitrine, jamais la clé live).
      - Origine de test = `https://app.staging.baillan.com` (suit `STAGING_ORIGIN`,
        basculé en phase staging).
      - `WEB_APP_BASE_URL` défaut → `https://app.baillan.com`.
      - `stripe_env.test.ts` : origines à jour + verrou anti-régression (la
        vitrine ne peut jamais être `live`). Suite functions 462/462.
- [ ] **P7** 💻 Merger le commit **phase prod** de `chore/050e-bascule-domaine`
      (`bb32084`) : `env.dart` `publicAppUrl` → `app.baillan.com`, `deploy.yml`
      main `public_url` → `app.baillan.com`, retrait du header noindex transitoire
      de la cible `marketing` (la vitrine baillan.com devient indexable).
- [ ] **P8** 💻 Promouvoir `develop` → `main` (PR de release) pour déployer app
      et vitrine en production sur les nouveaux domaines. Confirmation
      utilisateur requise pour tout déploiement prod (garde-fou CLAUDE.md).
- [ ] **P9** ✅ Vérifier en prod : `app.baillan.com` sert l'app (connexion
      Google/Apple, parcours métier) ; `baillan.com` sert la vitrine, indexable
      (`curl -I` : plus de `X-Robots-Tag: noindex`) ; `www.baillan.com` → 301 vers
      l'apex ; un appel Stripe depuis `baillan.com` (vitrine) est **refusé**
      (`origin_not_allowed`) — seul `app.baillan.com` obtient la clé live.

---

## Phase 3 — Post-bascule

- [ ] **T1** 👤 Google Search Console : ajouter `baillan.com` comme propriété,
      soumettre `https://baillan.com/sitemap-index.xml`. Ne PAS ajouter l'app.
- [ ] **T2** 👤 Play Console → Data safety / Account deletion : mettre l'URL de
      suppression de compte à `https://baillan.com/supprimer-mon-compte`.
      ⚠️ Cette URL est **figée dès soumission** d'une release — ne la changer
      qu'une fois, ici.
- [ ] **T3** 👤 Si des liens externes / stores pointaient vers l'ancienne URL
      racine de l'app, les mettre à jour vers `app.baillan.com`.
- [ ] **T4** 💻 `docs/state/` et `docs/ENVIRONMENTS.md` : retirer les mentions
      « bascule domaine en attente » / « domaine non branché », FEAT-050 passe
      de « v1 construite, bascule en attente » à ✅. `docs/state/INDEX.md`
      ligne 12 + `FEATURES.md`.
- [ ] **T5** ✅ Surveiller pendant quelques jours : Search Console (indexation de
      baillan.com), erreurs Auth (domaines oubliés), et le webhook/cron Stripe
      si des abonnés existent (aucun aujourd'hui, `SUBSCRIPTIONS_ENABLED=false`).

---

## Ce que la bascule ne traite PAS

- L'activation commerciale des paliers payants (`SUBSCRIPTIONS_ENABLED`, issue
  #138 / FEAT-057) : décision distincte, subordonnée à la micro-entreprise et à
  la clé Stripe live.
- La désindexation rétroactive de l'ancienne app : un `Disallow` ne retire pas
  une URL déjà connue de Google. Le changement d'origine (app.baillan.com,
  nouvelle origine) règle l'essentiel ; au besoin, demande de retrait via Search
  Console sur les vieilles URLs indexées.

## Points de vigilance résumés

| Risque | Mitigation |
|---|---|
| DNS avant Auth → connexions cassées | S2/P2 (domaines autorisés) AVANT S3/P4 (DNS/custom domain) |
| Origine Stripe live servie par la vitrine | P6 : `PROD_ORIGINS` = `app.baillan.com` seul |
| Vitrine prod indexable sans mentions légales | Prérequis légal coché avant P7 |
| URL Play Console figée | T2 : ne la poser qu'une fois |
| PWA installées sur l'ancien hôte | ne suivent pas (origine différente) — réinstallation ; aucun abonné réel concerné |
| Merge d'un commit de bascule avant son DNS | S4/P7 : ne merger qu'après vérification du custom domain de la phase |
