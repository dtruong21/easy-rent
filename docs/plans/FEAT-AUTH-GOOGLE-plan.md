# Plan — [FEAT-AUTH-GOOGLE] Sign-in / sign-up Google (Baillan)

## Summary

Ajout d'un bouton "Continuer avec Google" sur `/login` et `/signup`, basé sur
`FirebaseAuth.signInWithPopup(GoogleAuthProvider)`. La création de compte
Google côté `/signup` est gated par une checkbox RGPD obligatoire (a). Sur
`/login`, on choisit l'approche **stricte (b.i)** : si le sign-in Google
crée en réalité un nouvel utilisateur (`additionalUserInfo.isNewUser`), on
révoque immédiatement le compte (`user.delete()`) et on affiche un message
qui redirige vers `/signup`. Justification : (1) la `beforeUserCreated`
Cloud Function ne reçoit aucune preuve de consentement pour le flux Google
(elle hardcode `CURRENT_RGPD_VERSION` quel que soit le provider), donc le
seul moyen de garantir l'accountability RGPD (art. 7.1) est de bloquer la
création via un flux qui exige une checkbox explicite, et (2) le flux
"doux" (consent-gate post-login) implique un état intermédiaire où le
user existe sans consent, ce qui élargit la surface d'audit et complique
les exports RGPD. La compensation UX est claire : le message d'erreur
de `/login` propose explicitement le lien `/signup`.

Toutes les corrections au brief :
- Cloud Function `handleNewUser` lit `displayName`/`email` mais **ne lit
  PAS** `rgpdConsentVersion` depuis `raw_user_meta_data` — la version est
  hardcodée serveur. Pas un blocker, mais raison supplémentaire de gater
  côté client.
- `google_sign_in` package est inutile sur Web. `firebase_auth` ^5.3.1
  expose nativement `signInWithPopup` via le JS SDK.
- Firestore (pas Postgres/Supabase). `landlords/{uid}` doc avec champs
  camelCase confirmés.

## Approach choice

- **Signup page** : checkbox RGPD existante (`_RgpdCheckbox`) gate le bouton
  Google (même règle que pour email/password). Sans coche → bouton disabled.
  Au clic, on appelle `SignupController.signUpWithGoogle(rgpdConsent: true)`.
  Le repo `signUpWithGoogle` (1) appelle `signInWithPopup`, (2) si
  `isNewUser == false` (cas où le compte Google existe déjà), c'est un
  sign-in standard, on ne fait rien de plus ; (3) si `isNewUser == true`,
  on laisse `handleNewUser` provisionner le doc, puis le client fait un
  `set({merge:true})` pour s'assurer que `rgpdConsentVersion` est à jour
  + un champ `signupProvider: 'google'` (audit).

