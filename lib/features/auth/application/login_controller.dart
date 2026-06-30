import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/utils/email_validator.dart';
import '../data/auth_error_mapper.dart';
import '../data/auth_repository.dart';
import '../domain/login_page_state.dart';

final _log = Logger('LoginController');

class LoginController extends StateNotifier<LoginPageState> {
  LoginController(this._repository) : super(const LoginPageState.idle());

  final AuthRepository _repository;

  Future<void> signIn({required String email, required String password}) async {
    if (!EmailValidator.isValid(email)) {
      state = const LoginPageState.error(message: 'Adresse email invalide');
      return;
    }
    if (password.isEmpty) {
      state = const LoginPageState.error(message: 'Mot de passe requis');
      return;
    }

    state = const LoginPageState.submitting();
    try {
      await _repository.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      // Succès : authStateChanges déclenche GoRouter via GoRouterRefreshStream
      // → redirect vers /. Pas besoin de changer le state ici.
      state = const LoginPageState.idle();
    } on FirebaseAuthException catch (e, st) {
      _log.warning('FirebaseAuthException signIn (code=${e.code})', e, st);
      state = LoginPageState.error(message: AuthErrorMapper.fromException(e));
    } catch (e, st) {
      _log.severe('Erreur inattendue signIn', e, st);
      state = const LoginPageState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _repository.signOut();
    } catch (e, st) {
      _log.severe('Erreur lors de signOut', e, st);
    } finally {
      state = const LoginPageState.idle();
    }
  }
}

final loginControllerProvider =
    StateNotifierProvider<LoginController, LoginPageState>((ref) {
      return LoginController(ref.read(authRepositoryProvider));
    });
