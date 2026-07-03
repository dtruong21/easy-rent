# Plan — [FEAT-025] Écran Profil → vrai paramétrage (Sécurité + Support)

> **⚠️ Ce plan intègre le PIVOT DE SCOPE utilisateur du 2026-07-03**, qui remplace
> les décisions initiales de la user story (`docs/backlog/025-settings-profile.md`) :
> - **V1.1** = **formulaire in-app** (mot de passe actuel + nouveau + confirmation)
>   via `reauthenticateWithCredential` + `updatePassword` — **PAS** le lien email
>   `sendPasswordResetEmail`.
> - **V1.2** = **formulaire in-app** écrivant dans une **nouvelle collection Firestore
>   `support_requests`** — **PAS** un `mailto:`.
>
> Les sections « Décisions à trancher » et « Risques » de la story restent
> partiellement valides ; ce plan re-tranche ce qui a changé.

## Summary

Enrichir `/profile` de deux sections d'action de compte, dans l'ordre logique de
la page (après le formulaire d'identité, avant/autour de Légal & Session) :

1. **Sécurité** — changement de mot de passe **in-app** (reauth + updatePassword),
   visible **uniquement** si le `User` courant possède un provider `password`
   (comptes email ; rien affiché pour Google/Apple/anonyme).
2. **Support** — formulaire « Nous contacter » (sujet + message) qui écrit un doc
   `support_requests/{auto}` (create-only côté client).

Zéro modification de `functions/`. Une **nouvelle collection Firestore** avec un
bloc de rules **create-only** à ajouter (fourni verbatim ci-dessous, isolation git
gérée par l'orchestrateur). La notification email (`daki.tle.26@gmail.com`) est
**listée en 3 options non tranchées** — le formulaire se livre indépendamment.

## Data model changes

### Nouvelle collection `support_requests/{docId auto}`

Une seule collection plate, docId auto-généré (`.add()`), **jamais relue par le
client en V1** (write-only du point de vue de l'app ; consultation via console
Firestore ou pipeline de notification). Un doc = une demande de contact.

| Champ | Type | Contrainte | Source |
|---|---|---|---|
| `landlordId` | string | `== request.auth.uid` | `authRepository.currentUser.uid` |
| `email` | string | non vide | `landlordProfileProvider.email` (ou `currentUser.email`) |
| `subject` | string | 1..120 chars | saisie utilisateur |
| `message` | string | 1..2000 chars | saisie utilisateur |
| `appVersion` | string | présent | `appInfoProvider` → `'x.y.z+build'` |
| `appEnv` | string | présent | `Env.appEnv` (`'prod'` / `'dev'`) |
| `status` | string | `== 'new'` à la création | constante client |
| `createdAt` | timestamp | `serverTimestamp()` | serveur |

**Pas de `deletedAt`** : collection append-only, jamais soft-delete côté client
(cohérent avec `receipts` qui n'a pas de soft-delete non plus). **Pas d'`updatedAt`** :
le doc est immuable côté client une fois créé (pas de trigger `setUpdatedAt` requis,
donc aucun besoin de toucher `functions/`).

### Migration

**N/A (Firestore schemaless)** — aucune migration SQL. La collection est créée
implicitement au premier `.add()`. Les rules ci-dessous sont le seul artefact à
déployer.

### Index Firestore

**AUCUN index composite requis.** La collection est create-only : le client ne fait
ni `list` ni `where`/`orderBy`. Ne rien ajouter à `firestore.indexes.json`.
(Si un back-office futur veut lister par `status` + `createdAt`, l'index sera ajouté
dans la story back-office, pas ici.)

### RLS policies — bloc à ajouter à `firestore.rules`

**Threat model (1 paragraphe)** : un bailleur authentifié complet peut **créer**
une demande de support à son propre nom (`landlordId == auth.uid`), avec des champs
bornés en taille (anti-spam / anti-payload géant). Il ne peut **jamais** relire,
lister, modifier ni supprimer de demande (ni les siennes, ni celles des autres) —
`get/list/update/delete: false`. Les anonymes n'ont pas accès (`isFullyAuthed()`),
cohérent avec le fait qu'ils n'ont pas d'email. Toute lecture/traitement se fait
via Admin SDK (console, ou future CF de notification qui bypasse les rules).

**Bloc EXACT à insérer** — à placer **juste avant** le fallback
`match /{document=**}` (≈ ligne 312 du fichier actuel), en respectant l'indentation
à 4 espaces des autres `match` :

```
    // ====================================================================
    // support_requests/{id}   — CREATE-ONLY (FEAT-025)
    //
    // Formulaire « Nous contacter ». Le client écrit une demande à son
    // propre nom ; il ne relit JAMAIS (pas de back-office in-app en V1).
    // Traitement (notification email, triage) via Admin SDK / console.
    // ====================================================================
    match /support_requests/{id} {
      allow get, list: if false;   // l'utilisateur ne relit pas ses demandes en V1

      allow create: if isFullyAuthed()
        && request.resource.data.landlordId == request.auth.uid
        && request.resource.data.email is string
        && request.resource.data.email.size() > 0
        && request.resource.data.subject is string
        && request.resource.data.subject.size() > 0
        && request.resource.data.subject.size() <= 120
        && request.resource.data.message is string
        && request.resource.data.message.size() > 0
        && request.resource.data.message.size() <= 2000
        && request.resource.data.appVersion is string
        && request.resource.data.appEnv is string
        && request.resource.data.status == 'new'
        && request.resource.data.createdAt == request.time;

      allow update, delete: if false;
    }
```

**Notes de conformité aux conventions du fichier** :
- Réutilise le helper existant `isFullyAuthed()` (l.40) — pas de nouveau helper.
- `createdAt == request.time` valide que le client a bien mis `serverTimestamp()`
  (Firestore résout `serverTimestamp()` en `request.time` au moment de l'évaluation
  de la rule ; même vérification implicite que le pattern des autres collections,
  ici rendue explicite car `createdAt` est le seul timestamp).
- **Ne PAS** utiliser `preservesImmutables()` (helper pour les `update`, pas les
  `create` ; et cette collection n'a pas d'`update`).

**⚠️ Isolation git (à charge de l'orchestrateur, PAS de l'agent qui code)** :
`firestore.rules` porte des **modifications locales non commitées** sur la branche
courante (`git status` : ` M firestore.rules`). Procédure imposée :
1. `git stash push firestore.rules` (isoler le WIP)
2. Ajouter **uniquement** le bloc `support_requests` ci-dessus, commiter seul
3. `firebase deploy --only firestore:rules`
4. `git stash pop` (restaurer le WIP)

Ne **jamais** committer le WIP existant avec ce bloc.

## Backend (Edge Functions / Cloud Functions)

**Aucune Cloud Function écrite dans ce sprint** (deploy `functions/` cassé sur la
branche — contrainte dure). La **notification email** vers `daki.tle.26@gmail.com`
est laissée **en décision utilisateur de fin de sprint**, avec 3 options **non
tranchées ici** :

| Option | Principe | Coût / prérequis | Quand |
|---|---|---|---|
| **A — Extension Firebase « Trigger Email »** | Extension officielle qui envoie un email sur écriture dans une collection. Configurée **en console** (SMTP/SendGrid), pas de code dans `functions/`. Peut cibler `support_requests` ou une collection `mail` dédiée. | Config console + secret SMTP ; ne touche pas `functions/` (déploiement d'extension séparé du code) | Livrable même avec `functions/` cassé |
| **B — CF `onCreate('support_requests')`** | Trigger Firestore Admin SDK qui lit le doc et envoie l'email. | **Bloqué** tant que le deploy `functions/` n'est pas réparé | Après merge du fix `functions/` |
| **C — V1 sans notification** | Les demandes s'empilent dans Firestore, consultées **manuellement en console** (Firestore Data). | Zéro infra | Immédiat, filet minimal |

**Recommandation d'architecte (non contraignante)** : livrer le formulaire + rules
en V1 avec **option C** comme défaut de départ (aucun blocage), puis basculer sur
**A** dès que l'adresse SMTP/expéditeur est décidée — A est la seule qui reste
déployable sans réparer `functions/`. Décision à confirmer par l'utilisateur.

## Flutter changes

### Nouveaux fichiers

**V1.1 — Sécurité (changement mot de passe)**

- `lib/features/auth/domain/change_password_state.dart` — état freezed :
  `idle | submitting | success | error(message)`. Modèle strictement calqué sur
  `reset_password_state.dart` (sealed, `@freezed`, `part '*.freezed.dart'`). Génère
  `.freezed.dart` via build_runner.
- `lib/features/auth/application/change_password_controller.dart` —
  `StateNotifier<ChangePasswordState>` + `changePasswordControllerProvider`.
  Calqué sur `reset_password_controller.dart` :
  - `Future<void> submit({required String currentPassword, required String newPassword, required String confirmPassword})`
  - Validation locale AVANT tout appel réseau, dans cet ordre :
    1. `PasswordValidator.validate(newPassword)` (réutilise
       `lib/core/utils/password_validator.dart` — 8 car, 1 lettre, 1 chiffre)
    2. `newPassword != confirmPassword` → `'Les mots de passe ne correspondent pas'`
       (message identique à `reset_password_controller.dart:41`)
    3. (Optionnel/défense) `newPassword == currentPassword` → message
       « Le nouveau mot de passe doit être différent de l'actuel » — **à confirmer**
       (voir Questions). Sinon Firebase l'accepte silencieusement.
  - Puis `state = submitting` → `await repo.reauthenticateWithPassword(...)` →
    `await repo.updatePassword(...)` → `state = success`.
  - `catch (FirebaseAuthException e)` → `AuthErrorMapper.fromException(e)`
    (voir ajouts au mapper ci-dessous) ; `catch (_)` → message générique
    `'Une erreur est survenue. Veuillez réessayer.'`.
  - **Pas d'anti-énumération OWASP ici** (contrairement à `forgot_password_controller`) :
    l'utilisateur est déjà connecté et connaît son compte → un « mot de passe actuel
    incorrect » est un message honnête et utile, pas une fuite.
- `lib/features/profile/presentation/widgets/profile_security_section.dart` —
  `ProfileSecuritySection extends ConsumerWidget`. Contient :
  - Header `_SectionHeader(title: 'Sécurité')` — **voir note _SectionHeader** plus bas.
  - **Gating** : `ref.watch(hasPasswordProvider)` → si `false`, `return const SizedBox.shrink()`
    (rien affiché, pas même le header — décision utilisateur ferme).
  - Sinon, un `ProfileChangePasswordForm` (stateful, ci-dessous) ou un bouton
    « Changer mon mot de passe » qui révèle le formulaire inline. **Recommandation** :
    formulaire directement inline (3 champs), plus simple qu'un expand/dialog et
    cohérent avec le reste de la page qui est un long scroll de sections.
- `lib/features/profile/presentation/widgets/profile_change_password_form.dart` —
  `ProfileChangePasswordForm extends ConsumerStatefulWidget`. Calqué sur
  `reset_password_form.dart` mais avec **3 champs** :
  - `PasswordField` « Mot de passe actuel » (`autofillHints: [AutofillHints.password]`,
    key `Key('field_current_password')`)
  - `PasswordField` « Nouveau mot de passe » (`autofillHints: [AutofillHints.newPassword]`,
    key `Key('field_new_password')`) + helper text `'8 caractères min, 1 lettre, 1 chiffre'`
    (repris tel quel de `reset_password_form.dart:99`)
  - `PasswordField` « Confirmer le nouveau mot de passe »
    (key `Key('field_confirm_password')`)
  - `FilledButton` (key `Key('btn_change_password')`) désactivé si `submitting` OU si
    `_canSubmit` faux. `_canSubmit` = les 3 champs non vides ET
    `PasswordValidator.validate(new) == null` ET `new == confirm` (même logique de
    gating local que `reset_password_form.dart:45`).
  - `ref.listen<ChangePasswordState>` : sur `success` → `ScaffoldMessenger` SnackBar
    « Mot de passe mis à jour » (fond `primaryContainer`, cohérent avec le SnackBar
    succès profil `profile_page.dart:99`) **+ vider les 3 contrôleurs** (`.clear()`)
    **+ remettre le state controller à `idle`** (sinon un re-listen retriggererait).
    Sur `error` → message inline sous le formulaire (couleur `error`, comme
    `reset_password_form.dart:112`), pas de SnackBar (l'erreur reste visible près
    des champs pour retenter).

**V1.2 — Support (nous contacter)**

- `lib/features/support/domain/support_request_state.dart` — état freezed
  `idle | submitting | success | error(message)`. Même moule freezed.
- `lib/features/support/data/support_repository.dart` — pattern **identique** à
  `profile_repository.dart` :
  - `abstract interface class SupportRepository { Future<void> submit({required String subject, required String message, required String appVersion, required String appEnv}); }`
  - `class FirestoreSupportRepository implements SupportRepository` avec
    `FirebaseFirestore` + `FirebaseAuth` injectés. `submit` construit le payload
    (landlordId = `_auth.currentUser!.uid`, email = `_auth.currentUser!.email`,
    `status: 'new'`, `createdAt: FieldValue.serverTimestamp()`) puis
    `_firestore.collection('support_requests').add(payload)`. Lève une exception
    claire si `currentUser == null` (bug d'appel — la section n'est montrée qu'à un
    user complet).
  - `final supportRepositoryProvider = Provider<SupportRepository>(...)` (comme
    `profileRepositoryProvider`).
- `lib/features/support/application/support_controller.dart` —
  `StateNotifier<SupportRequestState>` + `supportControllerProvider`. Validation
  locale (subject non vide ≤120, message non vide ≤2000, mêmes bornes que les rules),
  puis `submitting` → `await repo.submit(...)` → `success`. `catch` → message
  générique (`'Envoi impossible. Réessayez dans quelques instants.'`) ; pas
  d'anti-énumération (write-only, pas d'info sensible).
- `lib/features/support/presentation/widgets/profile_support_section.dart` —
  `ProfileSupportSection extends ConsumerWidget`. Header `_SectionHeader(title: 'Support')`,
  texte court neutre (« Une question, un souci ? Écrivez-nous. » — **ne PAS** le
  présenter comme canal RGPD, cf. Legal notes de la story). Contient un
  `ProfileSupportForm` (stateful) inline.
- `lib/features/support/presentation/widgets/profile_support_form.dart` —
  `ProfileSupportForm extends ConsumerStatefulWidget`. Champs :
  - `TextFormField` « Sujet » (key `Key('field_support_subject')`, `maxLength: 120`)
  - `TextFormField` « Message » (key `Key('field_support_message')`, `maxLines: 5`,
    `maxLength: 2000`)
  - `FilledButton` (key `Key('btn_support_submit')`) désactivé si `submitting` ou
    champs vides.
  - `ref.listen` : `success` → SnackBar « Message envoyé. Nous reviendrons vers vous
    par email. » + vider les champs + repasser à `idle`. `error` → message inline.
  - Le user a besoin de `appInfoProvider` (version) et `Env.appEnv` : lus dans le
    widget et passés au controller.submit (le controller reste pur, sans dépendance
    à `PackageInfo`).

### Fichiers modifiés

- `lib/features/profile/presentation/profile_page.dart` — insérer les 2 nouvelles
  sections dans `_buildForm` (Column). **Ordre proposé** (à confirmer, voir Questions) :
  formulaire compte → `ProfileSecuritySection` → `ProfileAppearanceSection` →
  `ProfileLegalSection` → `ProfileAboutSection` → `ProfileSupportSection` →
  `ProfileSessionSection`. Justification : Sécurité juste après l'identité (actions
  de compte groupées) ; Support avant la déconnexion (fin de page, low-frequency).
  Ajouter les `SizedBox`/`Divider` cohérents avec l'existant. **Aucune logique dans
  la page** — les sections sont autonomes (elles lisent leurs providers).
  - **Import ajout** : les deux nouveaux widgets de section.
- `lib/features/auth/data/auth_repository.dart` — **ajouts à l'interface + impl** :
  - Interface `AuthRepository` (après `sendPasswordResetEmail`, l.195) :
    ```
    /// Réauthentifie l'utilisateur courant avec son mot de passe actuel.
    /// Prérequis Firebase pour updatePassword (« recent login »).
    /// Lève FirebaseAuthException('wrong-password'|'invalid-credential', ...)
    /// si le mot de passe est incorrect, ou StateError si aucun user/email.
    Future<void> reauthenticateWithPassword(String currentPassword);

    /// Change le mot de passe de l'utilisateur courant. À appeler APRÈS
    /// reauthenticateWithPassword (Firebase exige une session récente).
    Future<void> updatePassword(String newPassword);
    ```
  - Impl `FirebaseAuthRepository` :
    ```
    @override
    Future<void> reauthenticateWithPassword(String currentPassword) async {
      final user = _auth.currentUser;
      final email = user?.email;
      if (user == null || email == null) {
        throw StateError('reauthenticateWithPassword requires a signed-in '
            'user with an email (currentUser=${user?.uid}).');
      }
      _log.info('reauthenticateWithPassword requested');
      final cred = EmailAuthProvider.credential(
          email: email, password: currentPassword);
      await user.reauthenticateWithCredential(cred);
    }

    @override
    Future<void> updatePassword(String newPassword) async {
      final user = _auth.currentUser;
      if (user == null) {
        throw StateError('updatePassword requires a signed-in user.');
      }
      _log.info('updatePassword requested');
      await user.updatePassword(newPassword);
    }
    ```
  - **Style** : `_log.info` sans logger le mot de passe ; `StateError` pour les bugs
    d'appel (cohérent avec `_requireAnonymousUser`, l.695) ; `FirebaseAuthException`
    laissée remonter pour mapping par le controller.
  - **Fake de test** : les fakes `implements AuthRepository` existants (ex.
    `session_state_provider_test.dart`) devront ajouter les 2 stubs `async {}` —
    changement mécanique, à répercuter partout où `implements AuthRepository`
    apparaît (voir Testing).
- `lib/features/auth/data/auth_error_mapper.dart` — **vérifier / compléter** le
  mapping des codes du flow reauth/update. La plupart sont **déjà couverts** :
  - `wrong-password`, `invalid-credential` → déjà « Email ou mot de passe incorrect. »
    (l.16-20). **Point d'attention UX** : dans le contexte « mot de passe actuel »,
    ce libellé mentionne « Email » qui n'a pas de sens ici. **Recommandation** :
    ajouter un code Baillan dédié OU laisser le controller mapper spécifiquement
    `wrong-password`/`invalid-credential` en « Mot de passe actuel incorrect. »
    **avant** de déléguer au mapper générique. Préférence archi : mapping spécifique
    dans le `change_password_controller` (garde `AuthErrorMapper` mutualisé intact),
    fallback `AuthErrorMapper.fromException` pour les autres codes.
  - `weak-password` → déjà couvert (l.29). `too-many-requests` → déjà couvert (l.33).
  - `requires-recent-login` → **NON couvert** actuellement. En théorie évité (on
    reauth juste avant), mais l'ajouter au mapper par sécurité :
    « Pour des raisons de sécurité, reconnectez-vous puis réessayez. » **À ajouter.**

### Providers

- `hasPasswordProvider` (**nouveau**, à placer dans
  `lib/features/auth/application/auth_session_provider.dart` — même fichier que
  `authStateChangesProvider`/`sessionStateProvider`, cohérence de colocation) :
  ```
  /// `true` ssi le User courant possède un provider `password` (compte email,
  /// ou social lié ultérieurement à un mot de passe). Base de gating de la
  /// section Sécurité. Dérivé de authStateChangesProvider (userChanges) → se
  /// rafraîchit après login/link à chaud (pas de session bloquée).
  final hasPasswordProvider = Provider<bool>((ref) {
    final async = ref.watch(authStateChangesProvider);
    final user = async.asData?.value
        ?? ref.read(authRepositoryProvider).currentUser;
    if (user == null || user.isAnonymous) return false;
    return user.providerData.any((info) => info.providerId == 'password');
  });
  ```
  - **Pourquoi `authStateChangesProvider` et pas `currentUser` direct** : ce
    StreamProvider s'appuie sur `userChanges()` (superset qui refire sur link
    provider / mutations — cf. commentaire `auth_repository.dart:324-333`). Un
    compte social qui **lie** un mot de passe pendant la session verra la section
    apparaître sans reload. Le fallback `currentUser` couvre le loading initial
    (même défense que `sessionStateProvider`, l.44).
  - **`isAnonymous` court-circuité explicitement** : un anonyme n'a de toute façon
    pas de provider `password`, mais le check rend l'intention lisible et
    documente le critère de la story.
- `changePasswordControllerProvider` (StateNotifierProvider) — nouveau.
- `supportRepositoryProvider` (Provider) — nouveau.
- `supportControllerProvider` (StateNotifierProvider) — nouveau.

### Routes

**AUCUNE nouvelle route.** Tout vit sous `/profile` existant (sections inline). Pas
de `go_router` à toucher.

### Note _SectionHeader (dette de découpage à trancher)

`_SectionHeader` est **privé** dans `profile_settings_sections.dart` (l.174). Les
nouvelles sections `ProfileSecuritySection` (feature `profile`) et
`ProfileSupportSection` (feature `support`) en ont besoin. Deux options :

- **Option 1 (recommandée)** : promouvoir `_SectionHeader` en `SectionHeader` public
  dans un fichier partagé léger, ex.
  `lib/features/profile/presentation/widgets/section_header.dart`, et l'importer
  depuis les 3 sections. Retire la duplication, changement minime.
- **Option 2** : garder les sections Sécurité **dans**
  `profile_settings_sections.dart` (accès direct à `_SectionHeader`) et dupliquer un
  mini-header pour Support. Rejeté : duplication + fichier qui gonfle.

→ **Recommandation : Option 1.** Impact test : le test existant
`profile_page_test.dart` cherche `find.text('Apparence')` etc. par **texte**, pas par
type de widget — promouvoir le header ne casse rien.

## Testing strategy

Pattern imposé : tests **widget** façon `profile_page_test.dart`
(`ProviderScope` + overrides + `MaterialApp.router`), fakes maison, keys const.
`firebase_auth_mocks` (^0.14.2) dispo en dev deps.

### Point de vigilance BLOQUANT — override obligatoire de `authRepositoryProvider`

`profile_page_test.dart::_buildPage` **n'override PAS** `authRepositoryProvider`
aujourd'hui (la page n'en dépendait pas). Dès qu'on ajoute `hasPasswordProvider`
(qui lit `authRepositoryProvider` → `FirebaseAuth.instance`), **tous les tests
existants planteront** (Firebase non initialisé en `flutter test`). Le helper
`_buildPage` **doit** être étendu pour injecter un `authRepositoryProvider`
overridé (fake) — sinon régression immédiate sur les 15 tests existants.

