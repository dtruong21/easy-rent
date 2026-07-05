# Plan — [FEAT-011] Authentification email + password (Pivot FEAT-001)

> **Statut** : ✅ **Implémentée 2026-06-22** — Code mergé, tests 1093/1093 passing, `flutter analyze` clean.
> 
> **Pivot 2026-06-22** : Remplacement de FEAT-001 (magic link) par authentification classique email + password pour v1 stable. Voir contexte ci-dessous et `docs/plans/FEAT-001-auth-magic-link.md` (historique conservé).

## Contexte et justification du pivot

**Décision** : Remplacer le flow magic link (FEAT-001) par email + password classique avant la sortie MVP.

**Raison** : Authentification par mot de passe est plus familière aux utilisateurs français / propriétaires tertiaires. Magic link PKCE présente des frictions (lien dans email, ouverture dans le bon navigateur, expiration courte). Password offre une UX plus stable et un taux de conversion meilleur pour MVP.

**Limitations connues** :
- Session recovery dépend de `supabase_flutter` 2.x + PKCE
- Mot de passe minimum 8 caractères + 1 lettre + 1 chiffre (Supabase built-in `letters_digits`)
- Pas de « remember me » / persistance navigateur (MVP constraint)
- Email confirmation obligatoire côté Supabase (activation config 2026-06-22)

## Décisions actées

### Politique mot de passe
- **Longueur minimale** : 8 caractères
- **Complexité** : 1 lettre + 1 chiffre minimum (Supabase `letters_digits` validator)
- **Hachage** : bcrypt côté Supabase (jamais en clair côté client)
- **HTTPS exclusif** : Tous les transports en-transit protégés

### Signup self-service
- Formulaire signup publique : email + password + confirmation password
- Email confirmation obligatoire : lien de confirmation envoyé par Supabase (SMTP template FR)
- Full name capturée via auth metadata (`raw_user_meta_data->>'full_name'`) → trigger SQL `handle_new_user()` migre vers `landlords.full_name`
- Auto-provisioning : trigger `handle_new_user()` crée landlord sur confirmation email

### Reset password
- Lien reset password par email (template FR)
- Redirect vers `/reset-password?token=...` (composant public)
- Confirmation nouveau password + validation
- Session auto-restaurée post-reset (connexion transparent)
- Snackbar confirmation "Mot de passe réinitialisé"

### Routes publiques
- `/login` : formulaire connexion email + password (refactorisé FEAT-001)
- `/signup` : formulaire inscription email + password + full_name + confirmation password
- `/forgot-password` : formulaire email uniquement (champ readonly après envoi)
- `/reset-password?token=<token>` : formulaire nouveau password (code validé backend)

**Comportement redirect** :
- Authentifié + `/login` ou `/signup` → redirect `/`
- Non authentifié + route fermée (ex `/properties`) → redirect `/login`
- Non authentifié + `/privacy` → accessible (public)

## Architecture Flutter

### Couche Domain (models, use cases)
- `PasswordValidator` : validation policy (8 chars, 1 lettre, 1 chiffre) — testable unitairement
- `AuthErrorMapper` : conversion erreurs Supabase en messages UI localisés

### Couche Data (repositories, services)
- `AuthRepository` refactor :
  - `signUp(email, password, fullName) → Future<void>` — envoie OTP confirmation email
  - `signIn(email, password) → Future<void>` — connecte et restaure session
  - `resetPassword(email) → Future<void>` — demande reset link par email
  - `confirmPasswordReset(token, password) → Future<void>` — applique nouveau password
  - `authStateChanges` : Stream session (inchangé)
- `PasswordResetService` : gère token validation + polling (si désiré)

### Couche Application (Riverpod providers)
- `authRepositoryProvider` : accès à AuthRepository
- `authStateChangesProvider` : StreamProvider session (inchangé)
- `isAuthenticatedProvider` : dérivé (inchangé)
- `loginControllerProvider` : StateNotifier(LoginFormState) — validation + appel signIn
- `signupControllerProvider` : StateNotifier(SignupFormState) — validation + appel signUp
- `forgotPasswordControllerProvider` : StateNotifier(ForgotPasswordFormState)
- `resetPasswordControllerProvider` : StateNotifier(ResetPasswordFormState) + token extraction

