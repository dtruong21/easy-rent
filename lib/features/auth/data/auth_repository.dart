import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _log = Logger('AuthRepository');

/// Contrat public : les widgets et providers consomment cette interface,
/// jamais l'implémentation directement (facilite les mocks dans les tests).
abstract interface class AuthRepository {
  /// Flux d'événements d'authentification Supabase (login, logout, refresh…).
  Stream<AuthState> get authStateChanges;

  /// Session active, ou [null] si non authentifié.
  Session? get currentSession;

  /// Connecte l'utilisateur via email + mot de passe.
  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  /// Crée un compte et envoie un email de confirmation.
  ///
  /// [fullName] est transmis dans les métadonnées utilisateur pour que
  /// le trigger Supabase `handle_new_user` alimente la table `landlords`.
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
  });

  /// Envoie un email de réinitialisation de mot de passe.
  ///
  /// [redirectTo] est dérivé dynamiquement de [Uri.base.origin] pour
  /// fonctionner sans config en dev local, staging et prod.
  Future<void> sendPasswordResetEmail(String email);

  /// Met à jour le mot de passe de la session courante (flow reset password).
  Future<void> updatePassword(String newPassword);

  /// Révoque la session courante côté Supabase.
  Future<void> signOut();
}

/// Implémentation concrète s'appuyant sur [SupabaseClient].
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  @override
  Session? get currentSession => _client.auth.currentSession;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _log.info('signInWithPassword requested');
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
  }) async {
    // emailRedirectTo est dérivé dynamiquement de Uri.base.origin pour
    // fonctionner sans config en dev local, staging et prod automatiquement —
    // symétrique à ce qui est fait dans sendPasswordResetEmail.
    final emailRedirectTo = '${Uri.base.origin}/login';
    _log.info(
      'signUpWithPassword requested (emailRedirectTo: $emailRedirectTo)',
    );
    await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
      emailRedirectTo: emailRedirectTo,
    );
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    // redirectTo est calculé à l'exécution → fonctionne sans config en
    // dev local (localhost:XXXX), staging et prod automatiquement.
    final redirectTo = '${Uri.base.origin}/reset-password';
    _log.info('sendPasswordResetEmail requested (redirectTo: $redirectTo)');
    await _client.auth.resetPasswordForEmail(email, redirectTo: redirectTo);
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    _log.info('updatePassword requested');
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  @override
  Future<void> signOut() async {
    _log.info('signOut');
    await _client.auth.signOut();
  }
}

/// Provider exposant le repository d'authentification.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(Supabase.instance.client);
});