→ Étendre `_buildPage(..., {AuthRepository? authRepo, SupportRepository? supportRepo})`
et ajouter les overrides correspondants. Le fake par défaut = compte email
(`providerData` avec `password`) pour ne pas casser les tests existants qui ne
s'occupent pas de la section (elle sera juste présente et inerte).

### Faker le User / providerData proprement

`MockUser` (`firebase_auth_mocks`) accepte `isAnonymous: bool` et
`providerData: List<UserInfo>` dans son constructeur (vérifié dans
`mock_user.dart:30-37`). Construire un `UserInfo` avec `providerId == 'password'`
via `UserInfo.fromJson` (constructeur disponible dans
`firebase_auth_platform_interface`, prend une `Map`) :

```dart
UserInfo _providerInfo(String providerId) => UserInfo.fromJson({
      'uid': 'uid-1',
      'email': 'test@example.com',
      'displayName': null,
      'photoUrl': null,
      'phoneNumber': null,
      'isAnonymous': false,
      'isEmailVerified': true,
      'providerId': providerId,   // 'password' | 'google.com' | 'apple.com'
      'tenantId': null,
      'refreshToken': null,
      'creationTimestamp': null,
      'lastSignInTimestamp': null,
    });

MockUser _passwordUser() => MockUser(
      isAnonymous: false,
      uid: 'uid-1',
      email: 'test@example.com',
      providerData: [_providerInfo('password')],
    );
MockUser _googleUser() => MockUser(
      isAnonymous: false, uid: 'uid-1', email: 'g@example.com',
      providerData: [_providerInfo('google.com')]);
MockUser _anonUser() => MockUser(isAnonymous: true, uid: 'uid-a');
```

