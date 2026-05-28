# Plan — [FEAT-001] Authentification magic link

> Statut : **plan technique** (aucun code écrit). À valider par `product-owner` (voir Questions critiques) avant implémentation.

## Summary

Authentification OTP par magic link via Supabase Auth, sans mot de passe. Le client Flutter envoie le lien (`signInWithOtp`), Supabase redirige vers l'app (PWA Flutter Web), la session est restaurée au boot et exposée globalement via un `StreamProvider` Riverpod. Le routeur `go_router` se rafraîchit sur le stream d'auth pour gérer les gardes (`/login` ⇄ `/`). La création de l'enregistrement `landlords` au 1er accès est faite côté serveur par un **trigger Postgres sur `auth.users`** (fiable, pas de course Flutter). Comme `auth.users` est partagée entre les schémas `dev` et `public`, le trigger insère dans **les deux** schémas. Le formulaire impose une case de consentement RGPD non pré-cochée.

## Data model changes

### Frontière FEAT-001 / FEAT-002 (proposée)

FEAT-001 crée la table `landlords` **minimale** (juste de quoi rattacher l'identité au 1er login) + le trigger d'auto-provisioning. FEAT-002 **étend** la table (colonnes adresse bailleur, raison sociale, SIRET, etc.) via `ALTER TABLE` — pas de re-création. C'est la frontière la plus propre : FEAT-001 possède le cycle de vie « compte créé », FEAT-002 possède « profil bailleur enrichi ».

> ⚠️ Décision clé à valider : la PK de `landlords` est `auth.users.id` (relation 1-1 user↔landlord). Voir Question critique #1.

### Migration (les DEUX schémas — règle d'or `docs/ENVIRONMENTS.md`)

Fichier : `supabase/migrations/<YYYYMMDDHHMMSS>_feat001_landlords_and_auth_trigger.sql`

```sql
-- ============================================================================
-- FEAT-001 — landlords (minimal) + auto-provisioning trigger on auth.users
-- Applies to BOTH public (PROD) and dev (DEV) schemas.
-- ============================================================================

-- ---------- table: public.landlords ----------
CREATE TABLE public.landlords (
  id          uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.landlords ENABLE ROW LEVEL SECURITY;

-- RLS : un landlord ne voit/modifie que SA ligne (id == auth.uid()).
-- Pas de policy INSERT pour `authenticated` : l'insertion est faite par le
-- trigger en SECURITY DEFINER (bypass RLS), jamais par le client.
CREATE POLICY "landlord_selects_self" ON public.landlords
  FOR SELECT USING (id = auth.uid());
CREATE POLICY "landlord_updates_self" ON public.landlords
  FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());

CREATE INDEX idx_public_landlords_email ON public.landlords(email);

-- ---------- table: dev.landlords ----------
CREATE TABLE dev.landlords (LIKE public.landlords INCLUDING ALL);
-- NB: INCLUDING ALL ne copie pas le FK vers auth.users → on le rajoute.
ALTER TABLE dev.landlords
  ADD CONSTRAINT dev_landlords_id_fkey
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE dev.landlords ENABLE ROW LEVEL SECURITY;
CREATE POLICY "landlord_selects_self" ON dev.landlords
  FOR SELECT USING (id = auth.uid());
CREATE POLICY "landlord_updates_self" ON dev.landlords
  FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- ---------- trigger function (shared) ----------
-- Insère le landlord dans LES DEUX schémas au 1er accès (auth.users est
-- partagée entre dev et prod, on ne sait pas de quel env provient le signup).
-- ON CONFLICT DO NOTHING => idempotent, sûr en cas de re-exécution.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.landlords (id, email)
    VALUES (NEW.id, NEW.email)
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO dev.landlords (id, email)
    VALUES (NEW.id, NEW.email)
    ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ---------- parity / RLS asserts ----------
SELECT dev.assert_rls_both_schemas('landlords');
```

> Voir Question critique #2 (insérer dans les deux schémas vs un seul) et #5 (gestion du `ON DELETE CASCADE` vs rétention légale).

### RLS policies (résumé / threat model)

- **SELECT** : `id = auth.uid()` → un user ne lit que sa propre ligne. Un user A ne peut pas lire la ligne de B.
- **UPDATE** : `id = auth.uid()` (USING + WITH CHECK) → ne peut modifier que sa ligne, et ne peut pas réassigner `id` à autrui.
- **INSERT** : **aucune policy `authenticated`** → le client ne peut pas s'auto-insérer. Seul le trigger (`SECURITY DEFINER`, propriétaire = rôle privilégié) insère. Cela ferme la porte à un user qui forgerait une ligne `landlords` avec un faux `id`.
- **DELETE** : aucune policy → pas de suppression directe par le client (cf. droit à l'effacement géré ultérieurement, possiblement via Edge Function + soft-delete pour les entités à rétention légale).

## Backend (Edge Functions)

**N/A pour FEAT-001.** L'envoi du magic link est natif Supabase Auth (`signInWithOtp`), aucun secret côté serveur custom. La création `landlords` est un trigger Postgres, pas une fonction Deno.

## Flutter changes

### New files

- `lib/features/auth/domain/auth_state.dart` — type d'état UI du formulaire (freezed `union` : `idle / submitting / linkSent / error`). Distinct de la session Supabase.
- `lib/features/auth/data/auth_repository.dart` — wrapper fin sur `Supabase.instance.client.auth` : `sendMagicLink(email)`, `signOut()`, `authStateChanges` (Stream), `currentSession`. Provider `authRepositoryProvider`.
- `lib/features/auth/application/auth_controller.dart` — `StateNotifier<LoginFormState>` (ou AsyncNotifier) pilotant l'envoi du lien et la validation. Provider `authControllerProvider`.
- `lib/features/auth/application/auth_session_provider.dart` — `StreamProvider<AuthState>` exposant `authRepository.authStateChanges` ; helper `isAuthenticatedProvider` (bool dérivé).
- `lib/features/auth/presentation/widgets/login_form.dart` — champ email + case RGPD + bouton, < 200 lignes.
- `lib/features/auth/presentation/widgets/magic_link_sent_view.dart` — écran « Vérifiez votre boîte mail ».
- `lib/core/auth/auth_email_validator.dart` (ou util dans `core/utils/`) — validation email pure, testable unitairement.
- `lib/core/router/go_router_refresh_stream.dart` — `ChangeNotifier` qui notifie `GoRouter.refreshListenable` à chaque event d'auth (pattern standard go_router + stream).

### Modified files

- `lib/features/auth/presentation/login_page.dart` — remplace le stub : compose `LoginForm` / `MagicLinkSentView` selon l'état du `authControllerProvider`. Footer avec lien politique de confidentialité.
- `lib/core/router/app_router.dart` — (a) brancher `refreshListenable` sur `GoRouterRefreshStream(authStateChanges)` pour réévaluer la garde quand la session change ; (b) garder le `redirect` actuel mais lire la session via le repository ; (c) ajouter une route publique `/privacy` **ou** ouvrir l'URL externe (voir Q#4). Conserver la logique `/login ⇄ /` existante.
- `lib/main.dart` — `Supabase.initialize(...)` est déjà là ; ajouter `authFlowType: AuthFlowType.pkce` (recommandé web) et confirmer la persistance de session par défaut. Garde-fou : si `!Env.isConfigured`, afficher un écran d'erreur de config plutôt que crasher (voir Q#6).
- `lib/features/dashboard/presentation/dashboard_page.dart` — ajouter l'action « Déconnexion » dans l'AppBar appelant `authController.signOut()` (le redirect vers `/login` est automatique via le refresh stream).
- `web/index.html` / config Supabase Auth — déclarer les Redirect URLs (voir section Config).
- `dart-defines.dev.example.json` / `dart-defines.example.json` — documenter une éventuelle clé `PRIVACY_POLICY_URL` et l'URL de redirect si paramétrée (voir Q#4).

### Contrats / interfaces clés

```dart
// auth_repository.dart
abstract interface class AuthRepository {
  Stream<AuthState> get authStateChanges; // supabase AuthState
  Session? get currentSession;
  Future<void> sendMagicLink(String email);   // signInWithOtp(emailRedirectTo: <redirect>)
  Future<void> signOut();
}

// auth_state.dart (état du FORMULAIRE, pas la session)
@freezed
sealed class LoginFormState with _$LoginFormState {
  const factory LoginFormState.idle() = _Idle;
  const factory LoginFormState.submitting() = _Submitting;
  const factory LoginFormState.linkSent(String email) = _LinkSent;
  const factory LoginFormState.error(String message) = _Error;
}
```

- `sendMagicLink` appelle `client.auth.signInWithOtp(email: email, emailRedirectTo: <REDIRECT_URL>)`. Le `emailRedirectTo` doit pointer vers l'origine de l'app (dev vs prod) — c'est le point multi-env critique (Q#3).
- `signInWithOtp` crée l'utilisateur s'il n'existe pas (`shouldCreateUser` true par défaut) → couvre signup ET login avec le même appel.

### Providers (Riverpod)

| Provider | Type | Rôle |
|---|---|---|
| `authRepositoryProvider` | `Provider<AuthRepository>` | accès Supabase Auth |
| `authStateChangesProvider` | `StreamProvider<AuthState>` | flux de session (boot + login + logout + refresh) |
| `isAuthenticatedProvider` | `Provider<bool>` | dérivé, lu par le router |
| `authControllerProvider` | `StateNotifierProvider<.., LoginFormState>` | logique formulaire (validation, envoi, erreurs) |

### Routes

| Path | Auth requise | Note |
|---|---|---|
| `/login` | non (redirect → `/` si loggué) | existant, à câbler |
| `/` | oui | existant |
| `/privacy` | non | **optionnel** selon Q#4 (route interne vs lien externe) |

## Config (Redirect URLs Supabase)

À configurer dans Supabase Studio → Authentication → URL Configuration :

- **Site URL** : URL prod Firebase Hosting (ex. `https://easyrent.web.app`).
- **Redirect Allow List** (les deux env, même projet Supabase) :
  - `https://<prod>.web.app/` (+ variantes éventuelles)
  - `https://<staging-dev>.web.app/`
  - `http://localhost:<port>/` (dev local Flutter Web)
- Provider Email : activer **Magic Link**, désactiver « Confirm email » password flow inutile. Vérifier rate limit OTP par défaut.
- `flutter-dev` + `supabase-dev` doivent s'accorder sur la valeur de `emailRedirectTo` injectée par env (Q#3).

## Testing strategy

- **Unit** : `test/unit/auth_email_validator_test.dart` — emails valides/invalides, vide, espaces, casse.
- **Unit** : `auth_controller_test.dart` — repo mocké : transitions `idle→submitting→linkSent`, `→error` sur exception, **aucun appel repo si email invalide ou case RGPD décochée**.
- **Widget** : `test/widget/login_form_test.dart` — bouton désactivé tant que case RGPD décochée ; erreur inline « Adresse email invalide » ; passage à la vue « Vérifiez votre boîte mail » ; lien politique présent. Locale fr_FR.
- **Widget/Router** : garde de route — non authentifié sur `/properties` → `/login` ; authentifié sur `/login` → `/`.
- **RLS** : `supabase/tests/rls_landlords.sql` — user A ne SELECT/UPDATE que sa ligne ; tentative d'INSERT direct par `authenticated` refusée ; user B ne voit pas la ligne de A. Tester sur `public` ET `dev`.
- **Manuel QA** : flux complet email réel (sandbox Resend/dev), refresh navigateur garde la session, déconnexion révoque, deep link ouvert dans un autre onglet/navigateur (Q#7).

## Risks

- **Deep link / redirect PWA (Flutter Web)** : `supabase_flutter` capte le callback via le fragment d'URL / detectSessionInUri. Risque si le magic link est ouvert dans un navigateur différent de celui qui a initié (PKCE lie le code au navigateur d'origine) → message d'erreur clair à prévoir. Voir Q#7.
- **Multi-env redirect** : `emailRedirectTo` doit matcher l'allow-list ET l'origine réelle (localhost vs staging vs prod). Mauvais réglage = lien qui retombe sur la mauvaise origine ou rejeté par Supabase. C'est le risque #1 d'intégration.
- **Persistance de session vs « pas de remember me »** : `supabase_flutter` persiste par défaut dans le localStorage (survit au refresh ET à la fermeture du navigateur). La story dit « pas au-delà de la session navigateur ». Tension à arbitrer (Q#8) — sinon non-conformité RGPD/story.
- **Init Supabase au boot** : si `Env` non configuré (`SUPABASE_URL` vide), `Supabase.initialize` peut lever / l'app crash. Prévoir un garde-fou (Q#6).
- **Trigger sur `auth.users`** : nécessite des droits élevés (souvent OK via migration sur free tier, mais à confirmer côté Supabase). Si refus de créer un trigger sur le schéma `auth`, fallback = provisioning au 1er login côté Flatter avec `upsert` (moins fiable) — à éviter, mais à connaître.
- **`ON DELETE CASCADE` vs rétention légale** : supprimer un `auth.users` effacerait `landlords` (et plus tard ses quittances). En conflit potentiel avec l'obligation de conservation 5 ans (Q#5).
- **Double insertion dev+prod** : un compte créé en prod crée aussi une ligne `dev.landlords` (et inverse). Acceptable (isolation des données métier ailleurs), mais à documenter.

## Questions critiques (arbitrage utilisateur AVANT de coder)

1. **PK de `landlords`** : adopter `id = auth.users.id` (relation 1-1, `auth.uid()` direct dans les RLS — le plus simple) ? Ou un `id` propre + colonne `user_id` séparée ? → recommandation : PK = `auth.users.id`.
2. **Trigger : insérer dans dev ET public, ou un seul schéma ?** Comme `auth.users` est partagée, on ne connaît pas l'env à l'insertion. Option A (recommandée) : insérer dans les deux (idempotent). Option B : table de provisioning paresseuse au 1er accès par schéma. → recommandation : Option A.
3. **Valeur de `emailRedirectTo` par environnement** : quelles URLs exactes (domaine Firebase prod, domaine staging, localhost) ? Faut-il injecter l'URL via `--dart-define` ou la dériver de `Uri.base.origin` à l'exécution ? → besoin des domaines réels.
4. **Politique de confidentialité** : URL externe existante, ou page interne `/privacy` à créer dans cette feature ? Quelle URL pointer dans la case RGPD et le footer ?
5. **`ON DELETE CASCADE` sur `landlords.id`** : OK pour le MVP, ou faut-il déjà prévoir soft-delete / anonymisation pour respecter la rétention légale (quittances 5 ans) dès maintenant ?
6. **Comportement si `Env` non configuré au boot** : écran d'erreur propre vs laisser crasher en dev ? (impacte `main.dart`).
7. **UX magic link ouvert dans un autre navigateur** (PKCE) : afficher un message « ouvrez le lien dans le même navigateur » et permettre de renvoyer un lien ? Acceptable pour le MVP ?
8. **Persistance de session** : la story interdit le « remember me » / session au-delà du navigateur, mais `supabase_flutter` persiste par défaut. Doit-on désactiver la persistance (session en mémoire seulement, perdue au refresh — UX dégradée) ou tolérer la persistance par défaut et reformuler la contrainte ? → arbitrage produit/légal nécessaire.

## Step-by-step execution order

1. **`supabase-dev`** — écrire et appliquer la migration `landlords` + trigger sur `dev` et `public` ; écrire `supabase/tests/rls_landlords.sql` ; vérifier `dev.assert_rls_both_schemas('landlords')`. (Dépend de Q#1, #2, #5.)
2. **`supabase-dev` (config)** — activer Magic Link, renseigner Site URL + Redirect Allow List dev/prod/localhost. (Dépend de Q#3.)
3. **`flutter-dev`** — `auth_repository` + providers + `auth_controller` + `auth_state` (freezed, lancer build_runner) ; brancher `GoRouterRefreshStream` dans `app_router.dart` ; durcir `main.dart` (PKCE, garde-fou config). (Dépend de Q#3, #6, #8.)
4. **`flutter-dev`** — UI : `login_page` + `login_form` (validation, case RGPD, lien politique) + `magic_link_sent_view` ; action Déconnexion dans le dashboard. (Dépend de Q#4.)
5. **`qa-tester`** — tests unit (validator, controller), widget (form/garde), exécuter les tests RLS, QA manuelle du flux email + refresh + logout. (Dépend de Q#7.)
6. **`code-reviewer` + `security-auditor`** — revue RLS (INSERT fermé au client, SECURITY DEFINER + search_path figé), absence de secret client, conformité RGPD (case non pré-cochée, lien politique), conformité multi-env.
7. **`state-keeper`** — MAJ `SCHEMA.md`, `ROUTES.md`, `FEATURES.md` après merge.
```
