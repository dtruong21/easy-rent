import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

/// Flux d'auth Firebase exposé globalement.
///
/// Toute modification (login, logout, refresh token) est automatiquement
/// propagée aux widgets et au routeur via ce provider.
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// Dérivé booléen — [true] si un utilisateur est authentifié.
///
/// Utilisé par le routeur pour évaluer la garde `/login ⇄ /`. Pendant le
/// chargement initial ou en cas d'erreur transitoire, on se rabat sur le
/// currentUser en cache pour éviter une redirection vers /login à tort.
final isAuthenticatedProvider = Provider<bool>((ref) {
  final asyncState = ref.watch(authStateChangesProvider);
  return asyncState.when(
    data: (user) => user != null,
    loading: () => ref.read(authRepositoryProvider).currentUser != null,
    error: (_, _) => ref.read(authRepositoryProvider).currentUser != null,
  );
});