Le fake `AuthRepository` de test expose `authStateChanges => Stream.value(user)` et
`currentUser => user` (comme `session_state_provider_test.dart::_FakeAuthRepository`),
plus des stubs pour `reauthenticateWithPassword` / `updatePassword` que l'on peut
faire **jeter** un `FirebaseAuthException(code: 'wrong-password')` ou réussir selon
le scénario (flags `throwWrongCurrentPassword`, `throwTooManyRequests`, etc.).

### Scénarios V1.1 (mapping Gherkin story + pivot)

1. **Compte email → section Sécurité visible** : fake user `password` →
   `find.byKey(Key('field_current_password'))` `findsOneWidget`, header « Sécurité »
   présent.
2. **Google → rien affiché** : fake user `google.com` → `find.text('Sécurité')`
   `findsNothing`, `find.byKey(Key('field_current_password'))` `findsNothing`.
3. **Apple → rien affiché** : idem avec `apple.com`.
4. **Anonyme → rien affiché** : fake user `isAnonymous: true`.
5. **Succès** : remplir les 3 champs valides, tap `btn_change_password` →
   `reauthenticateWithPassword` puis `updatePassword` appelés (fake enregistre les
   args) ; SnackBar « Mot de passe mis à jour » ; les 3 champs vidés.
