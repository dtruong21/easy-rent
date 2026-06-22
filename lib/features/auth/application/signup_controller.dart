import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/email_validator.dart';
import '../../../core/utils/password_validator.dart';
import '../data/auth_error_mapper.dart';
import '../data/auth_repository.dart';
import '../domain/signup_page_state.dart';

final _log = Logger('SignupController');

class SignupController extends StateNotifier<SignupPageState> {
  SignupController(this._repository) : super(const SignupPageState.idle());

  final AuthRepository _repository;

  Future<void> signUp({
    required String fullName,
    required String email,
    required String password,
    required String confirmPassword,
    required bool rgpdConsent,
  }) async {
    if (fullName.trim().isEmpty) {
      state = const SignupPageState.error(message: 'Nom complet requis');
      return;
    }
    if (!EmailValidator.isValid(email)) {
      state = const SignupPageState.error(message: 'Adresse email invalide');
      return;
    }
    final passwordError = PasswordValidator.validate(password);
    if (passwordError != null) {
      state = SignupPageState.error(message: passwordError);
      return;
    }
    if (password != confirmPassword) {
      state = const SignupPageState.error(
        message: 'Les mots de passe ne correspondent pas',
      );
      return;
    }
    if (!rgpdConsent) {
      state = const SignupPageState.error(
        message: 'Vous devez accepter la politique de confidentialité',
      );
      return;
    }

    state = const SignupPageState.submitting();
    try {
      await _repository.signUpWithPassword(
        email: email.trim(),
        password: password,
        fullName: fullName.trim(),
      );
      // Email confirmation obligatoire → on ne redirige pas directement.
      state = const SignupPageState.awaitingConfirmation();
      _log.info('Signup réussi — email de confirmation envoyé');
    } on AuthException catch (e, st) {
      _log.warning('AuthException signup', e, st);
      state = SignupPageState.error(message: AuthErrorMapper.fromException(e));
    } catch (e, st) {
      _log.severe('Erreur inattendue signup', e, st);
      state = const SignupPageState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }
}

final signupControllerProvider =
    StateNotifierProvider<SignupController, SignupPageState>((ref) {
      return SignupController(ref.read(authRepositoryProvider));
    });
