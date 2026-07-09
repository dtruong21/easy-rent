# FEAT-044 — Freemium → Paid: Implementation Plan

> **Statut** : 🧭 Plan d'implémentation (2026-07-09). Complète le cadrage produit [`docs/backlog/044-monetization-freemium.md`](../backlog/044-monetization-freemium.md) (modèle, benchmark, RevenueCat déjà décidés). Ce document rend le modèle **buildable** et fige les décisions ouvertes. Rien n'est encore codé.

Synthesis of four research streams into one buildable, phased plan. The freemium→paid model, RevenueCat choice, and per-account (not per-property) pricing are **already decided** — this plan makes them executable and resolves the open numbers.

---

## 1. TL;DR

- **What:** Convert Baillan from free to freemium. Free tier = **2 properties / 2 active leases / 3 tenants / 500 MB storage**. Paid "Pro" = unlimited + automation features. Enforcement is **server-authoritative** (Cloud Functions), because properties and tenants are currently plain client-side Firestore writes that a modified client can bypass.
- **Resolved price:** **5,99 €/mois TTC** or **49 €/an TTC** (~32 % off, "≈4 mois offerts"), **14-day full-feature trial**, **no lifetime option**. Positioned as "*moitié prix de Rentila, en illimité, un seul prix quel que soit le nombre de biens*."
- **Launch sequence:** **Web/Stripe first** (Phase B) → mobile IAP later with FEAT-024 (Phase C). Web-first is the single biggest margin lever: ~2–3 % Stripe fee vs 15 % store commission. RevenueCat is the entitlement layer from day one (free below $2,500 MTR).
- **Most important build insight:** *Leases are already server-gated via the `createLease` callable; properties and tenants are not.* Phase A's core work is **moving `createProperty`/`createTenant` server-side** and adding **denormalized per-landlord counters maintained transactionally inside the callables** — a hard cap cannot be enforced by Firestore rules (no aggregation, no atomic reserve) or by async triggers (boundary race).
- **Phase A ships with zero payment code** — real revenue capture (Phase B) is gated behind **hard legal blockers**: SIREN/micro-entreprise, CGV, rétractation waiver, and a consumer mediator must exist *before* taking the first euro.
- **Two latent bugs found in the repo — both already fixed (2026-07-09), ahead of Phase A:** (1) `softDeleteEntity` never decremented the parent `activeLeaseCount` on a direct lease soft-delete (property got stuck un-deletable) — fixed + regression test `soft_delete_leases.test.ts`; (2) `SCHEMA.md` said `subscriptionTier == 'pro'` while the code enum uses `'paid'` (the enum is authoritative — the webhook must write `'paid'`) — SCHEMA.md corrected.

---

## 2. Resolved open decisions

| Decision | Recommendation | Rationale | Confidence |
|---|---|---|---|
| **Monthly price** | **5,99 €/mois TTC** | Charm "<6 €"; exactly half of Rentila Gold TTC (9,90 HT = 11,88 TTC) while being *unlimited*. Net after 15 % store = ~4,24 €; after Stripe = ~4,65 € — healthy. 4,90 € would crush margin for no positioning gain. | High |
| **Annual price** | **49 €/an TTC** (~32 % off) | Front-loads cash, cuts churn, store commission applies once/yr not 12×. Beats Rentila Silver (49 €/an but capped at 5 biens) by being unlimited. Push annual-first. | High |
| **Trial length** | **14 days, full-feature, no card** | Matches/beats Rentila (15 j) & BailFacile (7 j). Note: a trial that grants immediate access triggers the rétractation-waiver requirement (§4.3). | High |
| **Lifetime / IAP à vie** | **NO** | Recurring infra cost vs one-time pay → adverse selection; store taxes it 15–30 % up front; destroys MRR/LTV predictability. Substitute if a hook is wanted: limited "Fondateur" annual (e.g. 39 €/an for first N users) — marketing, not a true lifetime. | High |
| **Free-tier storage quota** | **500 MB free / 10 GB Pro** | 10× Rentila's 50 MB → direct marketing line. Covers 2 biens + photo EDL (5–20 MB is the heavy item). Infra cost ~6,5 $/mo per 1 000 free users on Blaze — negligible. ⚠️ Assumes Firebase Blaze / paid tier (consistent with FEAT-019 pivot). | Med-High |
| **Free count caps** | **2 properties / 2 active leases / 3 tenants** | Lets a colocation of 3 through on 2 biens/leases. "Active" = `deletedAt == null` (properties/tenants) and `deletedAt == null && status == 'active'` (leases). | Med (product call) |