6. **Mauvais mot de passe actuel** : fake `reauthenticateWithPassword` jette
   `FirebaseAuthException('wrong-password')` → message inline « Mot de passe actuel
   incorrect. » ; `updatePassword` **jamais** appelé.
7. **Nouveau mot de passe faible** : saisir `new = 'abc'` → validation locale
   (`PasswordValidator`) → message ; aucun appel réseau (fake non touché).
8. **Confirmation ≠ nouveau** : `new` valide mais `confirm` différent → message
   « Les mots de passe ne correspondent pas » ; aucun appel réseau.
9. **too-many-requests** : fake jette `FirebaseAuthException('too-many-requests')` →
   « Trop de demandes. Réessayez dans quelques minutes. » (via mapper existant).
10. **Bouton désactivé pendant submit** : state `submitting` → `btn_change_password`
    `onPressed == null` + `CircularProgressIndicator` (pattern `profile_page_test.dart:236`,
    `pump()` pas `pumpAndSettle()`).

Tests **unitaires** du `ChangePasswordController` (façon
`reset_password_controller_test.dart`) : ordre de validation, mapping d'erreurs,
transitions d'état — plus fins que le widget.

### Scénarios V1.2 (support)

1. **Section présente pour compte complet** : header « Support » + champs +
   `btn_support_submit`.
