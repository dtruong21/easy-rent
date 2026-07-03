import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'apple_auth_exception.dart';
import 'google_auth_exception.dart';

final _log = Logger('AuthRepository');

/// Version actuelle du texte de consentement RGPD présenté à l'utilisateur.
///
/// Format : 'vN-YYYY-MM' — à incrémenter à chaque mise à jour des CGU, du
/// texte de politique de confidentialité ou des finalités de traitement.
/// Persisté dans landlords.rgpdConsentVersion (champ immuable post-création).
/// **Doit rester synchronisé avec functions/src/auth/handle_new_user.ts**.
/// Historique :
/// - v1-2026-06 : politique de confidentialité v1.0 seule
/// - v2-2026-07 : CGU v1.0 + politique de confidentialité v1.0
///   (case d'acceptation unique au signup)
const String rgpdConsentVersion = 'v2-2026-07';

/// Fenêtre d'expiration glissante d'une session anonyme (BAILLAN-M1).
///
/// À garder synchronisé avec `anonExpiryWindow`
/// (`application/anon_expiry_renewer.dart` — non importable ici sans cycle)
/// et `ANON_EXPIRY_DAYS` (`functions/src/auth/handle_new_user.ts`).
const Duration _anonProvisionExpiryWindow = Duration(days: 14);

/// Contrat public — les widgets / providers consomment cette interface,
/// jamais l'implémentation directement (mocks faciles en test).
abstract interface class AuthRepository {
  /// Flux d'événements d'authentification Firebase Auth.
  Stream<User?> get authStateChanges;

  /// Utilisateur courant, ou [null] si non authentifié.
  User? get currentUser;

