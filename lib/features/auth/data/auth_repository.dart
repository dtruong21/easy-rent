import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'google_auth_exception.dart';

final _log = Logger('AuthRepository');

/// Version actuelle du texte de consentement RGPD présenté à l'utilisateur.
///
/// Format : 'vN-YYYY-MM' — à incrémenter à chaque mise à jour du texte de
/// politique de confidentialité ou des finalités de traitement. Persisté
/// dans landlords.rgpdConsentVersion (champ immuable post-création).
/// **Doit rester synchronisé avec functions/src/auth/handle_new_user.ts**.
const String rgpdConsentVersion = 'v1-2026-06';

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
  ///
  /// Si Identity Platform `beforeUserCreated` est activé, la Cloud Function
  /// crée déjà le doc landlords ; le `set({merge:true})` client garantit
  /// l'idempotence sans casser le flow quand IP est désactivé.
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
  });

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

/// Implémentation s'appuyant sur [FirebaseAuth] + [FirebaseFirestore].
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(
    this._auth,
    this._firestore, {
    IsNewUserResolver isNewUserResolver = _defaultIsNewUser,
  }) : _isNewUser = isNewUserResolver;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final IsNewUserResolver _isNewUser;

  @override
  Stream<User?> get authStateChanges => _auth.authStateChanges();

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
      'rgpdConsentAt': now,
      'rgpdConsentVersion': rgpdConsentVersion,
      'createdAt': now,
      'updatedAt': now,
      'deletedAt': null,
    }, SetOptions(merge: true));
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
  );
});
