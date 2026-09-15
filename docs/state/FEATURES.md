# Features — registre

> Source d'état — features. Maintenu par state-keeper. Dernière sync : 2026-07-30.

Statut : ✅ done | 🟢 ready | 🚧 wip | 📋 planned | 💡 idea. Historique détaillé → CHANGELOG.md.

| FEAT-ID | Nom court | Statut | Domaine | Réf commit/PR |
|---|---|---|---|---|
| FEAT-001 | Auth propriétaire magic link (remplacée → 011) | ✅ done | account | — |
| FEAT-002 | Modèle Postgres + RLS (archivé, migré → 019) | ✅ done | account | — |
| FEAT-003 | CRUD UI propriétés | ✅ done | properties | — |
| FEAT-004 | CRUD UI locataires | ✅ done | properties | — |
| FEAT-005 | CRUD UI baux | ✅ done | leases | — |
| FEAT-006 | CRUD paiements | ✅ done | payments-receipts | — |
| FEAT-007 | Quittance PDF + Web Share | ✅ done | payments-receipts | — |
| FEAT-008 | Partage quittance natif | ✅ done | payments-receipts | — |
| FEAT-009 | Upload documents (PDF, images) | ✅ done | expenses-documents | — |
| FEAT-010 | Dashboard + PWA + prod setup | ✅ done | dashboard | — |
| FEAT-011 | Auth email + password | ✅ done | account | — |
| FEAT-012 | Cards system (EntityCard) | ✅ done | dashboard | — |
| FEAT-013 | UX modernization (AppAppBar, palette indigo) | ✅ done | dashboard | — |
| FEAT-014 | Forms enrichment FR (32 champs : DPE, garant, IRL, dépôt) | ✅ done | leases | — |
| FEAT-015 | Detail pages enrichment | ✅ done | properties | — |
| FEAT-016 | RGPD consent persistence | ✅ done | account | — |
| FEAT-017 | Rentabilité portfolio (rendement, cash-flow) | ✅ done | properties | — |
| FEAT-018 | Simulateur investissement | ✅ done | simulator | — |
| FEAT-019 | Migration backend → Firebase (Firestore) | ✅ done | account | — |
| FEAT-020 | Rebrand EasyRent → Baillan | ✅ done | account | — |
| FEAT-021 | Vérification email post-signup | ✅ done | account | — |
| FEAT-022 | Redesign login « La Page du Registre » | ✅ done | account | — |
| FEAT-023 | Réglages app (thème + légal + version) | ✅ done | account | — |
| FEAT-024 | App mobile iOS/Android (bundle com.daki.baillan) | ✅ done | account | feature/024-mobile (2026-07-06) |
| FEAT-025 | Sécurité + support in-app (support_requests) | ✅ done | account | 0cd54de, f5734b4 |
| FEAT-025b | /profile HUB de réglages | ✅ done | account | 16ebc77 |
| FEAT-026 | Navigation shell adaptative (5 branches) | ✅ done | dashboard | ca2d10a |
| FEAT-027 | Dashboard — période graphique (6/12/24m) | ✅ done | dashboard | ba7c12d |
| FEAT-028 | Détection retards de paiement (grâce 5j) | ✅ done | leases | 7ac1d03 |
| FEAT-029 | Charges — motif paiement + régularisation annuelle | ✅ done | leases | 871ebff |
| FEAT-029b | Découvrabilité régularisation (?action=regularize) | ✅ done | leases | 514666f |
| FEAT-030 | Navigation retour corrigée (pop/push) | ✅ done | dashboard | 7db144d |
| FEAT-031 | Relance de paiement assistée (client-side) — automatisation cron = V2 | ✅ done | leases | feat/payment-reminder-assisted |
| FEAT-032 | Dashboard — trésorerie graphique (encaissé vs dû) | ❌ superseded 2026-09-15 (par FEAT-027) | dashboard | — |
| FEAT-033 | Archivage régularisations charges — snapshot figé (`charge_statements`, immuable) | ✅ done + staging 2026-09-14 (PR #182, functions déployées) | leases | PR #182 |
| FEAT-034 | Import multi-colonnes CSV (properties/tenants/leases) | ❌ abandonné 2026-09-14 | properties | — |
| FEAT-035 | 2FA TOTP | 📋 planned | account | — |
| FEAT-036 | Charges récupérables vs non-récupérables (décret 87-713) | ✅ done | leases | PR #66 |
| FEAT-041 | Suivi dépenses unifié V1 (expenses + documents v2) | ✅ done | expenses-documents | PR #67 |
| FEAT-042 | Mode de charges (provisions/forfait) + éligibilité régul. | ✅ done | leases | PR #68 |
| FEAT-043 | Internationalisation FR/EN (i18n, gen_l10n) | ✅ done | account | PR #71 |
| FEAT-044 | Freemium enforcement — plafonds free (2 biens/3 locataires/2 baux) | ✅ done | properties, leases | PR #91 |
| FEAT-044b | Gating Pro — quota documents (10 free, serveur) + régularisation charges (client) | ✅ done | expenses-documents, leases | PR #120 |
| FEAT-044c | Paiement — webhook RevenueCat + réconciliation quotidienne (back-end) | ✅ done | account | PR #114 |
| FEAT-044d | Paiement — Stripe Checkout Session web (back-end, ADR 0002 approche A) | ✅ done | account | PR #117 |
| FEAT-044e | Paiement — **intégration client** — web ✅ (paywall `/pro/*` + Stripe Checkout, 75fcbd3) / IAP mobile 📋 (pas de `purchases_flutter`) | 🚧 wip | account | 75fcbd3, docs/plans/FEAT-044-payment-revenuecat-plan.md |
| FEAT-045 | Suppression compte in-app + /delete-account (loi 6/7/1989) | ✅ done | account | PR #69 |
| FEAT-048 | FAQ produit publique /faq | ✅ done | account | PR #69 |
| FEAT-049 | SEO du PWA — quick-wins (Option A) + domaine canonique baillan.com | ✅ done | account | PR #73, #121 |
| FEAT-050 | Site marketing statique crawlable (Option B) | 🚧 v1 construite (bascule domaine en attente) | account | docs/backlog/050-marketing-site-seo.md |
| FEAT-051 | Baillan Pro — annonces & diffusion multi-portails | 💡 idea | properties | discovery PR #98, docs/backlog/051-annonces-diffusion-pro.md |
| FEAT-052 | Feature Readiness Score (`/feature-ready`, advisory) | ✅ done | tooling | PR #100 (`tool/feature_ready.dart`) |
| FEAT-054 | Isolation prod/staging — base Firestore `staging` (web ; Auth/Storage/Functions restent partagés) | ✅ done | account | PR #145 (impl.), PR #140 (cadrage), ADR 0003 |
| FEAT-055 | Comparaison de scénarios de simulation (Pro) | ✅ done | simulator | PR #139 (cadrage), PR #148-#151 (impl. + responsive, 2026-07-24+27) |
| FEAT-056 | Abonnements Pro/Max/Ultra — 3 paliers payants (grille quotas) | 🚧 wip | account, properties, leases, expenses-documents, simulator | branche `feat/056-multi-tier-subscriptions` — back-end callables ✅ (createCheckoutSession, manageSubscription, createScenario) · webhook + cron ✅ · Cloud Functions déployées ✅ · staging rules+indexes ✅ (PR #152 CI) · prod rules/indexes ⏳ (PR #154 non mergé) · Stripe 6 prix test ✅ · RevenueCat 3 entitlements (Pro achetable, Max/Ultra démo) ✅ · client UI Pro 🚧 (FEAT-044e) |
