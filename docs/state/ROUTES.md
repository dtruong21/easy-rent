# Routes Flutter & Navigation — snapshot

> Maintenu par `state-keeper`. **Source** : `lib/core/router/app_router.dart`. **Dernière sync** : 2026-07-09 (FEAT-045 i18n + FEAT-048 + FEAT-041 merged ; 50+ routes, 3-state guard stable). **Pivot** : FEAT-026 (StatefulShellRoute.indexedStack 5 branches) + FEAT-030 (navigation fixes).

## Architecture Navigation

**Système** : GoRouter 14.6.0 (nested routing avec StatefulShellRoute)

**Gardiennage** : 3-states (unauthenticated / anonymous / fullyAuthenticated) via `sessionStateProvider` (Riverpod StreamProvider)

**Shell** : StatefulShellRoute.indexedStack 5 branches (Accueil / Biens / Locataires / Baux / Profil) — accessibles uniquement fullyAuthenticated (anonyme redirigé)

**Transitions** : AppTransition.standard (slide) ou AppTransition.fade (auth forms)

---

## Routes Publiques (hors shell)

| Chemin | Page | Transition | Guard | Notes |
|---|---|---|---|---|
| `/` | LandingPage | fade | unauthenticated OR anonyme → redir `/simulator` | Carrefour onboarding |
| `/login` | LoginPage | fade | !fullyAuthenticated | Email/password + Google/Apple signup |
| `/signup` | SignupPage | fade | !fullyAuthenticated | Nouvelles inscriptions + RGPD gate |
| `/forgot-password` | ForgotPasswordPage | fade | public | Réinitialisation mot de passe |
| `/reset-password` | ResetPasswordPage | fade | public | Lien email-reset |
| `/privacy` | PrivacyPage | fade | public | Politique confidentialité (v1.2, loi 6 juillet 1989) |
| `/terms` | TermsPage | fade | public | CGU (v2-2026-07, FEAT-023) |
| `/delete-account` | DeleteAccountRequestPage | fade | public (anonyme inclus) | **FEAT-045** — URL Google Play « Account deletion » ; adapte le CTA à la session (login / go profil / suppression essai anonyme) |
| `/faq` | FaqPage | fade | public (anonyme inclus) | **FEAT-048** — questions fréquentes produit (ExpansionTiles), aussi accessible via Profil → Aide |

---

## Routes Shell (5 branches, fullyAuthenticated only)

### Branche 0 : Dashboard (Accueil)

| Chemin | Page | Transition | Type | Notes |
|---|---|---|---|---|
| `/dashboard` | DashboardPage | standard | read | KPI cards (loyers encaissés, retards, charges) + CTA (Simulateur, Charges) |

---

### Branche 1 : Properties (Biens, FEAT-003)

| Chemin | Page | Transition | Type | Notes |
|---|---|---|---|---|
| `/properties` | PropertiesListPage | standard | read | Listage biens (grid/table toggleable FEAT-012) |
| `/properties/new` | PropertyFormPage | standard | write | Créer bien |
| `/properties/:id` | PropertyDetailPage | standard | read | Fiche bien (détail, liens baux, onglet dépenses) |
| `/properties/:id/edit` | PropertyFormPage | standard | write | Éditer bien |
| **`/properties/:id/expenses`** | **PropertyExpensesPage** | standard | read | **NEW FEAT-041a — Listage dépenses bien** |
| **`/properties/:id/expenses/new`** | **ExpenseFormPage** | standard | write | **NEW FEAT-041a — Créer dépense (pré-remplissage leaseId via extra)** |
| **`/properties/:id/expenses/:eid/edit`** | **ExpenseEditPage** | standard | write | **NEW FEAT-041a — Éditer dépense** |

**Notes FEAT-041** :
- `/properties/:id/expenses/new?leaseId=xxx` : pré-remplissage depuis fiche bail (state.extra)
- PropertyExpensesPage : onglet dépenses accessible depuis PropertyDetailPage
- Flux : Dashboard → drill-down property → onglet dépenses → `/expenses` → `new` ou `:eid/edit`