2. **Succès** : remplir sujet + message, tap → `SupportRepository.submit` appelé
   avec `subject`/`message`/`appVersion`/`appEnv` attendus (fake enregistre) ;
   SnackBar succès ; champs vidés. `appInfoProvider` mocké via
   `PackageInfo.setMockInitialValues` (déjà fait dans le `setUp` existant).
3. **Validation** : sujet vide → bouton désactivé / message ; message vide → idem ;
   message > 2000 → borné (via `maxLength` + validation controller).
4. **Échec réseau** : fake `submit` jette → message inline neutre « Envoi
   impossible… » ; pas de SnackBar succès.
5. **Bouton désactivé pendant submit** : state `submitting` → `onPressed == null`.

### Tests RLS (à confier à `qa-tester` sur l'émulateur Firestore)

Le pattern de test de rules existe déjà (le fichier `firestore.rules` référence
`docs/plans/FEAT-019-firestore-rules.md`). Scénarios `support_requests` :
- Compte complet crée un doc avec `landlordId == auth.uid` et champs valides → **allow**.
- `landlordId != auth.uid` → **deny**.
- `subject`/`message` vide ou dépassant la borne (121 / 2001 chars) → **deny**.
- `status != 'new'` → **deny**.
- Anonyme tente un create → **deny** (`isFullyAuthed()` faux).
- N'importe quel `get`/`list`/`update`/`delete` (même sur son propre doc) → **deny**.

