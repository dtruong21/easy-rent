import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _log = Logger('AuthRepository');

/// Contrat public : les widgets et providers consomment cette interface,
/// jamais l'implémentation directement (facilite les mocks dans les tests).
abstract interface class AuthRepository {
  /// Flux d'événements d'authentification Supabase (login, logout, refresh, etc.).
  Stream<AuthState> get authStateChanges;

  /// Session active, ou [null] si non authentifié.
  Session? get currentSession;

  /// Envoie un magic link à [email].
  ///
  /// - Crée le compte si inexistant (`shouldCreateUser` vaut [true] par défaut).
  /// - [emailRedirectTo] est dérivé de l'origine courante de l'app (auto dev/prod).
  /// - Lève une [AuthException] (ou autre) si Supabase renvoie une erreur.
  Future<void> sendMagicLink(String email);

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
  Future<void> sendMagicLink(String email) async {
    // emailRedirectTo est dérivé de Uri.base.origin à l'exécution :
    // - en dev local : http://localhost:xxxx
    // - en prod PWA  : https://easyrent.web.app (ou autre domaine)
    // Aucune config par env nécessaire : correspond automatiquement à l'origine.
    final redirectTo = '${Uri.base.origin}/';
    // L'email n'est PAS logué (donnée personnelle RGPD).
    _log.info('sendMagicLink requested (redirectTo: $redirectTo)');
    await _client.auth.signInWithOtp(email: email, emailRedirectTo: redirectTo);
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
