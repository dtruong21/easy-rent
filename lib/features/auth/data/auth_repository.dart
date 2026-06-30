import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

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

/// Implémentation s'appuyant sur [FirebaseAuth] + [FirebaseFirestore].
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

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
