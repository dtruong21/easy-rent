# Routes Flutter — snapshot

> Maintenu par `state-keeper`. **Source** : `lib/core/router/app_router.dart`. **Dernière sync** : 2026-07-05 (FEAT-023...FEAT-030 ✅ mergées) — landing publique `/`, simulator accessible anonymes, garde 3-états (unauthenticated / anonymous / fullyAuthenticated), shell adaptatif FEAT-026.

## Garde d'accès (redirects)

| SessionState | Landing `/` | Auth forms | Public | Simulator | Métier | Comportement |
|---|---|---|---|---|---|---|
| `unauthenticated` | ✅ Access | ✅ /login/signup/forgot/reset | ✅ /privacy | ❌ Deny | ❌ Deny | → /login |
| `anonymous` | → /simulator | ❌ Deny | ✅ /privacy | ✅ /simulator/:id | ❌ Deny | → /simulator |
| `fullyAuthenticated` | → /dashboard | ❌ Deny | ✅ /privacy | ✅ /simulator/:id | ✅ All métier | — |

**Implémentation** :
- `ref.listen<SessionState>(sessionStateProvider)` → `_RouterRefreshNotifier.refresh()`
- Bypass ancien `GoRouterRefreshStream` (race condition signe-in chaud, commit 07f20a3)
- Riverpod garanti état frais APRÈS intégration du changement

---

## Public Routes

| Route | Page | Transition | Accès | Feature | Notes |
|---|---|---|---|---|---|
| `/` | `LandingPage` | fade | unauthenticated + anonymous | BAILLAN-M1 | Carrefour onboarding (anons → /simulator) |
| `/login` | `LoginPage` | fade | unauthenticated | FEAT-001 | Email + password |
| `/signup` | `SignupPage` | fade | unauthenticated | FEAT-001, FEAT-021 | Email + password + RGPD gate (commit d9ad603) |
| `/forgot-password` | `ForgotPasswordPage` | fade | unauthenticated | — | Demande lien reset |
| `/reset-password` | `ResetPasswordPage` | fade | public (email link) | — | Reste accessible connecté (late-click email) |
| `/privacy` | `PrivacyPage` | fade | public | — | Mentions RGPD + loi 6 juillet 1989 |
| `/terms` | `TermsPage` | fade | public | FEAT-023 | CGU v1.0 (2026-07-03) — liée depuis /profile |

**Notas** :
- `/login` + `/signup` redirigent comptes connectés vers `/dashboard`
- RGPD gate (`signup_form`) : consentement obligatoire au clic (pas pre-checked)
- Landing `/` = première route, accès non-authed + anonymes

---

## Authenticated Routes (compte complet)

### Core Collections

| Route | Page | Transition | Card | Feature |
|---|---|---|---|---|
| `/dashboard` | `DashboardPage` | standard | — | FEAT-010 |
| `/properties` | `PropertiesListPage` | standard | PropertyCard | FEAT-003 |
| `/properties/new` | `PropertyFormPage` | standard | — | FEAT-003 |
| `/properties/:id` | `PropertyDetailPage` | standard | — | FEAT-003 |
| `/properties/:id/edit` | `PropertyEditPage` | standard | — | FEAT-003 |
| `/tenants` | `TenantsListPage` | standard | TenantCard | FEAT-004 |
| `/tenants/new` | `TenantFormPage` | standard | — | FEAT-004 |
| `/tenants/:id` | `TenantDetailPage` | standard | — | FEAT-004 |
| `/tenants/:id/edit` | `TenantEditPage` | standard | — | FEAT-004 |
| `/leases` | `LeasesListPage` | standard | LeaseCard + status pills | FEAT-005 |
| `/leases/new` | `LeaseFormPage` | standard | — | FEAT-005 |
| `/leases/:id` | `LeaseDetailPage` | standard | — | FEAT-005 |
| `/leases/:id/edit` | `LeaseEditPage` | standard | — | FEAT-005 |

### Lease Sub-Routes (Branche 3, FEAT-005...FEAT-030)

| Route | Page | Transition | Feature | Parents |
|---|---|---|---|---|
| `/leases/:id/edit` | `LeaseEditPage` | standard | FEAT-005 | LeaseDetailPage |
| `/leases/:id/payments/new` | `PaymentFormPage` | standard | FEAT-006, FEAT-029 | LeaseDetailPage |
| `/leases/:id/payments/:pid/edit` | `PaymentEditPage` | standard | FEAT-006, FEAT-029 | LeaseDetailPage |
| `/leases/:id/receipts` | `LeaseReceiptsPage` | standard | FEAT-007, FEAT-029 | LeaseDetailPage |