---

## 3. Phased build plan

### Phase A — Free-tier enforcement (buildable NOW, zero payment integration)

**Goal:** Make the free caps real and unbypassable, server-side, and capture upgrade intent via a "coming soon" paywall — all before any billing exists.

**Dependencies:** none. Ships independently. Every account today is `'free'`/`'anonymous'`, so caps apply to everyone the moment this lands (see grandfathering below).

**Tasks:**

1. **Extend `SubscriptionTier`** — `lib/features/auth/domain/subscription_tier.dart`. Add getters mirroring `scenarioLimit` (`null` = unlimited, anonymous = most-restrictive `0`):
   - `int? get propertyLimit` → anonymous 0, free 2, paid null
   - `int? get activeLeaseLimit` → anonymous 0, free 2, paid null
   - `int? get activeTenantLimit` → anonymous 0, free 3, paid null
   - Mirror as TS constants in CF: `FREE_PROPERTY_LIMIT=2`, `FREE_ACTIVE_LEASE_LIMIT=2`, `FREE_ACTIVE_TENANT_LIMIT=3`.

2. **Add denormalized counters** to `landlords/{uid}` (client read-only, server-maintained): `activePropertiesCount`, `activeTenantsCount`, `activeLeasesCount` (all `int`).
   - Initialize `= 0` at every provisioning site: `auth_repository.dart` signup (~L503-517), Google link (~L662), Apple link (~L775), anonymous (~L817); and `functions/src/callable/finalize_anonymous_upgrade.ts:115` (`tx.update`).
   - **One-off backfill script** (Admin SDK) recomputing counts from live queries for existing docs.

3. **CREATE two callables** — new file `functions/src/callable/property_tenant.ts`: `createProperty` and `createTenant`. Each runs `db.runTransaction`, reads `landlords/{uid}` for `subscriptionTier` + counter, **gates** (`if tier !== "paid" && count >= LIMIT throw new HttpsError("resource-exhausted", ...)`), then `tx.set(entity)` + `tx.update(landlord, {counter: FieldValue.increment(1)})` **in the same transaction** (atomic slot reservation — this is what makes the cap race-safe). Signatures mirror the current client `create()` payloads. Add `readOnly: false` to the property payload (see Phase C downgrade).

4. **Migrate the client repos** from direct `docRef.set()` to `httpsCallable`:
   - `property_repository.dart:274` → call `createProperty` (same pattern as `archive()` → `softDeleteEntity` at `:348`).
   - `tenant_repository.dart:150` → call `createTenant`.

5. **MODIFY three callables:**
   - `createLease` (`lease_payment.ts:191-244`): load `landlords/{uid}`; when `status=='active'`, gate on `activeLeasesCount`; add `tx.update(landlordRef, {activeLeasesCount: increment(1)})` alongside the existing property/tenant `activeLeaseCount` increments.
   - `updateLease` (`lease_payment.ts:337,393`): reuse existing `delta`; when `delta !== 0` also increment landlord `activeLeasesCount`; re-check the cap on reactivation (`delta==+1`).
   - `softDeleteEntity` (`soft_delete.ts`): the property/tenant `activeLeaseCount` decrement on active-lease soft-delete is **✅ already done (2026-07-09)** — only the *landlord-level* `activeLeasesCount` decrement remains (add a `leases` branch that also decrements the landlord counter). Idempotency already guaranteed by the `deletedAt != null` short-circuit.

6. **Firestore rules defense-in-depth** (`firestore.rules`): flip `properties` (line 175) and `tenants` (line 205) to `allow create: if false` (now CF-exclusive, like leases at line 239). Keep `update` allowed for owners but block mutation of `activeLeaseCount` and `readOnly`, and block edits when `readOnly == true`.

7. **Client gate UI** mirroring `scenario_limit_controller.dart`: live `activePropertiesCountProvider` / `…Tenants` / `…Leases` StreamProviders + `canCreateProperty/Tenant/Lease` providers (fail-safe to most-restrictive on load) → disable "add" buttons at cap.