  /// Connecte avec email + mot de passe.
  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  /// Crée un compte et :
  /// 1. Provisionne Firebase Auth user + displayName
  /// 2. Écrit landlords/{uid} avec consent RGPD horodaté (atomicité art. 7.1)
  /// 3. Envoie un email de vérification (template Firebase Auth par défaut)
  /// 4. Signe out — l'utilisateur devra cliquer le lien puis se reconnecter
  ///
  /// Si Identity Platform `beforeUserCreated` est activé, la Cloud Function
  /// crée déjà le doc landlords ; le `set({merge:true})` client garantit
  /// l'idempotence sans casser le flow quand IP est désactivé.
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
  });

  /// Envoie (ou renvoie) un email de vérification à l'utilisateur courant.
  ///
  /// L'utilisateur DOIT être signé (i.e. `currentUser != null`). Utilise le
  /// template email par défaut Firebase Auth — customisable dans Firebase
  /// Console → Authentication → Templates → « Vérification d'e-mail ». Le
  /// lien pointe vers `<origin>/login` après vérification.
  ///
  /// Lève `FirebaseAuthException('no-current-user', ...)` si aucun user
  /// n'est signé au moment de l'appel.
  Future<void> sendCurrentUserEmailVerification();

  /// Connecte avec un compte Google existant.
  ///
  /// **Ne crée jamais de nouveau compte** : si le popup Google révèle un
  /// utilisateur inconnu de Baillan (`isNewUser == true`), le compte Firebase
  /// Auth créé par le popup est immédiatement révoqué (rollback : `delete()`
  /// + `signOut()`) puis l'appel lève
  /// `FirebaseAuthException(code: GoogleAuthErrorCode.newUserOnLogin)`.
  /// Cette garde évite qu'un compte soit provisionné sans consentement RGPD
  /// explicite (art. 7.1) — toute première inscription Google doit passer
  /// par [signUpWithGoogle].
  Future<void> signInWithGoogle();

  /// Crée un compte (ou connecte un compte existant) via Google.
  ///
  /// [rgpdConsent] doit être `true` — sinon l'appel lève
  /// `FirebaseAuthException(code: GoogleAuthErrorCode.consentDeclined)`
  /// **avant** d'ouvrir le popup Google (aucune création n'est tentée sans
  /// consentement explicite).
  ///
  /// Si le compte Google est nouveau (`isNewUser == true`), le doc
  /// `landlords/{uid}` (déjà provisionné par la Cloud Function
  /// `beforeUserCreated`) est surchargé via `set(merge:true)` pour ajouter
  /// `signupProvider: 'google'` et `rgpdConsentSource: 'google-popup'`
  /// (audit trail RGPD). Si le compte existe déjà (`isNewUser == false`),
  /// le doc landlord n'est jamais modifié.
  Future<void> signUpWithGoogle({required bool rgpdConsent});

  /// Connecte avec un compte Apple existant.
  ///
  /// **Ne crée jamais de nouveau compte** : si le popup Apple révèle un
  /// utilisateur inconnu de Baillan (`isNewUser == true`), le compte Firebase
  /// Auth créé par le popup est immédiatement révoqué (rollback : `delete()`
  /// + `signOut()`) puis l'appel lève
  /// `FirebaseAuthException(code: AppleAuthErrorCode.newUserOnLogin)`.
  /// Cette garde évite qu'un compte soit provisionné sans consentement RGPD
  /// explicite (art. 7.1) — toute première inscription Apple doit passer
  /// par [signUpWithApple].
  ///
  /// **Spécificité Apple** : si ce rollback delete() puis un nouveau
  /// [signUpWithApple] est retenté depuis le même Apple ID, Apple ne
  /// re-transmettra PAS le nom complet (bug/limitation connue : le
  /// displayName + email complet ne sont fournis qu'à la toute première
  /// autorisation OAuth pour un couple app/Apple ID). Voir
  /// [signUpWithApple] pour le fallback appliqué.
  Future<void> signInWithApple();

  /// Crée un compte (ou connecte un compte existant) via Apple.
  ///
  /// [rgpdConsent] doit être `true` — sinon l'appel lève
  /// `FirebaseAuthException(code: AppleAuthErrorCode.consentDeclined)`
  /// **avant** d'ouvrir le popup Apple (aucune création n'est tentée sans
  /// consentement explicite).
  ///
  /// Si le compte Apple est nouveau (`isNewUser == true`), le doc
  /// `landlords/{uid}` (déjà provisionné par la Cloud Function
  /// `beforeUserCreated`) est surchargé via `set(merge:true)` pour ajouter
  /// `signupProvider: 'apple'` et `rgpdConsentSource: 'apple-popup'`
  /// (audit trail RGPD). Si le compte existe déjà (`isNewUser == false`),
  /// le doc landlord n'est jamais modifié.
  ///
  /// **Spécificités Apple à connaître** :
  /// - `user.displayName` peut être `null` (Apple ne renvoie le nom complet
  ///   qu'à la toute première autorisation OAuth pour ce couple app/Apple
  ///   ID — un rollback `delete()` suivi d'un nouveau `signUpWithApple`
  ///   depuis le même Apple ID ne re-déclenchera pas l'envoi du nom). Le
  ///   fallback CREATE utilise `user.displayName ?? user.email ?? ''`.
  /// - "Hide My Email" : l'utilisateur peut choisir un email proxy
  ///   `@privaterelay.appleid.com`. Firebase Auth le traite comme un email
  ///   vérifié standard — aucun filtrage/validation de domaine n'est
  ///   appliqué ici.
  Future<void> signUpWithApple({required bool rgpdConsent});

  /// Ouvre une session Firebase Anonymous Auth (« essai sans compte »),
  /// puis provisionne le doc `landlords/{uid}` avec `isAnonymous: true`,
  /// `subscriptionTier: 'anonymous'` et `anonExpiresAt: now + 14 jours`
  /// s'il n'existe pas déjà (session anonyme réutilisée).
  ///
  /// Le provisioning est fait côté client (chemin CREATE anonyme des
  /// rules) : sur ce projet, Identity Platform est désactivé, la Cloud
  /// Function `handleNewUser` (beforeUserCreated) ne se déclenche donc
  /// jamais — elle ne sert que de defense-in-depth si IP est activé un
  /// jour. **Aucun consentement RGPD n'est demandé/stampé** — l'anonyme
  /// n'a rien signé (voir `docs/LEGAL.md`).
  Future<void> signInAnonymously();

  /// Lie le compte anonyme courant à un email + mot de passe, en préservant
  /// l'UID (et donc les scénarios simulateur déjà sauvegardés).
  ///
  /// Doit être appelée uniquement quand `currentUser?.isAnonymous == true`
  /// (sinon lève `StateError`). Séquence :
  /// 1. `EmailAuthProvider.credential` + `currentUser.linkWithCredential`
  /// 2. `updateDisplayName(fullName)`
  /// 3. Callable `finalizeAnonymousUpgrade` (stamp RGPD + tier='free' côté
  ///    serveur, Admin SDK — évite toute rule client permissive)
  /// 4. Email de vérification puis `signOut` (même flow que
  ///    [signUpWithPassword] : l'utilisateur doit confirmer son email avant
  ///    de ré-accéder à l'app en tant que compte complet)
  ///
  /// [rgpdConsent] doit être `true` — sinon lève
  /// `FirebaseAuthException(code: GoogleAuthErrorCode.consentDeclined)`
  /// avant toute tentative de link.
  Future<void> linkAnonymousWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
    required bool rgpdConsent,
  });

  /// Lie le compte anonyme courant à un compte Google, en préservant l'UID.
  ///
  /// [rgpdConsent] doit être `true` — sinon lève
  /// `FirebaseAuthException(code: GoogleAuthErrorCode.consentDeclined)`
  /// **avant** d'ouvrir le popup Google.
  Future<void> linkAnonymousWithGoogle({required bool rgpdConsent});

  /// Lie le compte anonyme courant à un compte Apple, en préservant l'UID.
  ///
  /// [rgpdConsent] doit être `true` — sinon lève
  /// `FirebaseAuthException(code: AppleAuthErrorCode.consentDeclined)`
  /// **avant** d'ouvrir le popup Apple.
  Future<void> linkAnonymousWithApple({required bool rgpdConsent});

  /// Envoie un email de réinitialisation de mot de passe.
  Future<void> sendPasswordResetEmail(String email);

  /// Confirme le reset password avec l'oobCode reçu dans l'email.
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  });

  /// Vérifie qu'un oobCode est valide et retourne l'email associé.
  Future<String> verifyPasswordResetCode(String code);

  /// Révoque la session Firebase.
  Future<void> signOut();
}