### DoD tooling

- `flutter analyze` clean (les 4 nouveaux `.freezed.dart` générés compilent).
- `dart format .` sur **tous** les fichiers, y compris les `*.freezed.dart` générés
  (CI fail sinon — cf. MEMORY « dart format avant commit »).
- `build_runner` : `dart run build_runner build --delete-conflicting-outputs` pour
  les 2 nouveaux états freezed.

## Risks

1. **[BLOQUANT tests] `authRepositoryProvider` non overridé dans `profile_page_test.dart`** :
   ajouter `hasPasswordProvider` casse tous les tests existants si le helper de
   montage n'injecte pas un fake auth repo. **Mitigation** : étendre `_buildPage`
   (détaillé ci-dessus). C'est le risque #1 à traiter.
2. **Isolation git de `firestore.rules`** : le WIP non commité ne doit jamais partir
   avec le bloc `support_requests`. **Mitigation** : procédure stash/commit/deploy/pop
   explicitée ; à charge de l'orchestrateur, PAS de l'agent Flutter.
3. **`reauthenticateWithCredential` — codes d'erreur SDK variables selon plateforme
   web** : selon la version Firebase JS, un mauvais mot de passe peut remonter
   `wrong-password` **ou** `invalid-credential`. **Mitigation** : mapper les DEUX
   codes vers « Mot de passe actuel incorrect. » dans le controller.
