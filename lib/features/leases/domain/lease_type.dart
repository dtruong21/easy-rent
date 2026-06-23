/// Types de bail — enum Dart fermé aligné sur le CHECK SQL.
///
/// IMPORTANT : si une nouvelle valeur est ajoutée côté SQL (CHECK constraint
/// sur `leases.lease_type`), elle DOIT être ajoutée ici aussi.
/// Le fallback [unfurnished] tolère gracieusement une valeur SQL inconnue.
enum LeaseType {
  unfurnished,
  furnished,
  mobility,
  student;

  /// Valeur stockée en base (correspond exactement au CHECK SQL).
  String get sqlValue => name;

  /// Libellé français affiché dans l'UI.
  String get labelFr => switch (this) {
    LeaseType.unfurnished => 'Vide (non meublé)',
    LeaseType.furnished => 'Meublé',
    LeaseType.mobility => 'Mobilité',
    LeaseType.student => 'Étudiant',
  };

  /// Durée légale minimale en mois (info indicative UI).
  int get legalMinDurationMonths => switch (this) {
    LeaseType.unfurnished => 36, // 3 ans
    LeaseType.furnished => 12, // 1 an
    LeaseType.mobility => 1, // 1-10 mois
    LeaseType.student => 9, // 9 mois
  };

  /// Dépôt de garantie maximum légal en mois de loyer HC.
  ///
  /// [mobility] : 0 = pas de dépôt de garantie autorisé légalement.
  int get maxDepositMonths => switch (this) {
    LeaseType.unfurnished => 1,
    LeaseType.furnished => 2,
    LeaseType.mobility => 0,
    LeaseType.student => 1,
  };

  /// Texte indicatif affiché sous le champ "Type de bail" dans le formulaire.
  String get formHelperText => switch (this) {
    LeaseType.unfurnished => 'Bail vide : durée min 3 ans · DG max = 1 mois HC',
    LeaseType.furnished => 'Bail meublé : durée min 1 an · DG max = 2 mois HC',
    LeaseType.mobility =>
      'Bail mobilité : 1 à 10 mois · pas de dépôt de garantie',
    LeaseType.student => 'Bail étudiant : 9 mois · DG max = 1 mois HC',
  };

  /// Convertit une valeur SQL vers l'enum Dart.
  ///
  /// Retourne [unfurnished] si [value] est null ou inconnue —
  /// tolérance défensive pour backward compat (données legacy sans lease_type).
  static LeaseType fromSql(String? value) {
    if (value == null) return LeaseType.unfurnished;
    return LeaseType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => LeaseType.unfurnished,
    );
  }
}