/// Détermine si une [UserCredential] correspond à un compte nouvellement créé.
///
/// Extrait en fonction injectable (plutôt qu'un accès direct à
/// `cred.additionalUserInfo?.isNewUser` dans le corps des méthodes) car les
/// packages de test doubles Firebase (`firebase_auth_mocks`) n'implémentent
/// pas `additionalUserInfo` (lève `UnimplementedError`) — l'injection permet
/// de tester la logique de rollback/provisioning sans dépendre du SDK Firebase
/// réel. En production, [_defaultIsNewUser] délègue simplement au SDK.
typedef IsNewUserResolver = bool Function(UserCredential cred);

bool _defaultIsNewUser(UserCredential cred) {
  // Fail-closed : si on ne peut pas déterminer la nouveauté du compte, on
  // REFUSE de continuer plutôt que de risquer (a) un rollback destructeur
  // (user.delete()) sur un compte existant ou (b) un nouveau compte qui
  // passe le consent gate RGPD sans rollback. La couche appelante doit
  // catch cette exception et présenter une erreur générique à l'utilisateur.
  // Les tests injectent un [IsNewUserResolver] dédié et ne passent pas par
  // cette fonction.
  final info = cred.additionalUserInfo;
  if (info == null) {
    throw FirebaseAuthException(
      code: 'baillan/cannot-determine-new-user',
      message:
          'AdditionalUserInfo missing on UserCredential — '
          'cannot safely determine if account is new.',
    );
  }
  return info.isNewUser;
}