4. **`requires-recent-login` résiduel** : bien qu'on reauth juste avant `updatePassword`,
   un délai/refresh token peut théoriquement déclencher ce code. **Mitigation** :
   l'ajouter au `AuthErrorMapper` (message « reconnectez-vous »).
5. **Notification email non tranchée** : le formulaire livre des demandes qui
   pourraient n'être vues par personne si aucune option A/B/C n'est activée.
   **Mitigation** : défaut = option C (consultation console) documenté ; l'utilisateur
   tranche A vs B en fin de sprint. **À surfacer au product-owner.**
6. **RGPD — canal support n'est pas une conformité** : ne pas labelliser « RGPD » /
   « effacement » dans l'UI (juste « Support »), cf. Legal notes de la story. Le doc
   `support_requests` stocke `email` + `message` = **nouvelle donnée personnelle**
   côté Baillan (contrairement au `mailto:` initialement prévu) → à intégrer au
   registre de traitement / politique de conf. **À surfacer au security-auditor.**
7. **Coût `updatePassword` = déconnexion des autres sessions** : Firebase révoque les
   refresh tokens des autres sessions après changement de mot de passe (comportement
   attendu / souhaitable). La session courante reste valide. À mentionner en QA, pas
   un bug.
8. **`_SectionHeader` privé** : promotion nécessaire (Option 1) — dette mineure, sans
   impact sur les tests par texte.