---

### Branche 2 : Tenants (Locataires, FEAT-004)

| Chemin | Page | Transition | Type | Notes |
|---|---|---|---|---|
| `/tenants` | TenantsListPage | standard | read | Listage locataires |
| `/tenants/new` | TenantFormPage | standard | write | Créer locataire (optionnel `?picker=1` → pop tenantId au lieu de go `/tenants`) |
| `/tenants/:id` | TenantDetailPage | standard | read | Fiche locataire |
| `/tenants/:id/edit` | TenantEditPage | standard | write | Éditer locataire |

---

### Branche 3 : Leases (Baux, FEAT-005) + Payments (FEAT-006) + Receipts (FEAT-007)

| Chemin | Page | Transition | Type | Notes |
|---|---|---|---|---|
| `/leases` | LeasesListPage | standard | read | Listage baux (filter drill-down via `?filter=active\|renewable\|late`) |
| `/leases/new` | LeaseFormPage | standard | write | Créer bail |
| `/leases/:id` | LeaseDetailPage | standard | read | Fiche bail (`?action=regularize` auto-ouvre dialog FEAT-030) |
| `/leases/:id/edit` | LeaseEditPage | standard | write | Éditer bail (FEAT-036 : chargesAmountCents + nonRecoverableChargesCents) |
| `/leases/:id/payments/new` | PaymentFormPage | standard | write | Créer paiement (FEAT-029 : notes motif) |
| `/leases/:id/payments/:pid/edit` | PaymentEditPage | standard | write | Éditer paiement |
| `/leases/:id/receipts` | LeaseReceiptsPage | standard | read | Quittances bail (FEAT-007, generate + share + archive) |

---

### Branche 4 : Profile (Profil, FEAT-025b)

| Chemin | Page | Transition | Type | Notes |
|---|---|---|---|---|
| `/profile` | ProfilePage | standard | read | Hub réglages — ordre 2026-07-07 : Compte (détails, mot de passe, **suppression**) / Apparence / Aide (**FAQ**, contact, légal) / À propos / Session |
| `/profile/details` | ProfileDetailsPage | standard | write | Email/fullName (FEAT-025, immutables) |
| `/profile/password` | ChangePasswordPage | standard | write | Changement mot de passe (reauthenticateWithPassword + updatePassword, gated hasPasswordProvider) |
| `/profile/support` | SupportPage | standard | write | Formulaire contact (FEAT-025, collection `support_requests`) |
| `/profile/delete-account` | DeleteAccountPage | standard | write | **FEAT-045** — suppression de compte (re-auth par provider + révocation Apple + callable `deleteAccount` ; rétention quittances annoncée) |

---

## Routes hors Shell (plein écran, BAILLAN-M1)

### Simulateur (FEAT-018)

| Chemin | Page | Transition | Type | Guard | Notes |
|---|---|---|---|---|
| `/simulator` | SimulatorPage | standard | CRUD | unauthenticated OR anonymous OR fullyAuthenticated | Simulateur investissement (accessible anonymes, essai 14j) |
| `/simulator/:id` | SimulatorPage(scenarioId) | standard | CRUD | (idem) | Édition scénario |

**Comportement** :
- Anonyme redirigé landing → `/simulator` (seul accès métier)
- Compte complet peut `push()` par-dessus shell (simulateur modal, retour via pop)
- Scenarios persistés (investment_scenarios collection, landlordId=uid invariant)

---

## Paramètres de Route (GoRouter patterns)

