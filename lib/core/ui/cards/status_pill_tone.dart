/// Tone sémantique d'un [StatusPill].
enum StatusPillTone {
  /// Succès, état actif, confirmé.
  success,

  /// Avertissement, action requise, délai proche.
  warning,

  /// Danger, erreur, retard, échec.
  danger,

  /// Information neutre, état en cours.
  info,

  /// Neutre, archivé, inactif.
  neutral,
}

/// Variante visuelle d'un [StatusPill].
enum StatusPillVariant {
  /// Fond pâle + texte saturé (par défaut).
  subtle,

  /// Fond saturé + texte sur fond.
  filled,

  /// Transparent + bordure colorée + texte saturé.
  outlined,
}

/// Taille d'un [StatusPill].
enum StatusPillSize {
  /// Petit : hauteur 20px, font 11px.
  sm,

  /// Moyen : hauteur 24px, font 12px (par défaut).
  md,
}