## Step-by-step execution order

1. **[orchestrateur]** Isoler le WIP `firestore.rules` : `git stash push firestore.rules`,
   ajouter le bloc `support_requests` seul, commit, `firebase deploy --only firestore:rules`,
   `git stash pop`. (Peut se faire en parallèle du dev Flutter — la collection ne
   sert qu'au moment du submit support.)
2. **[flutter-dev]** `AuthRepository` : ajouter `reauthenticateWithPassword` +
   `updatePassword` (interface + impl) ; répercuter les 2 stubs dans tous les fakes
   de test `implements AuthRepository`. Compléter `AuthErrorMapper`
   (`requires-recent-login`).
3. **[flutter-dev]** V1.1 : `change_password_state` (+ build_runner) →
   `change_password_controller` → `hasPasswordProvider` (dans
   `auth_session_provider.dart`) → promouvoir `SectionHeader` (Option 1) →
   `profile_security_section` + `profile_change_password_form` → insérer dans
   `profile_page.dart`.
4. **[flutter-dev]** V1.2 : `support_request_state` (+ build_runner) →
   `support_repository` (+ provider) → `support_controller` →
   `profile_support_section` + `profile_support_form` → insérer dans `profile_page.dart`.
5. **[flutter-dev]** Étendre `profile_page_test.dart::_buildPage` (override
   `authRepositoryProvider` + `supportRepositoryProvider`), écrire les tests widget
   V1.1 + V1.2 ; tests unitaires des 2 controllers.
6. **[qa-tester]** Tests de rules `support_requests` sur l'émulateur ; QA manuelle
   des 4 scénarios de provider (email/Google/Apple/anonyme) + changement mot de passe
   réel sur staging.
7. **[code-reviewer]** Revue (découpage sections, `_canSubmit`, vidage des champs).
8. **[security-auditor]** Revue : rules create-only, non-fuite du mot de passe dans
   les logs, `support_requests` = nouvelle donnée perso (registre RGPD), pas de label
   « conformité RGPD » dans l'UI.
9. **[orchestrateur]** `flutter analyze` + `dart format` + build → déploiement
   staging (pas de prod sans confirmation utilisateur).
10. **[fin de sprint / utilisateur]** Trancher l'option de notification email
    (A/B/C) et l'activer.

## Questions critiques à trancher AVANT / PENDANT le codage

1. **Notification email** (option A « Trigger Email » config console / B « CF après
   fix functions » / C « console-only V1 »). Sans décision, on livre avec **C** par
   défaut, mais les demandes ne déclencheront aucune alerte. → **product-owner + utilisateur.**
   (L'adresse `daki.tle.26@gmail.com` est notée ; elle sera l'expéditeur/destinataire
   de l'option retenue.)
2. **Message d'erreur « mot de passe actuel incorrect »** : confirmer qu'on veut un
   libellé dédié (« Mot de passe actuel incorrect. ») plutôt que le générique existant
   « Email ou mot de passe incorrect. » (qui mentionne « Email », hors contexte ici).
   → **product-owner** (recommandation : libellé dédié).
3. **Interdire `newPassword == currentPassword` ?** Firebase l'accepte silencieusement
   (no-op). Ajouter une validation locale « le nouveau doit différer de l'actuel » ?
   → **product-owner** (recommandation : oui, évite une confusion utilisateur).
4. **Ordre des sections dans la page** : Sécurité juste après le formulaire compte,
   Support avant Session (proposé). Confirmer que cet ordre convient. → **product-owner.**
5. **Placement du formulaire mot de passe** : inline (proposé) vs derrière un bouton
   « Changer mon mot de passe » qui déplie / ouvre un dialog. → **product-owner**
   (recommandation : inline, cohérent avec la page long-scroll).
