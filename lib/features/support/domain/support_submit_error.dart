/// Bornes de validation du formulaire « Nous contacter » (FEAT-025) —
/// mêmes valeurs que les rules Firestore `support_requests` (create-only,
/// defense in depth). Partagées entre [SupportController] (validation) et
/// `SupportSubmitErrorL10n` (message localisé, placeholder `{limit}`).
const int kSupportSubjectMaxLength = 120;
const int kSupportMessageMaxLength = 2000;

/// Bornes de la note d'un avis (FEAT-060) — mêmes valeurs que les rules.
const int kFeedbackRatingMin = 1;
const int kFeedbackRatingMax = 5;

/// Erreurs de validation/soumission du formulaire « Nous contacter »,
/// indépendantes de la locale d'affichage (FEAT-043 i18n).
///
/// **Contrainte technique** : `SupportRequestState.error` (freezed, généré
/// via `build_runner`) porte un champ `message` de type `String` — le
/// régénérer avec un type enum est hors périmètre de cette extraction
/// (nécessite de relancer `build_runner`, non disponible dans cet
/// environnement). Pattern retenu, identique à `TenantSubmitError`
/// (`lib/features/tenants/domain/tenant_submit_error.dart`) et
/// `ExpenseSubmitError`
/// (`lib/features/expenses/domain/expense_submit_error.dart`) :
/// `SupportController` stocke le **nom** de cet enum
/// (`SupportSubmitError.name`, une clé technique stable, jamais un message
/// FR) dans `SupportRequestState.error.message` ; la couche présentation
/// (`profile_support_form.dart`) le reconvertit via `SupportSubmitErrorL10n`
/// pour l'afficher.
///
/// Mêmes garanties que le pattern `ValidationError` du domaine partagé
/// (`lib/core/validation/validation_error.dart`) : aucune dépendance à
/// `BuildContext`/`AppLocalizations` ici.
enum SupportSubmitError {
  /// Le champ sujet a été laissé vide.
  subjectRequired,

  /// Le sujet dépasse [kSupportSubjectMaxLength] caractères.
  subjectTooLong,

  /// Le champ message a été laissé vide.
  messageRequired,

  /// Le message dépasse [kSupportMessageMaxLength] caractères.
  messageTooLong,

  /// Aucune note (ou note hors 1-5) pour un avis (FEAT-060).
  ratingRequired,

  /// Erreur réseau / Firestore générique lors de l'envoi.
  sendFailed;

  /// Reconstruit l'enum depuis son [name] stocké dans
  /// `SupportRequestState.error.message` — retourne [sendFailed] si
  /// absent/invalide (ne doit jamais arriver en pratique, filet de sécurité
  /// défensif).
  static SupportSubmitError fromCode(String code) {
    return SupportSubmitError.values.firstWhere(
      (e) => e.name == code,
      orElse: () => SupportSubmitError.sendFailed,
    );
  }
}