**FEAT-029b (2026-07-04)** : Query param `/leases/:id?action=regularize` ouvre auto dialog charge_regularization (page détail + FEAT-029 button on card/list line).

**FEAT-030 (2026-07-04)** : Navigation retour fixée :
- Formulaires → `pop()` retour fiche (ex. PropertyEditPage → PropertyDetailPage)
- Tuiles Accueil → `push()` (stack conservée)
- Simulateur → `push()` par-dessus shell

### User Routes (Shell, 5 branches FEAT-026)

| Route | Page | Transition | Feature | Branche |
|---|---|---|---|---|
| `/dashboard` | `DashboardPage` | standard | FEAT-010, FEAT-027, FEAT-028 | Accueil |
| `/properties` (+ sub-routes) | `PropertiesListPage` | standard | FEAT-003 | Biens |
| `/tenants` (+ sub-routes) | `TenantsListPage` | standard | FEAT-004 | Locataires |
| `/leases` (+ sub-routes) | `LeasesListPage` | standard | FEAT-005, FEAT-028, FEAT-029b | Baux |
| `/profile` | `ProfilePage` | standard | FEAT-023, FEAT-025, FEAT-025b | Profil |

**FEAT-026 (2026-07-03, commit ca2d10a)** : Navigation shell adaptative — `StatefulShellRoute.indexedStack` 5 branches, état préservé par branche :
- **Desktop** (≥600px) : `NavigationRail` repliable (icônes + libellés compact/étendu, `railExpandedProvider` persisté SharedPreferences)
- **Mobile** (<600px) : `NavigationBar` en bas (5 destinations)
- **Marque** : Logo Baillan en tête (replié : icône / déplié : wordmark)
- Landing/auth/légal/simulateur hors shell (3-états inchangée)
- Référence : [`docs/UX_NAVIGATION.md`](../UX_NAVIGATION.md)

### Profile Sub-Routes (Branche 4, FEAT-025b)

| Route | Page | Notes |
|---|---|---|
| `/profile` | `ProfilePage` | Hub tuiles (détails, password, support, légal, à propos) |
| `/profile/details` | `ProfileDetailsPage` | Identité bailleur (form complet) |
| `/profile/password` | `ChangePasswordPage` | Comptes email only (gate `hasPasswordProvider` + reauthenticateWithPassword) |
| `/profile/support` | `SupportPage` | Formulaire « Nous contacter » → collection `support_requests` create-only (FEAT-025) |

**FEAT-023 (2026-07-03)** : ProfilePage tuiles réglages app :
- Thème Système/Clair/Sombre (`themeModeProvider`, SharedPreferences)
- Liens `/terms` + `/privacy` 
- Bouton déconnexion
- Section « À propos » (version via `package_info_plus` → v1.0.0+BUILD)

---

## Anonymous Routes (essai BAILLAN-M1)

| Route | Page | Transition | Accès | Feature | Notes |
|---|---|---|---|---|---|
| `/simulator` | `SimulatorPage()` | standard | anonymous + fullyAuthenticated | FEAT-018 | CRUD investment_scenarios, pas parent |
| `/simulator/:id` | `SimulatorPage(scenarioId: id)` | standard | anonymous + fullyAuthenticated | FEAT-018 | Edit scénario existant |

**Notas** :
- Anonyme = essai 14j dans `landlords.anonExpiresAt`
- Pas accès collections métier (properties, leases, etc.) — Firestore RLS refuse
- Quit demo dialog : `quit_demo_dialog.dart` + action deconnexion
- Simulateur avant création de compte = route d'engagement maximal (MVP P1)

---

## Session State (3-branch enum)

```dart
enum SessionState {
  unauthenticated,  // Pas de compte Firebase Auth
  anonymous,        // Firebase Auth anonymous (essai 14j)
  fullyAuthenticated; // Email/Google/Apple vérifié
}
```

**Dérivation** (FirebaseAuth + custom claims) :
- `currentUser == null` → unauthenticated
- `currentUser != null && firebase.sign_in_provider == 'anonymous'` → anonymous
- `currentUser != null && !isAnonymous()` → fullyAuthenticated

