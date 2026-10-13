/// Sollicitation d'avis (FEAT-060) : demande de note native dans les apps,
/// carte « Votre avis compte » sur le web.
library;

/// Ancienneté minimale du compte complet avant toute sollicitation.
const Duration kReviewMinAccountAge = Duration(days: 15);

/// Délai minimal entre deux sollicitations automatiques sur un appareil.
const Duration kReviewSolicitationInterval = Duration(days: 120);

/// PURE — vrai si l'on peut solliciter un avis maintenant : compte complet,
/// créé depuis au moins [kReviewMinAccountAge], au moins un bien, et aucune
/// sollicitation depuis [kReviewSolicitationInterval] sur cet appareil.
bool isReviewSolicitationEligible({
  required bool fullyAuthenticated,
  required DateTime accountCreatedAt,
  required bool hasProperty,
  required DateTime? lastSolicitedAt,
  required DateTime now,
}) {
  if (!fullyAuthenticated || !hasProperty) return false;
  if (now.difference(accountCreatedAt) < kReviewMinAccountAge) return false;
  if (lastSolicitedAt != null &&
      now.difference(lastSolicitedAt) < kReviewSolicitationInterval) {
    return false;
  }
  return true;
}
