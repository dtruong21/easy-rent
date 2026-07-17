# Features — registre

> Source d'état — features. Maintenu par state-keeper. Dernière sync : 2026-07-08.

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
| FEAT-017 | (Réserve) | 💡 idea | — | — |
| FEAT-018 | Simulateur investissement | ✅ done | simulator | — |
| FEAT-019 | Migration Supabase → Firebase | ✅ done | account | — |
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
| FEAT-031 | Rappels paiement automatiques (attente infra email) | 📋 planned | payments-receipts | — |
| FEAT-032 | Dashboard — trésorerie graphique (encaissé vs dû) | 📋 planned | dashboard | — |
| FEAT-033 | Archivage régularisations charges (absorbé par 041 V1) | 💡 idea | leases | — |
| FEAT-034 | Import multi-colonnes CSV (properties/tenants/leases) | 📋 planned | properties | — |
| FEAT-035 | 2FA TOTP | 📋 planned | account | — |
| FEAT-036 | Charges récupérables vs non-récupérables (décret 87-713) | ✅ done | leases | PR #66 |
| FEAT-041 | Suivi dépenses unifié V1 (expenses + documents v2) | ✅ done | expenses-documents | PR #67 |
| FEAT-042 | Mode de charges (provisions/forfait) + éligibilité régul. | ✅ done | leases | PR #68 |
| FEAT-043 | Internationalisation FR/EN (i18n, gen_l10n) | ✅ done | account | PR #71 |
| FEAT-044 | Freemium enforcement — plafonds free-tier (2 biens/3 locataires/2 baux) + callables CF-exclusive | ✅ done | properties, leases | PR #91 |
| FEAT-045 | Suppression compte in-app + /delete-account (loi 6/7/1989) | ✅ done | account | PR #69 |
| FEAT-048 | FAQ produit publique /faq | ✅ done | account | PR #69 |
| FEAT-049 | SEO du PWA — quick-wins (Option A) | ✅ done | account | PR #73 |
| FEAT-050 | Site marketing statique crawlable (Option B) | 📋 planned | account | docs/backlog/050-marketing-site-seo.md |
| FEAT-051 | Feature Readiness Score (`/feature-ready`, advisory) | 🚧 wip | tooling | feature/051-feature-readiness-score |