| Route | Param | Type | Notes |
|---|---|---|---|
| `/properties/:id` | id | string (UUID) | Property UUID |
| `/properties/:id/expenses/:eid/edit` | id, eid | string | Property UUID, Expense UUID (FEAT-041) |
| `/tenants/:id` | id | string (UUID) | Tenant UUID |
| `/leases/:id` | id | string (UUID) | Lease UUID |
| `/leases/:id?action=regularize` | action (query) | string | Query param : 'regularize' → auto-ouvre dialog (FEAT-030) |
| `/leases/:id/payments/:pid/edit` | id, pid | string | Lease UUID, Payment UUID |
| `/simulator/:id` | id | string (UUID) | Scenario UUID |
| `/tenants/new?picker=1` | picker (query) | '1' | Picker mode → pop tenantId au lieu go |
| `/properties/:id/expenses/new?leaseId=xxx` | leaseId (extra) | string | Pré-remplissage depuis fiche bail (state.extra, FEAT-041) |

---

## Stratégie Redirect (sessionStateProvider)

**Source** : `lib/core/router/app_router.dart`, fonction `redirect()` + listener `sessionStateProvider`.

**Implémentation** :
```dart
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.listen<SessionState>(sessionStateProvider, (prev, next) {
    if (prev != next) refreshNotifier.refresh();
  });
  
  return GoRouter(
    redirect: (context, state) {
      final sessionState = ref.read(sessionStateProvider);
      final location = state.matchedLocation;
      
      const publicRoutes = {'/login', '/signup', '/forgot-password', '/reset-password', '/privacy', '/terms'};
      final isAnonAccessible = location == '/simulator' || location.startsWith('/simulator/');
      
      switch (sessionState) {
        case SessionState.unauthenticated:
          if (location == '/') return null; // landing OK
          if (publicRoutes.contains(location)) return null;
          return '/login';
        
        case SessionState.anonymous:
          if (location == '/') return '/simulator';
          if (publicRoutes.contains(location)) return null;
          if (isAnonAccessible) return null;
          return '/'; // toute route métier → landing
        
        case SessionState.fullyAuthenticated:
          if (location == '/') return '/dashboard';
          if (location == '/login' || location == '/signup') return '/dashboard';
          return null;
      }
    },
  );
});
```

**Logique** :
1. **unauthenticated** (pas login) → `/login` (sauf landing + public routes)
2. **anonymous** (BAILLAN-M1 essai 14j) → `/simulator` seul accès métier (landing redir)
3. **fullyAuthenticated** (email/password/Google/Apple) → accès shell + toutes routes

**Tuteur de refresh** : `ref.listen(sessionStateProvider)` déclenche redirect re-évaluation immédiate post-auth (fix race condition commit 07f20a3, FEAT-030).

---

## Shell Adaptatif (FEAT-026)

**Type** : StatefulShellRoute.indexedStack (5 branches)

**Responsive** :
- **<600px** : NavigationBar bottom (5 destinations, labels + icônes)
- **≥600px** : NavigationRail left (icônes, compact ou libellés + icônes, railExpandedProvider)

**Persistence** :
- `railExpandedProvider` (SharedPreferences) : état NavigationRail expanded/collapsed
- État branche préservé automatique (indexedStack)

**Branding** : Logo Baillan en tête (réplié : icône / déplié : wordmark)

**Ref** : [`docs/UX_NAVIGATION.md`](../UX_NAVIGATION.md)

---

## Deep Linking & External Navigation

**Web URLs standards** :
- `https://easyrent.app/` → landing
- `https://easyrent.app/login` → login
- `https://easyrent.app/dashboard` → dashboard (fullyAuthenticated)
- `https://easyrent.app/properties/abc123` → fiche bien
- `https://easyrent.app/leases/xyz789?action=regularize` → fiche bail + auto-ouvre régularisation
- `https://easyrent.app/simulator` → simulateur (accessible anonymes)

**Email links** : `/reset-password?token=...` (token extraction via state.uri.queryParameters)

**Firebase Dynamic Links** : À implémenter (passthrough → URLs standard)

---

## Transitions personnalisées

**Fichier** : `lib/core/router/transitions.dart`

