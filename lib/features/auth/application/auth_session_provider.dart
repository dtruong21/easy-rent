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