/// Ouvre le popup OAuth de link pour un utilisateur anonyme donné.
///
/// Extrait en fonction injectable car `firebase_auth_mocks` (0.14.2) ne
/// surcharge pas `User.linkWithPopup` (méthode concrète héritée de la classe
/// réelle `User`, absente de `MockUser` → `NoSuchMethodError` en test). En
/// production, [_defaultLinkWithPopup] délègue simplement au SDK.
typedef LinkWithPopupFn =
    Future<UserCredential> Function(User user, AuthProvider provider);

Future<UserCredential> _defaultLinkWithPopup(
  User user,
  AuthProvider provider,
) => user.linkWithPopup(provider);

/// Lie un utilisateur anonyme à une [AuthCredential] (email/password ici).
///
/// Extrait en fonction injectable car `firebase_auth_mocks` (0.14.2) contient
/// un bug connu : `MockUser.linkWithCredential` construit un
/// `MockUserCredential(false, mockUser: this)` alors que `this.isAnonymous`
/// reste `true` (champ final non mutable) — l'assertion interne du package
/// (`mockUser.isAnonymous == isAnonymous`) échoue systématiquement en debug.
/// En production, [_defaultLinkWithCredential] délègue simplement au SDK.
typedef LinkWithCredentialFn =
    Future<UserCredential> Function(User user, AuthCredential credential);

Future<UserCredential> _defaultLinkWithCredential(
  User user,
  AuthCredential credential,
) => user.linkWithCredential(credential);

/// Appelle la Cloud Function callable `finalizeAnonymousUpgrade`.
///
/// Extrait en fonction injectable : il n'existe pas de test double officiel
/// pour `FirebaseFunctions`/`HttpsCallable` (contrairement à
/// `firebase_auth_mocks` ou `fake_cloud_firestore`), donc les tests
/// unitaires injectent un [FinalizeUpgradeFn] simulé plutôt que de dépendre
/// d'un backend réel.
typedef FinalizeUpgradeFn =
    Future<void> Function({
      required bool rgpdConsent,
      required String rgpdConsentVersion,
    });

/// Implémentation s'appuyant sur [FirebaseAuth] + [FirebaseFirestore].
class FirebaseAuthRepository implements AuthRepository {
  /// [functions] est optionnel : requis uniquement par le chemin de
  /// production de `linkAnonymousWith*` (construction lazy du callable HTTPS
  /// dans [_finalizeUpgrade]). Les tests qui n'exercent pas ces méthodes (ou
  /// qui injectent directement [finalizeUpgrade]) peuvent l'omettre plutôt
  /// que de mocker un `FirebaseFunctions` réel (aucun test double officiel).
  FirebaseAuthRepository(
    this._auth,
    this._firestore, {
    FirebaseFunctions? functions,
    IsNewUserResolver isNewUserResolver = _defaultIsNewUser,
    LinkWithPopupFn linkWithPopup = _defaultLinkWithPopup,
    LinkWithCredentialFn linkWithCredential = _defaultLinkWithCredential,
    FinalizeUpgradeFn? finalizeUpgrade,
  }) : _isNewUser = isNewUserResolver,
       _linkWithPopup = linkWithPopup,
       _linkWithCredential = linkWithCredential,
       _finalizeUpgrade =
           finalizeUpgrade ??
           (({required rgpdConsent, required rgpdConsentVersion}) async {
             final fn = functions;
             if (fn == null) {
               throw StateError(
                 'FirebaseAuthRepository built without FirebaseFunctions — '
                 'cannot call finalizeAnonymousUpgrade.',
               );
             }
             await fn.httpsCallable('finalizeAnonymousUpgrade').call({
               'rgpdConsent': rgpdConsent,
               'rgpdConsentVersion': rgpdConsentVersion,
             });
           });

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final IsNewUserResolver _isNewUser;
  final LinkWithPopupFn _linkWithPopup;
  final LinkWithCredentialFn _linkWithCredential;
  final FinalizeUpgradeFn _finalizeUpgrade;

