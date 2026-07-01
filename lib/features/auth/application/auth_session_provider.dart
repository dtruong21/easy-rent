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

/// Dérivé booléen — [true] si un utilisateur est authentifié ET son email
/// est vérifié.
///
/// Utilisé par le routeur pour évaluer la garde `/login ⇄ /`. Un compte
/// nouvellement créé avec email/mot de passe qui n'a pas cliqué le lien de
/// vérification est traité comme non authentifié (defense in depth
/// complémentaire au signOut côté signup et à la re-vérification côté
/// login). Les comptes Google ont `emailVerified=true` par construction.
///
/// Pendant le chargement initial ou en cas d'erreur transitoire, on se
/// rabat sur le currentUser en cache pour éviter une redirection à tort.
bool _isVerified(User? user) => user != null && user.emailVerified;

final isAuthenticatedProvider = Provider<bool>((ref) {
  final asyncState = ref.watch(authStateChangesProvider);
  return asyncState.when(
    data: _isVerified,
    loading: () => _isVerified(ref.read(authRepositoryProvider).currentUser),
    error: (_, _) => _isVerified(ref.read(authRepositoryProvider).currentUser),
  );
});