8. **"Coming soon" paywall** — reuse the **already-wired** `PaidPlanInterestRepository.markInterest({features, email})` + existing `coming_soon_paid_plan_section` / `scenario_limit_reached_modal` widgets. When a create is blocked, map `resource-exhausted` → upgrade sheet that captures interest into `paid_plan_interest/{uid}`. Zero billing, captures demand.

9. **Dormant downgrade scaffolding** (build now, inert until someone is `'paid'`): add `readOnly: bool` field + the `onLandlordTierChange` trigger (see Phase C) — no-op today because nobody downgrades yet.

**Acceptance criteria:**
- A modified/scripted client cannot create a 3rd property, 3rd active lease, or 4th tenant on a free account (verified by calling the callable directly and by direct Firestore write attempt → both rejected).
- Two concurrent create requests at the boundary → exactly one succeeds, one gets `resource-exhausted` (transaction retry proves the reserve is atomic).
- Counters stay consistent through create → soft-delete → recreate cycles; backfill matches live counts; the `activeLeaseCount` decrement bug no longer drifts.
- **Legal guard-rail verified:** `createPayment`/`generateReceipt`/`markReceiptAsSent`/`createDocument`/`deleteAccount` are **never** gated (art. 21 loi 6/7/1989 — issuing a quittance on an existing lease must always work). Cap gates *creating a new active lease* only.
- Blocked create surfaces the interest-capture paywall and writes to `paid_plan_interest`.

**Grandfathering (product sign-off before shipping):** existing free accounts with >2 properties keep full edit access and simply can't add more (never restrict retroactively — legally safest). `readOnly` is only stamped on a *real* paid→free downgrade. Confirm acceptable, or add an explicit `grandfathered: true` flag.

---

### Phase B — Web paid launch (Stripe first)

**Goal:** Take real money on the web/PWA at ~2–3 % fee, unlock unlimited via RevenueCat entitlement. **Store-billing research explicitly supports launching web-before-mobile** — "every euro collected on web is a euro that never pays store commission."

**Dependencies:** Phase A shipped **and** all **hard legal blockers in §4 done** (SIREN, CGV, rétractation waiver, mediator, compliant invoicing). Do not take a euro before these.

