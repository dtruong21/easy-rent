/// Erreurs de validation génériques, indépendantes de la locale d'affichage.
///
/// **Pattern FEAT-043 (i18n)** : les validateurs (`lib/core/utils/
/// *_validators.dart`) sont des fonctions pures testées sans
/// `BuildContext` — ils ne doivent jamais dépendre d'`AppLocalizations`.
/// Un validateur qui a besoin d'exposer un message localisable retourne cet
/// enum ; la couche présentation (widget, qui a un `BuildContext`) le
/// traduit via l'extension `ValidationErrorL10n.message` (voir
/// `validation_error_l10n.dart`).
///
/// Ceci ne remplace PAS tous les validateurs existants d'un coup (ampleur
/// hors périmètre de la foundation, cf. `docs/plans/FEAT-043-i18n.md` R2) —
/// c'est l'exemple de référence pour l'extraction module par module à venir.
/// Voir aussi `lib/l10n/l10n_convention.dart` pour la convention de nommage
/// des clés ARB associées (préfixe `validation*`).
enum ValidationError {
  /// Champ obligatoire laissé vide.
  required,

  /// Adresse email dont le format ne correspond pas à un email valide.
  invalidEmail,
}
