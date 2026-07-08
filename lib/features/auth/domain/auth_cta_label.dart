/// Libellés des CTA de rebond affichés sous un message d'erreur auth
/// (FEAT-043 i18n).
///
/// **Contrainte technique** : `LoginPageState.error`/`SignupPageState.error`
/// (freezed) portent un champ `ctaLabel` de type `String?` — le régénérer
/// avec un type enum est hors périmètre (nécessite de relancer
/// `build_runner`, non disponible dans cet environnement). Pattern identique
/// à [AuthError] (`lib/features/auth/domain/auth_error.dart`) :
/// `LoginController`/`SignupController` stockent le **nom** de cet enum
/// dans `ctaLabel` ; la couche présentation (`auth_cta_label_l10n.dart`) le
/// reconvertit via [AuthCtaLabelL10n] pour l'afficher sur le bouton.
enum AuthCtaLabel {
  /// Rebond vers `/signup` (ex. Google/Apple sign-in sans compte Baillan
  /// associé, `AuthError.googleNewUserOnLogin`/`appleNewUserOnLogin`).
  createAccount,

  /// Rebond vers `/login` (ex. `account-exists-with-different-credential`
  /// au signup — un compte existe déjà via un autre moyen).
  signIn;

  /// Reconstruit l'enum depuis son [name] stocké dans `ctaLabel` — retourne
  /// `null` si absent/invalide (pas de filet [unknown] ici : `ctaLabel` est
  /// déjà nullable, un code invalide masque simplement le bouton CTA).
  static AuthCtaLabel? fromCode(String? code) {
    if (code == null) return null;
    for (final value in AuthCtaLabel.values) {
      if (value.name == code) return value;
    }
    return null;
  }
}
