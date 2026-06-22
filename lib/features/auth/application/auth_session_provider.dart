import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';

/// Flux de session Supabase exposé globalement.
///
/// Toute modification (login, logout, refresh token) est automatiquement
/// propagée aux widgets et au routeur via ce provider.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// Dérivé booléen — [true] si une session active existe.
///
/// Utilisé par le routeur pour évaluer la garde `/login ⇄ /`.
final isAuthenticatedProvider = Provider<bool>((ref) {
  final asyncState = ref.watch(authStateChangesProvider);
  return asyncState.when(
    data: (authState) => authState.session != null,
    loading: () {
      // Pendant le chargement initial, on se base sur la session en cache.
      final repo = ref.read(authRepositoryProvider);
      return repo.currentSession != null;
    },
    error: (error, stack) {
      // En cas d'erreur transitoire du stream, on se rabat sur la session en
      // cache plutôt que de renvoyer false — évite une redirection vers /login
      // à tort quand une session valide existe côté client.
      final repo = ref.read(authRepositoryProvider);
      return repo.currentSession != null;
    },
  );
});

/// Dérivé booléen — [true] si l'event d'auth courant est [passwordRecovery].
///
/// Supabase émet [AuthChangeEvent.passwordRecovery] avec une session temporaire
/// quand l'utilisateur clique le lien de reset password. Dans cet état, la
/// session existe mais l'utilisateur n'est PAS réellement authentifié — il doit
/// d'abord changer son mot de passe. Ce provider permet au routeur de forcer
/// la redirection vers `/reset-password` au lieu de laisser passer vers `/`.
///
/// Repasse à [false] lors de [AuthChangeEvent.userUpdated] (password changé)
/// ou [AuthChangeEvent.signedOut].
final isInPasswordRecoveryProvider = Provider<bool>((ref) {
  final asyncState = ref.watch(authStateChangesProvider);
  return asyncState.maybeWhen(
    data: (authState) => authState.event == AuthChangeEvent.passwordRecovery,
    orElse: () => false,
  );
});