### Couche Presentation (Pages + Widgets)
- `lib/features/auth/presentation/pages/login_page.dart` : refactor (email + password + button) — 180 lignes
- `lib/features/auth/presentation/pages/signup_page.dart` : nouveau (email + full_name + password × 2 + lien login) — 240 lignes
- `lib/features/auth/presentation/pages/forgot_password_page.dart` : nouveau (email seul + button) — 120 lignes
- `lib/features/auth/presentation/pages/reset_password_page.dart` : nouveau (token hidden, 2 password inputs) — 160 lignes
- `lib/features/auth/presentation/widgets/password_field.dart` : nouveau (toggle show/hide, meter complexité) — 120 lignes
- `lib/features/auth/presentation/widgets/password_validator_error_list.dart` : nouveau (check list dynamique : 8+ chars, 1 letter, 1 digit) — 80 lignes
- `lib/features/auth/presentation/widgets/email_password_form.dart` : nouveau (composable email + password + validation) — 140 lignes

### Tests (Dart)
- Unit tests : `PasswordValidator` (test edge cases : 7 chars, letters-only, digits-only, valide, UTF-8, etc.)
- Unit tests : `AuthErrorMapper` (erreurs Supabase mappées → messages localisés)
- Unit tests : controllers (signup/login/forgot/reset, transitions d'état, validations)
- Widget tests : toutes les pages + widgets, interactions formulaire (enable/disable boutons, focus, validation)
- Integration test : flux signup complet → confirm email → login → logout (avec mocking Supabase ou testigos)

**Résultat** : 1093/1093 tests passing (1 session de dév, incluant refactors existants FEAT-001–010)

## Migration SQL (Supabase)

**Fichier** : `supabase/migrations/20260622130000_feat011_handle_new_user_fullname.sql`

```sql
-- FEAT-011 — Adapt handle_new_user() trigger to extract full_name from auth metadata
-- Applies to BOTH public (PROD) and dev (DEV) schemas.

-- ============================================================================
-- Update trigger function handle_new_user() to read full_name from metadata
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.landlords (id, email, full_name)
    VALUES (
      NEW.id,
      NEW.email,
      NEW.raw_user_meta_data->>'full_name'
    )
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO dev.landlords (id, email, full_name)
    VALUES (
      NEW.id,
      NEW.email,
      NEW.raw_user_meta_data->>'full_name'
    )
    ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- ============================================================================
-- Supabase Auth configuration (via Studio, not SQL)
-- ============================================================================
-- Email Provider : enable "Confirm email" + custom SMTP template (FR)
-- Password rules : minLength=8, letters_digits (1 letter + 1 digit minimum)
-- Email templates : supabase/templates/confirmation.html + recovery.html
```

### Configuration Supabase Studio (actions manuelles post-merge)

1. **Authentication → Providers → Email**
   - Enable "Confirm email" (confirmation obligatoire)
   - Password validation : minLength 8 + letters_digits
   - SMS/Magic Link : disable (aucun besoin)

2. **Authentication → URL Configuration**
   - Site URL : `https://easy-rent-54cd4.web.app` (prod) ou staging equivalent
   - Redirect Allow List :
     ```
     https://easy-rent-54cd4.web.app/**
     https://easyrent-staging.web.app/**
     http://localhost:*/**
     ```

3. **Authentication → Email Templates**
   - Copier le contenu de `supabase/templates/confirmation.html` → Confirmation Template
   - Copier le contenu de `supabase/templates/recovery.html` → Recovery Template

## Fichiers créés / modifiés / supprimés

### Création (22 fichiers Dart)

**Pages** (4 nouveaux) :
- `lib/features/auth/presentation/pages/signup_page.dart`
- `lib/features/auth/presentation/pages/forgot_password_page.dart`
- `lib/features/auth/presentation/pages/reset_password_page.dart`
- `lib/features/auth/presentation/pages/login_page.dart` (refactor)

**Widgets** (5 nouveaux) :
- `lib/features/auth/presentation/widgets/password_field.dart`
- `lib/features/auth/presentation/widgets/password_validator_error_list.dart`
- `lib/features/auth/presentation/widgets/email_password_form.dart`
- `lib/features/auth/presentation/widgets/signup_form.dart`
- `lib/features/auth/presentation/widgets/reset_password_form.dart`

**Domain** (2 nouveaux) :
- `lib/features/auth/domain/password_validator.dart`
- `lib/features/auth/domain/auth_error.dart`

**Data** (3 modifiés) :
- `lib/features/auth/data/auth_repository.dart` (refactor : remplace signInWithOtp par signIn/signUp/resetPassword)
- `lib/features/auth/data/password_reset_service.dart` (nouveau)
- `lib/features/auth/data/auth_error_mapper.dart` (nouveau)

**Application** (5 modifiés) :
- `lib/features/auth/application/login_controller.dart` (refactor : password au lieu de OTP)
- `lib/features/auth/application/signup_controller.dart` (nouveau)
- `lib/features/auth/application/forgot_password_controller.dart` (nouveau)
- `lib/features/auth/application/reset_password_controller.dart` (nouveau)
- `lib/features/auth/application/auth_state.dart` (refactor : état formulaires)

**Tests** (7 nouveaux) :
- `test/unit/features/auth/password_validator_test.dart`
- `test/unit/features/auth/auth_error_mapper_test.dart`
- `test/widget/features/auth/login_form_test.dart` (refactor)
- `test/widget/features/auth/signup_form_test.dart` (nouveau)
- `test/widget/features/auth/forgot_password_form_test.dart` (nouveau)
- `test/widget/features/auth/reset_password_form_test.dart` (nouveau)
- `test/widget/features/auth/password_field_test.dart` (nouveau)

### Modification (10 fichiers Dart)

- `lib/core/router/app_router.dart` : 4 routes (login refactor, signup, forgot, reset) + redirects
- `lib/main.dart` : durcissement config Supabase, garde-fou si clés manquantes
- `lib/features/dashboard/presentation/dashboard_page.dart` : action logout unchanged
- `lib/features/privacy/presentation/privacy_page.dart` : section sécurité (hash bcrypt, no remember-me)
- `lib/l10n/intl_*.arb` : localisation nouvelles clés (password policies, error messages)
- `pubspec.yaml` : aucune dépendance new (supabase_flutter déjà présent)
- `.github/workflows/ci.yml` : aucun changement (tests identiques)
- `.github/workflows/deploy.yml` : aucun changement
- `dart-defines.dev.example.json` : aucun changement
- `.env.example` : aucun changement

### Suppression (4 fichiers Dart)

- `lib/features/auth/presentation/widgets/magic_link_sent_view.dart` (plus d'OTP)
- `lib/features/auth/presentation/widgets/otp_code_input_field.dart` (inutile)
- `lib/features/auth/application/otp_controller.dart` (remplacé par signup/login)
- `test/widget/features/auth/magic_link_sent_view_test.dart` (supprimé)

## Limites connues (MVP)

1. **Session recovery** : dépend de `supabase_flutter` 2.x et du flow PKCE. Si le service worker crashe, session peut être perdue.
2. **Email delivery** : pas de retry automatique si email ne parvient pas. User doit demander renvoyer (UI TBD).
3. **Token expiry** : reset password token expire après 1h (Supabase default). UX : lien expiré → afficher "Demander nouveau lien" + redirect forgot-password.
4. **Password change** : pas d'endpoint pour changer password utilisateur connecté (MVP). À ajouter en FEAT-012.
5. **Rate limiting** : Supabase built-in (limité 3 tentatives/minute). Pas de custom throttling UI.

## Effort

- **Sprint** : 1 session de dev (5,5j) — implémentation + tests + code review + merge
- **Date livraison** : 2026-06-22
- **Branche** : `feature/feat-011-auth-password` → mergée dans `develop`

## Référence commits

Voir git log de la branche `feature/feat-011-auth-password` pour détails ligne-par-ligne.

## Prochaines étapes

- **FEAT-012** : Password change endpoint + profile settings (P1)
- **FEAT-013** : Multi-facteur (2FA / TOTP) — post-MVP
- **Email delivery reliability** : ajouter retry + dashboard "pending confirmations" — P1
- **Privacy/RGPD** : export données + droit à l'effacement (via Edge Function) — P1