- **Login page** : bouton "Continuer avec Google" disponible sans gate.
  Le repo `signInWithGoogle` appelle `signInWithPopup` puis inspecte
  `userCredential.additionalUserInfo!.isNewUser`. Si `true` (= compte
  vient d'être créé) :
    1. `user.delete()` (révocation immédiate, supprime aussi le doc
       Firestore via la règle de cascade côté Functions si elle existe ;
       sinon on supprime explicitement le doc dans le `catch` du
       repo via `_firestore.doc('landlords/{uid}').delete()`).
    2. `signOut()` par sécurité.
    3. Throw `FirebaseAuthException(code: 'baillan/google-new-user-on-login')`
       que `AuthErrorMapper` traduit en message FR avec invitation à
       `/signup`.
  Si `false` → sign-in normal, redirect via `authStateChanges`.

- **New user handling** : la création Firebase Auth déclenche
  `handleNewUser` blocking trigger (déjà déployé) qui provisionne
  `landlords/{uid}` avec `rgpdConsentVersion = 'v1-2026-06'` + serverTs.
  Côté client, on overwrite (merge) avec `fullName = user.displayName`,
  `email = user.email`, `signupProvider: 'google'`, `rgpdConsentAt`
  client-confirmé (utile pour l'export GDPR : on stocke aussi
  `rgpdConsentSource: 'google-popup'`).

- **RGPD consent flow** : sur `/signup`, la checkbox est OBLIGATOIRE pour
  activer le bouton Google. Si l'utilisateur décoche après ouverture du
  popup (race rare), `_canSubmitGoogle` est checké à nouveau dans le
  controller avant l'appel repo — on rejette avec
  `SignupPageState.error("Vous devez accepter la politique...")`.

## Files to create

### `lib/features/auth/data/google_auth_exception.dart`
Public API :
```dart
/// Codes synthétiques propres à Baillan pour les exceptions liées au flow Google.
sealed class GoogleAuthErrorCode {
  static const String newUserOnLogin = 'baillan/google-new-user-on-login';
  static const String popupBlocked = 'baillan/popup-blocked';
  static const String popupClosed = 'baillan/popup-closed';
  static const String consentDeclined = 'baillan/rgpd-consent-declined';
}
```

### `lib/features/auth/presentation/widgets/google_sign_in_button.dart`
Public API :
```dart
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,     // null => disabled
    required this.isLoading,
    this.label = 'Continuer avec Google',
  });
  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;
}
```
Widget : `OutlinedButton.icon` (pas `FilledButton` — bouton secondaire,
moins vendeur que le bouton primaire email/password), icône `G` Google
multicolore en SVG (asset à ajouter `assets/icons/google_g.svg` via
`flutter_svg`, déjà dans pubspec si non l'ajouter), label texte. Respect
brand guidelines Google. Hauteur identique au FilledButton primary
(48px). État `isLoading` → spinner.

### `lib/features/auth/presentation/widgets/_or_divider.dart`
Petit séparateur "ou" entre les blocs email/password et Google. Trait
fin + label centré, espacement vertical 16px.

## Files to modify

### `lib/features/auth/data/auth_repository.dart`
Ajouter deux méthodes à l'interface :
```dart
/// Sign-in Google : refuse les nouveaux comptes (révocation immédiate
/// si isNewUser=true → throw 'baillan/google-new-user-on-login').
Future<void> signInWithGoogle();

/// Sign-up Google : exige consent RGPD préalable (rgpdConsent==true),
/// laisse handleNewUser provisionner puis surcouche fullName/provider
/// côté client.
Future<void> signUpWithGoogle({required bool rgpdConsent});
```
Implémentation `FirebaseAuthRepository` :
- `signInWithGoogle` : build `GoogleAuthProvider` avec scope `email` +
  `profile` ; `_auth.signInWithPopup(provider)` ; check
  `cred.additionalUserInfo?.isNewUser == true` → `user.delete()` +
  `signOut()` + throw `FirebaseAuthException(code: 'baillan/google-new-user-on-login')`.
  Catch `firebase/popup-blocked-by-browser`, `firebase/popup-closed-by-user`,
  `account-exists-with-different-credential` → rethrow tels quels (mapper
  les traduit).
- `signUpWithGoogle` : si `!rgpdConsent` → throw
  `FirebaseAuthException(code: 'baillan/rgpd-consent-declined')`.
  Sinon `signInWithPopup` ; si `isNewUser == true`, faire merge sur
  `landlords/{uid}` avec `fullName: user.displayName ?? email`,
  `signupProvider: 'google'`, `rgpdConsentVersion`, `rgpdConsentAt: now`,
  `rgpdConsentSource: 'google-popup'`. Si `isNewUser == false`, c'est en
  fait un sign-in (compte Google existant) — accepter (équivalent à
  `signInWithGoogle` success) ; on ne touche pas au doc landlord.

### `lib/features/auth/data/auth_error_mapper.dart`
Ajouter cases :
```dart
case 'popup-closed-by-user':
  return 'Connexion Google annulée.';
case 'popup-blocked':
  return 'Votre navigateur a bloqué la fenêtre Google. Autorisez les pop-ups pour ce site et réessayez.';
case 'account-exists-with-different-credential':
  return 'Un compte existe déjà avec cet email mais via une autre méthode. Connectez-vous d\'abord avec votre mot de passe.';
case 'baillan/google-new-user-on-login':
  return 'Aucun compte Baillan associé à ce Google. Veuillez d\'abord créer un compte.';
case 'baillan/rgpd-consent-declined':
  return 'Vous devez accepter la politique de confidentialité.';
case 'cancelled-popup-request':
  return 'Une autre fenêtre Google est déjà ouverte.';
case 'web-storage-unsupported':
  return 'Votre navigateur bloque les cookies tiers nécessaires à Google. Activez-les ou utilisez le formulaire email.';
```

### `lib/features/auth/application/login_controller.dart`
Ajouter méthode `Future<void> signInWithGoogle()` :
- `state = submitting()`
- try `_repository.signInWithGoogle()`
- catch `FirebaseAuthException` → mapping FR. Cas spécial
  `baillan/google-new-user-on-login` : state = error MAIS ajouter un
  champ optionnel `ctaRoute: '/signup'` au state (voir modif domain
  ci-dessous).

### `lib/features/auth/application/signup_controller.dart`
Ajouter méthode `Future<void> signUpWithGoogle({required bool rgpdConsent})` :
- Validation `if (!rgpdConsent) state = error(...); return;`
- `state = submitting()`
- try `_repository.signUpWithGoogle(rgpdConsent: rgpdConsent)`
- même pattern de mapping erreurs.

### `lib/features/auth/domain/login_page_state.dart`
Étendre `error` factory pour exposer un CTA optionnel :
```dart
const factory LoginPageState.error({
  required String message,
  String? ctaRoute,
  String? ctaLabel,
}) = _Error;
```
Regénérer `.freezed.dart` (build_runner). Idem pour `signup_page_state.dart`
si on veut afficher un CTA après erreur Google côté signup (utile pour
`account-exists-with-different-credential` → CTA "Se connecter").

### `lib/features/auth/presentation/widgets/login_form.dart`
Sous le `FilledButton('Se connecter')` :
- `_OrDivider()` (16px gap)
- `GoogleSignInButton` avec `onPressed: isSubmitting ? null : () => ref.read(loginControllerProvider.notifier).signInWithGoogle()`
- `isLoading: formState.maybeWhen(submitting: () => true, orElse: () => false)`

Adapter le bloc `errorMessage` pour afficher le CTA si `ctaRoute != null` :
`TextButton(onPressed: () => context.go(ctaRoute), child: Text(ctaLabel ?? 'Continuer'))`.

### `lib/features/auth/presentation/widgets/signup_form.dart`
Sous `FilledButton('Créer mon compte')` :
- `_OrDivider()`
- `GoogleSignInButton` avec
  `onPressed: (_rgpdConsent && !isSubmitting) ? () => ref.read(signupControllerProvider.notifier).signUpWithGoogle(rgpdConsent: _rgpdConsent) : null`
- Hint visible si `!_rgpdConsent` : tooltip ou texte gris sous le bouton
  "Cochez la case ci-dessus pour activer Google".

### `pubspec.yaml`
Ajouter (si absent) : `flutter_svg: ^2.0.10` pour le logo Google
(vérifier d'abord — peut déjà y être). Ajouter asset
`assets/icons/google_g.svg`.

### `web/index.html`
Vérifier la CSP : `signInWithPopup` ouvre `accounts.google.com` et
`*.firebaseapp.com`. Si CSP stricte, ajouter ces origins en
`frame-src`, `connect-src`. Le fichier actuel a déjà `apis.google.com`
(à confirmer) mais probablement pas `accounts.google.com`. Mettre à
jour en conséquence.

### `firebase.json`
Idem — CSP headers Hosting. S'assurer que
`https://accounts.google.com` et `https://*.firebaseapp.com` sont dans
`frame-src` ET `connect-src`. Et que `https://apis.google.com` reste.

## Routes

Aucune nouvelle route. Pas de "consent gate" page car on a opté pour
l'approche stricte (b.i).

## Edge cases

(voir structured output — section `edge_cases`)

## Testing strategy

(voir structured output — section `tests_to_add`)

## Step-by-step execution order

1. **flutter-dev** : pubspec asset SVG + flutter_svg si nécessaire.
2. **flutter-dev** : ajouter méthodes au repo (`signInWithGoogle`,
   `signUpWithGoogle`) + extension `AuthErrorMapper`.
3. **flutter-dev** : ajouter controllers methods + extend domain states
   avec ctaRoute/ctaLabel (build_runner).
4. **flutter-dev** : créer widgets `GoogleSignInButton` + `_OrDivider` +
   intégrer dans `login_form.dart` et `signup_form.dart`.
5. **flutter-dev** : mettre à jour CSP (`web/index.html` + `firebase.json`).
6. **qa-tester** : écrire tests (mock repo via Mocktail, widget tests).
7. **code-reviewer** + **security-auditor** : focus sur le rollback
   `user.delete()` + race conditions popup.
8. **deployer** : déployer staging d'abord (channel staging), tester
   manuellement les 3 flows (signup new, signup existing, login new
   rejected, login existing OK), puis prod.

## Risks & open questions

- Risque `user.delete()` qui échoue côté repo : si `signInWithGoogle`
  détecte isNewUser mais que `user.delete()` throw (network par
  exemple), on se retrouve avec un compte Firebase Auth orphelin et
  un doc Firestore `landlords/{uid}`. Mitigation : entourer le delete
  d'un try/catch qui log l'incident (Sentry/logger) et signOut quand
  même ; un cron côté Cloud Functions peut nettoyer les
  `landlords` sans `signInProvider` après 24h, mais c'est P2.
- Risque CSP : si on oublie d'autoriser `accounts.google.com`, le popup
  reste blanc et l'utilisateur n'a aucun feedback. À tester avec la
  CSP strict mode du build prod.
- Open : doit-on lier un compte existant email+password à Google
  (account-linking) ? Pour l'instant non — l'utilisateur reçoit le
  message "Connectez-vous d'abord avec votre mot de passe". Un futur
  P1 pourrait offrir le lien via `linkWithCredential` dans `/profile`.