**Provider** : `lib/features/auth/application/auth_session_provider.dart`
- StreamProvider sur `FirebaseAuth.authStateChanges`
- Cache Firestore Doc `landlords/{uid}` en fallback (loading/error tolerance)

---

## Page Transitions (AppTransition)

```dart
enum AppTransition { fade, standard }
```

Utilisé dans `appPage()` builder (inject animation) :

| Transition | Duration | Cas d'usage |
|---|---|---|
| `fade` | 300ms | Landing ↔ auth forms ↔ privacy (changement radical contexte) |
| `standard` | 400ms | Métier (dashboard, CRUD, navigation hiérarchique) |

**Implementation** : `lib/core/router/transitions.dart` → custom PageBuilder.

---

## RLS Guards (Firestore Rules)

| Collection | Route | RLS Match | CF exclusive | Notes |
|---|---|---|---|---|
| `landlords/{uid}` | /profile | isOwner(uid) | — | Lecture doc self |
| `properties` | /properties* | isFullyAuthed() | — | Anonyme denied |
| `tenants` | /tenants* | isFullyAuthed() | — | Anonyme denied |
| `leases` | /leases* | isFullyAuthed() | ✅ createLease/updateLease/softDeleteLease | Cross-entity FK validation |
| `payments` | /leases/:id/payments* | isFullyAuthed() | ✅ createPayment/updatePayment | Cross-entity, déclenche generateReceipt |
| `receipts` | /leases/:id/receipts | isFullyAuthed() | ✅ generateReceipt/voidReceipt/markSent | Immuable, rétention 5 ans |
| `documents` | (TBD) | isFullyAuthed() | ✅ createDocument/softDeleteDocument | Catégorie → legalHold |
| `investment_scenarios` | /simulator* | isSignedIn() | — | Anonymes + comptes autorisés |

**Défense en profondeur** :
- Client ne crée jamais `deletedAt` (CF exclusive)
- Cross-entity valide FK côté serveur
- Anonyme jamais en mutation métier (RLS refuse)
- Quittances voided restent visibles (audit trail, pas de soft-delete)

---

## Deep Linking (PWA)

| URL | Résolution |
|---|---|
| `https://app.com/` | Landing (public) |
| `https://app.com/simulator/abc123` | Simulator with scenario (anons + comptes) |
| `https://app.com/properties` | Properties list (auth check + redirect unauthenticated) |
| `https://app.com/reset-password?oobCode=...` | Reset form (public, traite code Firebase) |

GoRouter gère navigation native ↔ PWA seamlessly.

---

## Router Provider (Riverpod)

```dart
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.listen<SessionState>(sessionStateProvider, (previous, next) {
    if (previous != next) refreshNotifier.refresh();
  });
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) { ... },
    routes: [ ... ],
  );
});
```

**Fix 2026-07-02** (commit 07f20a3) :
- Problem : `GoRouterRefreshStream(authStateChanges)` perd race — stream notification avant Riverpod state
- Solution : `ref.listen(sessionStateProvider)` — refresh APRÈS intégration
- Test couvrant : `router_auth_refresh_test.dart`

---

## Parameter Passing

| Route | Params | Source | Résolution |
|---|---|---|---|
| `/properties/:id` | `id` | path | state.pathParameters['id']! |
| `/leases/:id/payments/:pid/edit` | `leaseId, paymentId` | paths | state.pathParameters['id']!, state.pathParameters['pid']! |
| `/simulator/:id` | `scenarioId` | path (optional) | state.pathParameters['id'] (null-safe) |

GoRouter resolve path params avant pageBuilder → constructors reçoivent valeurs typées.

---

## Notable Implementation Details

**Landing redesign (FEAT-022)** :
- Renaming `/` : pivot vers public-first (anon → /simulator direct)
- AppAppBar absent Landing (standalone page)
- CTA buttons : créer compte + mode démo

**Simulator back button** :
- Masqué anonymes (commit e339e26)
- Visible comptes (navigation standard)

**RGPD consent gate** :
- SignupForm checkboxes + onChanged validation (commit d9ad603)
- Refuse submission si non-coché
- Cloud Function CF backup (Identity Platform blocking, si activé)

**Retries idempotent** :
- Provider refetch ne re-run CF (cache Firestore 30s)
- Payment/receipt operations tolèrent duplicate CF trigger