**Tasks:**
1. RevenueCat account + project; model the "Pro" entitlement (free below $2,500 MTR; 1 % of gross above).
2. RevenueCat **Web Billing** (Stripe-backed) or Stripe Checkout direct — [verify at build time] which gives better net (Stripe EU card ≈ 1,5 % + 0,25 €; SEPA Direct Debit ≈ 0,8 % + 0,30 € — cheaper for recurring FR subs; Stripe Billing +~0,7 %, Stripe Tax +~0,5 %). Sources: [Stripe FR](https://affonso.io/resources/stripe-fee-calculator/france), [SEPA](https://feetrace.com/blog/stripe-sepa-direct-debit-fees-for-saas-in-2026).
3. **`revenueCatWebhook` CF** (`functions/src/callable/revenuecat_webhook.ts`): validate RC signature, flip `landlords/{uid}.subscriptionTier` between `'paid'` and `'free'`. This is the **only** writer of `'paid'`; Firestore tier stays the single source of truth for the Phase A gates. **Must write `'paid'` (not `'pro'`)** — enum is authoritative.
4. Replace the "coming soon" paywall with a **real checkout** paywall (annual-first, monthly fallback). Price 5,99/49 TTC.
5. Pricing engine must allow a **TVA rate/line to be switched on later** without re-architecting (franchise crossover — §4.1).

**Acceptance criteria:** a web purchase flips the tier to `'paid'` via webhook (not client); caps lift immediately (unlimited); cancellation flips back to `'free'` and triggers the downgrade path; entitlement resolves via RevenueCat cross-platform; TVA line can be toggled by config.

**Commission advantage to note:** web nets ~4,65 €/mo (Stripe) vs ~4,24 €/mo (mobile 15 % SBP) — annual on web is the most profitable channel by far.

---

### Phase C — Mobile IAP (with/after FEAT-024)

**Goal:** Offer IAP on iOS/Android via RevenueCat as a *convenience* path, not the only one.

**Dependencies:** FEAT-024 (mobile app), Phase B entitlement layer.

**Tasks:**
1. Enroll **Apple Small Business Program** (15 % from day one, <$1M proceeds) and **Google's reduced tier** (15 % with Play Billing; EEA rollout live since 30 Jun 2026 — [verify France timing](https://android-developers.googleblog.com/2026/06/play-expanded-billing.html)). Sources: [Apple SBP](https://developer.apple.com/app-store/small-business-program/), [RevenueCat 15 %](https://www.revenuecat.com/blog/engineering/small-business-program/).
2. Add StoreKit / Play Billing products in RevenueCat (config change, not a rewrite, since RC is already the entitlement layer). Webhook already handles lifecycle.
3. **Downgrade → read-only** (now live, previously dormant): `onLandlordTierChange = onDocumentWritten("landlords/{uid}")` in `functions/src/triggers/tier_readonly.ts`. On **paid→free** with `activePropertiesCount > 2`: stamp `readOnly=true` on the newest `(count−2)` properties (`orderBy(createdAt DESC)`), never touch `deletedAt`. On **→paid**: clear all `readOnly`. Effects: rules block edits; `createLease` refuses a *new* lease on a read-only property; existing leases keep generating quittances (legal guard-rail); UI shows read-only card + upgrade nudge. Async trigger is fine here (not latency-sensitive; creating *more* is already blocked by the Phase A gate).
4. **Steering (margin optimizer, no store permission needed):** convert users on the **PWA before install**, then unlock the app via RC entitlement (multiplatform exception 3.1.3(b), valid because IAP is also offered). Do **not** rely on the reader-app exception — Baillan is a business tool, it doesn't apply.

**Acceptance criteria:** an IAP purchase grants the same `'paid'` entitlement as web; a cross-platform user who bought on web is Pro in the app; a real cancellation exercises the read-only downgrade correctly (oldest 2 stay editable, quittances on existing leases still work).

---

### Phase D — Pro-only feature gating

**Goal:** Wire automation features to the paid entitlement.

**Dependencies:** Phase B (a real `'paid'` tier must exist).

**Tasks:** gate behind `tier == 'paid'` (server-checked in the relevant callables, mirrored in UI): **rappels/reminders (FEAT-031)**, **exports FEC / 2044**, **multi-user**, **régularisation charges archiving (FEAT-033)**. Reuse the same fail-safe tier-provider pattern from Phase A. Each gated action must degrade gracefully to an upgrade nudge, never to data loss.

**Acceptance criteria:** each feature is inaccessible on free (server-enforced, not just UI-hidden); accessible immediately on upgrade; and none of the RGPD/legal-mandatory actions (export of *own* data, receipts) are ever behind the gate.

---

## 4. Legal & tax prerequisites

**Hard blockers before Phase B (taking real money) are marked 🔴.** Sources inline.

| # | Obligation | What MUST be done | Indicative cost | Blocker? |
|---|---|---|---|---|
| 0 | **Micro-entreprise registration + SIREN** | Register on INPI guichet unique; obtain SIREN (needed on every invoice & in CGV). Confirm mentions légales / LCEN éditeur identification in place. | €0 | 🔴 |
| 1 | **TVA franchise en base** | Stay ≤ **37 500 €** base / **41 250 €** majoré for services (single 25 000 € threshold was **repealed** 3 Nov 2025 — historic thresholds apply for 2026). Invoices carry **"TVA non applicable, art. 293 B du CGI"**. Build the pricing engine so a 20 % TVA line can switch on at crossover. [service-public A17995](https://entreprendre.service-public.gouv.fr/actualites/A17995) · [economie.gouv.fr](https://www.economie.gouv.fr/entreprises/gerer-sa-fiscalite-et-ses-impots/autres-impots-et-taxes/entreprises-pouvez-vous-beneficier-de-la-franchise-de-tva) | €0 | ⚠️ (arch. now, switch later) |
| 2 | **CGV B2C** | Publish CGV with all mandatory clauses (identity+SIREN, prix TTC, durée, tacite reconduction, rétractation, garanties, médiateur, droit applicable); require **active acceptance** before order (L111-1, L221-5). [F33527](https://entreprendre.service-public.gouv.fr/vosdroits/F33527) · [L221-5](https://www.legifrance.gouv.fr/codes/section_lc/LEGITEXT000006069565/LEGISCTA000032221365/) | €0 DIY / 300–1 500 € lawyer | 🔴 |
| 3 | **Rétractation 14 j + immediate-access waiver** | 14-day right (L221-18) applies. To allow instant use/trial: **unchecked, separate checkbox** — express request to begin + explicit renunciation (L221-25 / L221-28 13°); pre-ticked is invalid; **timestamp/log consent**. [verify] ord. **2026-2** mandatory online "fonction de rétractation" button (~19 Jun 2026) — build a one-click withdrawal control if it applies. [economie.gouv.fr](https://www.economie.gouv.fr/particuliers/vente-distance-droit-retractation) · [ord. 2026-2](https://www.village-justice.com/articles/fonction-retractation-ligne-entre-vigueur-juin-2026-que-change-ordonnance-2026,57910.html) | dev time | 🔴 |
| 4 | **Médiation de la consommation (L612-1)** | Enroll with an approved mediator (CM2C, MEDICYS…); display name/address/site in CGV + site + link to directory. Penalty €3 000/€15 000 for non-enrollment. [F33338](https://entreprendre.service-public.gouv.fr/vosdroits/F33338) | ~30–150 €/yr | 🔴 |
| 5 | **Chatel + résiliation 3-clics (L215-1 / L215-1-1)** | Renewal-reminder emails 3–1 month prior; permanently accessible online **"Résilier mon contrat"** function — no forced account, summary screen, email confirmation on durable medium. Web **and** app. Penalty up to €15 000/€75 000. [INC L215-1-1](https://www.inc-conso.fr/content/vous-pouvez-resilier-votre-contrat-dabonnement-en-quelques-clics) | dev time | 🔴 (for auto-renew) |
| 6 | **Facturation / e-invoicing** | Issue compliant invoices now (SIREN, n°, description, franchise mention). Be able to **receive** e-invoices by **1 Sept 2026** (applies to micro under franchise too); **issue**+e-report B2B by **1 Sept 2027**; pick a **PDP** [verify cost + B2C e-reporting]. Penalty €15/invoice, cap €15 000/yr. [economie.gouv.fr](https://www.economie.gouv.fr/tout-savoir-sur-la-facturation-electronique-pour-les-entreprises) | PDP fee (verify) | 🔴 (compliant invoicing) |
| 7 | **RGPD / CNIL (payments)** | Accept **Stripe & RevenueCat DPAs** (art. 28); update privacy policy (sub-processors, purposes, retention, US transfers via SCC/DPF); add paid processing to registre des traitements; tokenize card data via Stripe hosted fields (PCI burden stays with Stripe). [verify] RevenueCat's own sub-processor chain. [CNIL sous-traitant](https://www.cnil.fr/sites/cnil/files/atoms/files/rgpd-guide_sous-traitant-cnil.pdf) · [Stripe DPA](https://stripe.com/legal/dpa) | €0 DPAs + dev/legal | 🔴 |

**Cross-cutting:** compliant cookie/consent banner if analytics are added on the paid funnel.

---

## 5. Data model & API changes (consolidated)

**`landlords/{uid}` — new fields:**
- `activePropertiesCount: int` (server-maintained, client read-only)
- `activeTenantsCount: int`
- `activeLeasesCount: int`
- `subscriptionTier`: existing — values `'anonymous' | 'free' | 'paid'` (**`'paid'`, NOT `'pro'`**). Only `revenueCatWebhook` writes `'paid'`.
- *(optional)* `grandfathered: bool` if product wants explicit over-cap tagging.

**`properties/{id}` — new field:** `readOnly: bool` (default `false`; set by `onLandlordTierChange` on downgrade).

**New collections:** none required by enforcement. `paid_plan_interest/{uid}` already exists and is reused for the Phase A paywall.

**Cloud Functions:**

| Function | Status | Signature / behavior |
|---|---|---|
| `createProperty` | **NEW** (`property_tenant.ts`) | `(data) → {propertyId}`. Txn: read landlord tier+`activePropertiesCount`, gate (`resource-exhausted` if free & ≥2), `tx.set` property + `increment(activePropertiesCount)`. Sets `readOnly:false`. |
| `createTenant` | **NEW** (`property_tenant.ts`) | `(data) → {tenantId}`. Same shape, `activeTenantsCount` / limit 3. |
| `createLease` | **MODIFY** (`lease_payment.ts`) | Add landlord read + active-lease gate (limit 2) + `increment(activeLeasesCount)` when `status=='active'`. |
| `updateLease` | **MODIFY** (`lease_payment.ts`) | Apply `delta` to `activeLeasesCount`; re-check cap on reactivation. |
| `softDeleteEntity` | **MODIFY** (`soft_delete.ts`) | Decrement landlord counter by type; decrement property/tenant `activeLeaseCount` on active-lease delete (**fixes drift bug**). Idempotent via `deletedAt` short-circuit. |
| `finalizeAnonymousUpgrade` | **MODIFY** | Init the 3 counters to 0 in the anon→free `tx.update`. |
| `onLandlordTierChange` | **NEW trigger** (`tier_readonly.ts`) | `onDocumentWritten("landlords/{uid}")`. paid→free: stamp `readOnly` on newest `(count−2)` properties. →paid: clear all. Built dormant in Phase A, active in Phase C. |
| `revenueCatWebhook` | **NEW** (Phase B) | Validate RC signature → set `subscriptionTier` `'paid'`/`'free'`. Only writer of `'paid'`. |

**Firestore rules deltas:** `properties` & `tenants` → `allow create: if false` (CF-exclusive); block client mutation of `activeLeaseCount` and `readOnly`; block `update` when `resource.data.readOnly == true`. Leases already `create,update,delete: if false`.

**Enum:** `SubscriptionTier` gains `propertyLimit` / `activeLeaseLimit` / `activeTenantLimit` getters; TS mirror constants in CF must equal them.

---

## 6. Risks & things to verify at build time

- **Counter-consistency races** — mitigated by transactional maintenance inside callables (atomic reserve). Triggers are *not* the gate. Add a scheduled reconciler (recompute from live queries) as a non-load-bearing drift healer. Verify the backfill matches before flipping rules to `create: if false`.
- **`softDeleteEntity` drift bug** — ✅ fixed 2026-07-09 (property/tenant `activeLeaseCount` now decrements on active-lease soft-delete, with regression test). The *landlord-level* counter must follow the same pattern when Phase A adds it.
- **`'paid'` vs `'pro'` mismatch** — webhook must write `'paid'`; a wrong value silently leaves users capped. (SCHEMA.md corrected 2026-07-09.)
- **Grandfathering** — existing over-cap free accounts; confirm the "block new / never retro-restrict" behavior with product before shipping caps to all live users.
- **Storage quota assumes Blaze / paid tier** — 500 MB/user requires the FEAT-019 Firebase billing to be live before promising it.
- **TVA threshold volatility** — a future finance law could revive a lower threshold; keep the TVA-line switch ready. Re-check before launch.
- **Store-commission / DMA volatility** — US linked-out commission % (Epic v. Apple remand → SCOTUS) unsettled; Apple EU CTF sunset & exact DMA fee stack in flux; Google fee-restructure France timing (EEA covered from 30 Jun 2026, France specifically [verify]). Affects Phase C only — web-first insulates the launch.
- **RevenueCat Web Billing fee** — verify RC Web Billing's own fee vs Stripe-direct math before choosing the Phase B checkout.
- **Stripe Billing/Tax add-on %** and **PDP choice/cost + B2C e-reporting** — verify current numbers.
- **ord. 2026-2 withdrawal-button** scope/date — build a one-click withdrawal control if confirmed applicable.

---

## 7. Recommended immediate next step

**Build the server-side `createProperty` callable + the `activePropertiesCount` counter, end-to-end** — the thinnest vertical slice of Phase A:

1. Add `activePropertiesCount: int = 0` init at all landlord-provisioning sites + backfill existing docs.
2. Write `createProperty` in `functions/src/callable/property_tenant.ts` (transactional gate + increment).
3. Migrate `property_repository.dart:274` from `docRef.set()` to `httpsCallable('createProperty')`.
4. Flip `properties` rule (`firestore.rules:175`) to `allow create: if false`.
5. Prove the cap: scripted/direct-write 3rd property → rejected; concurrent boundary create → exactly one succeeds.

This slice de-risks the entire architecture (moving a client write server-side + transactional counter maintenance) on the single most-used entity, with **zero payment code and no legal blockers**. Tenants, leases, UI gating, and the interest-capture paywall then follow the same proven pattern.