  @override
  // CRITICAL fix — session-state refresh après link (BAILLAN-M1) :
  // `authStateChanges()` NE FIRE PAS sur linkWithCredential/linkWithPopup
  // (UID inchangé, Firebase ne considère pas ça comme un sign-in event). Le
  // sessionStateProvider resterait bloqué sur "anonymous" après un upgrade
  // réussi. On utilise `userChanges()` qui, lui, émet aussi sur les
  // mutations du User (link provider, email verified, displayName…) — c'est
  // un superset de `authStateChanges()`, tous les consommateurs qui font
  // `user != null` restent corrects.
  Stream<User?> get authStateChanges => _auth.userChanges();

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _log.info('signInWithPassword requested');
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
  }) async {
    _log.info('signUpWithPassword requested');
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'createUserWithEmailAndPassword returned null user',
      );
    }

    // Met à jour le profil Firebase Auth (displayName).
    await user.updateDisplayName(fullName);

    // Provisionne le doc landlords/{uid} avec consent RGPD horodaté.
    // Idempotent (`set({merge:true})`) — coexiste avec handleNewUser CF si
    // Identity Platform est activé.
    final now = FieldValue.serverTimestamp();
    await _firestore.doc('landlords/${user.uid}').set({
      'id': user.uid,
      'email': email,
      'fullName': fullName,
      'phone': null,
      'address': null,
      'isAnonymous': false,
      'subscriptionTier': 'free',
      'anonExpiresAt': null,
      'rgpdConsentAt': now,
      'rgpdConsentVersion': rgpdConsentVersion,
      'createdAt': now,
      'updatedAt': now,
      'deletedAt': null,
    }, SetOptions(merge: true));

    // Envoie l'email de vérification puis signe out : l'utilisateur devra
    // cliquer le lien reçu par email puis se reconnecter. Empêche l'accès
    // aux routes protégées via un compte non vérifié (defense in depth
    // complémentaire à `isAuthenticatedProvider` qui check `emailVerified`).
    await _sendVerificationEmail(user);
    await _auth.signOut();
  }

  @override
  Future<void> sendCurrentUserEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in user to send verification email to.',
      );
    }
    await _sendVerificationEmail(user);
  }

  Future<void> _sendVerificationEmail(User user) async {
    final origin = _safeOrigin();
    _log.info('sendEmailVerification requested (origin: $origin)');
    await user.sendEmailVerification(
      ActionCodeSettings(url: '$origin/login', handleCodeInApp: false),
    );
  }

  /// `Uri.base.origin` lève `StateError` hors des schémas http(s) (ex. les
  /// tests `flutter test` exécutés en `file://`). Fallback neutre : le lien
  /// de vérification pointera vers un chemin relatif si l'origin ne peut pas
  /// être résolu — en production (navigateur réel), l'origin http(s) est
  /// toujours disponible, ce fallback ne joue donc qu'en environnement de
  /// test.
  String _safeOrigin() {
    try {
      return Uri.base.origin;
    } on StateError {
      return '';
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    _log.info('signInWithGoogle requested');
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile');
    final cred = await _auth.signInWithPopup(provider);
    final isNewUser = _isNewUser(cred);
    if (!isNewUser) {
      // Connexion normale — un compte Baillan existait déjà pour ce Google.
      return;
    }

    // Rollback strict : aucun compte n'est autorisé à persister sans le
    // consentement RGPD explicite requis par le flow /signup.
    final user = cred.user;
    try {
      await user?.delete();
    } catch (e, st) {
      _log.severe(
        'orphan account uid=${user?.uid} created without RGPD consent — '
        'needs cleanup',
        e,
        st,
      );
    }
    try {
      await _auth.signOut();
    } catch (e, st) {
      _log.warning('signOut after rollback failed', e, st);
    }
    throw FirebaseAuthException(
      code: GoogleAuthErrorCode.newUserOnLogin,
      message: 'Google account has no associated Baillan landlord account.',
    );
  }

  @override
  Future<void> signUpWithGoogle({required bool rgpdConsent}) async {
    if (!rgpdConsent) {
      throw FirebaseAuthException(
        code: GoogleAuthErrorCode.consentDeclined,
        message: 'RGPD consent not given before Google sign-up.',
      );
    }

    _log.info('signUpWithGoogle requested');
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile');
    final cred = await _auth.signInWithPopup(provider);
    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'signInWithPopup returned null user',
      );
    }

    final isNewUser = _isNewUser(cred);
    if (!isNewUser) {
      // Compte Google déjà existant — ne jamais toucher au doc landlord
      // (préserve signupProvider/rgpdConsent d'origine).
      return;
    }

    // Le doc landlords/{uid} peut avoir été pré-provisionné par la Cloud
    // Function `beforeUserCreated` (handleNewUser) si Identity Platform est
    // activé. On lit l'état du doc pour choisir entre CREATE (CF inactive,
    // payload complet exigé par la rule CREATE) et UPDATE (CF active : la
    // rule UPDATE — firestore.rules:72-73 — interdit de toucher
    // `rgpdConsentAt` et `rgpdConsentVersion`, on n'écrit donc QUE les
    // métadonnées d'audit Google par-dessus).
    final docRef = _firestore.doc('landlords/${user.uid}');
    final snap = await docRef.get();
    final now = FieldValue.serverTimestamp();

    if (snap.exists) {
      await docRef.update({
        'signupProvider': 'google',
        'rgpdConsentSource': 'google-popup',
        'updatedAt': now,
      });
    } else {
      await docRef.set({
        'id': user.uid,
        'email': user.email,
        'fullName': user.displayName ?? '',
        'phone': null,
        'address': null,
        'isAnonymous': false,
        'subscriptionTier': 'free',
        'anonExpiresAt': null,
        'rgpdConsentAt': now,
        'rgpdConsentVersion': rgpdConsentVersion,
        'rgpdConsentSource': 'google-popup',
        'signupProvider': 'google',
        'createdAt': now,
        'updatedAt': now,
        'deletedAt': null,
      });
    }
  }

  @override
  Future<void> signInWithApple() async {
    _log.info('signInWithApple requested');
    // Scopes 'email' + 'name' — PAS de scope 'profile' (n'existe pas côté
    // Apple ; le nom complet est demandé via le scope 'name' dédié).
    final provider = OAuthProvider('apple.com')
      ..addScope('email')
      ..addScope('name');
    final cred = await _auth.signInWithPopup(provider);
    final isNewUser = _isNewUser(cred);
    if (!isNewUser) {
      // Connexion normale — un compte Baillan existait déjà pour cet Apple.
      return;
    }

    // Rollback strict : aucun compte n'est autorisé à persister sans le
    // consentement RGPD explicite requis par le flow /signup.
    final user = cred.user;
    try {
      await user?.delete();
    } catch (e, st) {
      _log.severe(
        'orphan account uid=${user?.uid} created without RGPD consent — '
        'needs cleanup',
        e,
        st,
      );
    }
    try {
      await _auth.signOut();
    } catch (e, st) {
      _log.warning('signOut after rollback failed', e, st);
    }
    throw FirebaseAuthException(
      code: AppleAuthErrorCode.newUserOnLogin,
      message: 'Apple account has no associated Baillan landlord account.',
    );
  }

  @override
  Future<void> signUpWithApple({required bool rgpdConsent}) async {
    if (!rgpdConsent) {
      throw FirebaseAuthException(
        code: AppleAuthErrorCode.consentDeclined,
        message: 'RGPD consent not given before Apple sign-up.',
      );
    }

    _log.info('signUpWithApple requested');
    final provider = OAuthProvider('apple.com')
      ..addScope('email')
      ..addScope('name');
    final cred = await _auth.signInWithPopup(provider);
    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'signInWithPopup returned null user',
      );
    }

    final isNewUser = _isNewUser(cred);
    if (!isNewUser) {
      // Compte Apple déjà existant — ne jamais toucher au doc landlord
      // (préserve signupProvider/rgpdConsent d'origine).
      return;
    }

    // Le doc landlords/{uid} peut avoir été pré-provisionné par la Cloud
    // Function `beforeUserCreated` (handleNewUser) si Identity Platform est
    // activé. On lit l'état du doc pour choisir entre CREATE (CF inactive,
    // payload complet exigé par la rule CREATE) et UPDATE (CF active : la
    // rule UPDATE — firestore.rules:72-73 — interdit de toucher
    // `rgpdConsentAt` et `rgpdConsentVersion`, on n'écrit donc QUE les
    // métadonnées d'audit Apple par-dessus).
    final docRef = _firestore.doc('landlords/${user.uid}');
    final snap = await docRef.get();
    final now = FieldValue.serverTimestamp();

    if (snap.exists) {
      await docRef.update({
        'signupProvider': 'apple',
        'rgpdConsentSource': 'apple-popup',
        'updatedAt': now,
      });
    } else {
      // Fallback fullName : Apple ne renvoie le displayName qu'à la toute
      // première autorisation OAuth pour ce couple app/Apple ID. En cas de
      // re-signup après un rollback (delete() suite à signInWithApple sur un
      // compte inconnu), `user.displayName` peut être `null` — on retombe
      // sur l'email (potentiellement un alias '@privaterelay.appleid.com'
      // si l'utilisateur a activé "Hide My Email", traité comme un email
      // normal) puis chaîne vide en dernier recours.
      await docRef.set({
        'id': user.uid,
        'email': user.email,
        'fullName': user.displayName ?? user.email ?? '',
        'phone': null,
        'address': null,
        'isAnonymous': false,
        'subscriptionTier': 'free',
        'anonExpiresAt': null,
        'rgpdConsentAt': now,
        'rgpdConsentVersion': rgpdConsentVersion,
        'rgpdConsentSource': 'apple-popup',
        'signupProvider': 'apple',
        'createdAt': now,
        'updatedAt': now,
        'deletedAt': null,
      });
    }
  }

  @override
  Future<void> signInAnonymously() async {
    _log.info('signInAnonymously requested');
    final cred = await _auth.signInAnonymously();
    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'signInAnonymously returned null user',
      );
    }

    // Provisionne landlords/{uid} si absent. Identity Platform étant
    // désactivé sur ce projet, la CF handleNewUser (beforeUserCreated) ne
    // tourne jamais : le chemin CREATE anonyme des rules est le chemin
    // nominal. Doc déjà présent = session anonyme réutilisée — on ne touche
    // à rien (anonExpiresAt est renouvelé par AnonExpiryRenewer).
    final docRef = _firestore.doc('landlords/${user.uid}');
    final snap = await docRef.get();
    if (snap.exists) return;

    final now = FieldValue.serverTimestamp();
    await docRef.set({
      'id': user.uid,
      'email': null,
      'fullName': '',
      'phone': null,
      'address': null,
      'isAnonymous': true,
      'subscriptionTier': 'anonymous',
      'anonExpiresAt': Timestamp.fromDate(
        DateTime.now().add(_anonProvisionExpiryWindow),
      ),
      'rgpdConsentAt': null,
      'rgpdConsentVersion': null,
      'createdAt': now,
      'updatedAt': now,
      'deletedAt': null,
    });
  }

  /// Garde commune aux 3 méthodes `linkAnonymousWith*` : vérifie qu'une
  /// session anonyme est bien active avant de tenter un lien. Lever un
  /// `StateError` plutôt qu'une `FirebaseAuthException` ici : ce n'est pas
  /// une erreur Firebase, c'est un bug d'appel côté UI (le bouton "Créer un
  /// compte" ne devrait jamais être branché sur ces méthodes hors contexte
  /// anonyme).
  User _requireAnonymousUser() {
    final user = _auth.currentUser;
    if (user == null || !user.isAnonymous) {
      throw StateError(
        'linkAnonymousWith* requires an active anonymous session '
        '(currentUser=${user?.uid}, isAnonymous=${user?.isAnonymous}).',
      );
    }
    return user;
  }

  Future<void> _finalizeAnonymousUpgrade({required bool rgpdConsent}) async {
    _log.info('finalizeAnonymousUpgrade callable requested');
    await _finalizeUpgrade(
      rgpdConsent: rgpdConsent,
      rgpdConsentVersion: rgpdConsentVersion,
    );
  }

  @override
  Future<void> linkAnonymousWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
    required bool rgpdConsent,
  }) async {
    if (!rgpdConsent) {
      throw FirebaseAuthException(
        code: GoogleAuthErrorCode.consentDeclined,
        message: 'RGPD consent not given before anonymous upgrade.',
      );
    }
    final anonUser = _requireAnonymousUser();
    _log.info('linkAnonymousWithEmailPassword requested');

    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    final cred = await _linkWithCredential(anonUser, credential);
    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'linkWithCredential returned null user',
      );
    }
    await user.updateDisplayName(fullName);
    await _finalizeAnonymousUpgrade(rgpdConsent: rgpdConsent);
    await _sendVerificationEmail(user);
    await _auth.signOut();
  }

  @override
  Future<void> linkAnonymousWithGoogle({required bool rgpdConsent}) async {
    if (!rgpdConsent) {
      throw FirebaseAuthException(
        code: GoogleAuthErrorCode.consentDeclined,
        message: 'RGPD consent not given before anonymous upgrade.',
      );
    }
    final anonUser = _requireAnonymousUser();
    _log.info('linkAnonymousWithGoogle requested');

    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile');
    await _linkWithPopup(anonUser, provider);
    await _finalizeAnonymousUpgrade(rgpdConsent: rgpdConsent);
  }

  @override
  Future<void> linkAnonymousWithApple({required bool rgpdConsent}) async {
    if (!rgpdConsent) {
      throw FirebaseAuthException(
        code: AppleAuthErrorCode.consentDeclined,
        message: 'RGPD consent not given before anonymous upgrade.',
      );
    }
    final anonUser = _requireAnonymousUser();
    _log.info('linkAnonymousWithApple requested');

    final provider = OAuthProvider('apple.com')
      ..addScope('email')
      ..addScope('name');
    await _linkWithPopup(anonUser, provider);
    await _finalizeAnonymousUpgrade(rgpdConsent: rgpdConsent);
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    final origin = Uri.base.origin;
    _log.info('sendPasswordResetEmail requested (origin: $origin)');
    await _auth.sendPasswordResetEmail(
      email: email,
      actionCodeSettings: ActionCodeSettings(
        url: '$origin/reset-password',
        handleCodeInApp: true,
      ),
    );
  }

  @override
  Future<String> verifyPasswordResetCode(String code) async {
    return await _auth.verifyPasswordResetCode(code);
  }

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    _log.info('confirmPasswordReset');
    await _auth.confirmPasswordReset(code: code, newPassword: newPassword);
  }

  @override
  Future<void> signOut() async {
    _log.info('signOut');
    await _auth.signOut();
  }
}

/// Provider exposant le repository d'authentification.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
    functions: FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});
