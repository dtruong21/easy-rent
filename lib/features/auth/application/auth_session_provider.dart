import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../domain/session_state.dart';

/// Flux d'auth Firebase exposé globalement.
///
/// Toute modification (login, logout, refresh token) est automatiquement
/// propagée aux widgets et au routeur via ce provider.
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// Dérive l'état de session (3 branches, mutuellement exclusives) depuis un
/// [User] Firebase Auth potentiellement `null`.
///
/// - `null` → [SessionState.unauthenticated]
/// - `isAnonymous == true` → [SessionState.anonymous] (peu importe
///   `emailVerified`, qui n'a pas de sens pour un compte anonyme)
/// - `isAnonymous == false && emailVerified == true` →
///   [SessionState.fullyAuthenticated]
/// - `isAnonymous == false && emailVerified == false` →
///   [SessionState.unauthenticated] (compte créé mais email pas encore
///   vérifié — même traitement qu'avant BAILLAN-M1, cf. FEAT-021)
SessionState _deriveSessionState(User? user) {
  if (user == null) return SessionState.unauthenticated;
  if (user.isAnonymous) return SessionState.anonymous;
  if (user.emailVerified) return SessionState.fullyAuthenticated;
  return SessionState.unauthenticated;
}

/// État de session courant (source de vérité 3-états pour le routeur et les
/// widgets qui doivent distinguer anonyme / authentifié / non-connecté).
///
/// Pendant le chargement initial ou en cas d'erreur transitoire sur le
/// [authStateChangesProvider], on se rabat sur le `currentUser` en cache
/// pour éviter une redirection à tort.
final sessionStateProvider = Provider<SessionState>((ref) {
  final asyncState = ref.watch(authStateChangesProvider);
  return asyncState.when(
    data: _deriveSessionState,
    loading: () =>
        _deriveSessionState(ref.read(authRepositoryProvider).currentUser),
    error: (_, _) =>
        _deriveSessionState(ref.read(authRepositoryProvider).currentUser),
  );
});

/// Dérivé booléen — [true] si et seulement si [SessionState.fullyAuthenticated].
///
/// Conservé pour compatibilité avec les call-sites existants (pages
/// protégées historiques) — préférer [sessionStateProvider] pour tout
/// nouveau code qui doit distinguer anonyme de non-connecté.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(sessionStateProvider) == SessionState.fullyAuthenticated;
});