| Transition | Animation | Durée | Usage |
|---|---|---|---|
| `AppTransition.standard` | Slide (bottom → top, 200ms) | 200ms | Nested routes (shell + métier) |
| `AppTransition.fade` | Fade (opacity 0→1, 150ms) | 150ms | Auth forms (landing, login, signup) |

---

## Navigation State Management (Riverpod)

### railExpandedProvider (FEAT-026)

**Persistent** : SharedPreferences

**Type** : StateProvider<bool>

**Usage** : NavigationRail expanded/collapsed state (≥600px)

**Défaut** : true (expanded)

---

### chartPeriodProvider (FEAT-027)

**Persistent** : SharedPreferences

**Type** : StateProvider<int>

**Usage** : Dashboard chart period (6/12/24 months)

**Défaut** : 12 (months)

---

### themeModeProvider (FEAT-023)

**Persistent** : SharedPreferences

**Type** : StateProvider<ThemeMode>

**Usage** : Thème (System / Light / Dark)

**Défaut** : ThemeMode.system

---

## Erreurs d'Accès (Auth Guard)

| Condition | Redirect | Code |
|---|---|---|
| unauthenticated + non-public | `/login` | RED-001 |
| anonymous + non-accessible | `/` | RED-002 |
| fullyAuthenticated + `/login` | `/dashboard` | RED-003 |

---

## Checklist Navigation (QA FEAT-030)

✅ Formulaires (`new`, `edit`) → `pop()` au succès (retour fiche, pas liste)
✅ Tuiles Accueil → `push()` (stack conservée, peut revenir Accueil)
✅ Bouton Profil → retiré fiche bail (contradictoire avec stack)
✅ Simulateur → `push()` par-dessus shell (plein écran, pas remplacement)
✅ Drill-down KPI dashboard → `/leases?filter=late` (préselection)
✅ `/leases/:id?action=regularize` → auto-ouvre dialog (pas de subroute)

---

## Summary — Routes par Feature

| Feature | Routes | Count | Status |
|---|---|---|---|
| **FEAT-001** (Auth) | /login, /signup, /forgot-password, /reset-password | 4 | ✅ |
| **FEAT-003** (Properties) | /properties, /properties/new, /properties/:id, /properties/:id/edit | 4 | ✅ |
| **FEAT-004** (Tenants) | /tenants, /tenants/new, /tenants/:id, /tenants/:id/edit | 4 | ✅ |
| **FEAT-005** (Leases) | /leases, /leases/new, /leases/:id, /leases/:id/edit | 4 | ✅ |
| **FEAT-006** (Payments) | /leases/:id/payments/new, /leases/:id/payments/:pid/edit | 2 | ✅ |
| **FEAT-007** (Receipts) | /leases/:id/receipts | 1 | ✅ |
| **FEAT-018** (Simulator) | /simulator, /simulator/:id | 2 | ✅ |
| **FEAT-023** (Settings) | /terms, /privacy | 2 | ✅ |
| **FEAT-025** (Support) | /profile/support | 1 | ✅ |
| **FEAT-025b** (Profile Hub) | /profile, /profile/details, /profile/password | 3 | ✅ |
| **FEAT-045** (Suppression compte) | /delete-account, /profile/delete-account | 2 | ✅ |
| **FEAT-026** (Shell Nav) | Shell wrapper (5 branches) | — | ✅ |
| **FEAT-027** (Dashboard) | /dashboard | 1 | ✅ |
| **FEAT-029** (Charges) | — (payment.notes field) | — | ✅ |
| **FEAT-030** (Navigation Fix) | Tuning redirect + transitions | — | ✅ |
| **FEAT-041a** (Expenses) | **/properties/:id/expenses, /properties/:id/expenses/new, /properties/:id/expenses/:eid/edit** | **3** | **✅** |
| **FEAT-041b** (Documents v2) | (intégré createDocument) | — | ✅ |

**Total** : 33+ named routes, ~45+ GoRouter routes avec nested paths.
