import 'package:freezed_annotation/freezed_annotation.dart';

part 'delete_account_state.freezed.dart';

/// État UI du flux de suppression de compte (FEAT-045).
///
/// [working] couvre toute la séquence (réauthentification → révocation
/// Apple éventuelle → callable de purge) : une seule étape visible pour
/// l'utilisateur, pas de granularité intermédiaire.
///
/// [success] : le compte n'existe plus et la session locale est fermée —
/// la page redirige vers la landing (le routeur a déjà basculé l'état de
/// session sur `unauthenticated`).
@freezed
sealed class DeleteAccountState with _$DeleteAccountState {
  const factory DeleteAccountState.idle() = _Idle;
  const factory DeleteAccountState.working() = _Working;
  const factory DeleteAccountState.success() = _Success;
  const factory DeleteAccountState.error({required String message}) = _Error;
}
