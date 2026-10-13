import 'package:flutter/widgets.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../auth/domain/plan_level.dart';

/// Libellé affichable d'un [PlanLevel] (FEAT-056) — seule source de vérité
/// pour « Pro »/« Max »/« Ultra » côté UI. Réutilisé par [ProBadge]
/// (`pro_badge.dart`), la page `/pro` (`pro_pricing_page.dart`), la section
/// abonnement du profil (`subscription_section.dart`) et les messages
/// d'upsell (limite de scénarios, taille de fichier) — jamais de chaîne
/// littérale `'Pro'`/`'Max'`/`'Ultra'` ailleurs dans l'UI.
extension PlanLevelLabel on PlanLevel {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      PlanLevel.pro => l10n.planLevelPro,
      PlanLevel.max => l10n.planLevelMax,
      PlanLevel.ultra => l10n.planLevelUltra,
    };
  }
}

/// Variante pour un id de palier brut (`'pro'`/`'max'`/`'ultra'`), tel que
/// renvoyé par le serveur (`upgradeTo` d'une erreur `file_too_large`,
/// `PlanLevelSpec.id`...). Id inconnu → l'id lui-même (filet défensif, ne
/// devrait jamais se produire avec une table à jour).
String planLevelLabelForId(BuildContext context, String levelId) {
  for (final level in PlanLevel.values) {
    if (level.id == levelId) return level.label(context);
  }
  return levelId;
}
