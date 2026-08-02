/// Copy de la page `/pro` dérivée de la table de droits (FEAT-056 §2) —
/// fonctions pures, aucun état, aucune dépendance Riverpod. Extrait de
/// [ProPricingPage] pour respecter la limite de 200 lignes par widget
/// (CLAUDE.md) : ces helpers ne construisent aucun `Widget` interactif,
/// seulement du texte déjà traduit à partir des valeurs **lues dans la
/// table**, jamais codées en dur (backlog `docs/backlog/056-abonnements-pro-max-ultra.md`
/// §5, plan `docs/plans/FEAT-056-multi-tier-subscriptions.md` §8.4).
library;

import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../auth/domain/plan_matrix.g.dart';

int _bytesToMb(int? bytes) => ((bytes ?? 0) / (1024 * 1024)).round();

/// Accroche (« tagline ») d'un palier payant.
String proPricingTaglineFor(BuildContext context, String levelId) {
  final l10n = context.l10n;
  return switch (levelId) {
    'pro' => l10n.proPricingProTagline,
    'max' => l10n.proPricingMaxTagline,
    'ultra' => l10n.proPricingUltraTagline,
    _ => '',
  };
}

/// Bullets de la carte Gratuit.
List<String> proPricingFreeBullets(BuildContext context) {
  final l10n = context.l10n;
  const key = PlanMatrix.freeKey;
  return [
    l10n.proPricingBulletCoreQuota(
      PlanMatrix.quotaLimit(key, PlanQuota.properties) ?? 0,
      PlanMatrix.quotaLimit(key, PlanQuota.tenants) ?? 0,
      PlanMatrix.quotaLimit(key, PlanQuota.activeLeases) ?? 0,
    ),
    l10n.proPricingBulletDocuments(
      PlanMatrix.quotaLimit(key, PlanQuota.documents) ?? 0,
    ),
    l10n.proPricingBulletReceipts,
    l10n.proPricingBulletPaymentsExpensesDashboard,
  ];
}

/// Bullets d'un palier payant (`'pro'` | `'max'` | `'ultra'`).
List<String> proPricingBulletsFor(BuildContext context, String levelId) {
  return switch (levelId) {
    'pro' => _proBullets(context),
    'max' => _maxBullets(context),
    'ultra' => _ultraBullets(context),
    _ => const [],
  };
}

List<String> _proBullets(BuildContext context) {
  final l10n = context.l10n;
  const key = 'pro';
  return [
    l10n.proPricingBulletCoreQuota(
      PlanMatrix.quotaLimit(key, PlanQuota.properties) ?? 0,
      PlanMatrix.quotaLimit(key, PlanQuota.tenants) ?? 0,
      PlanMatrix.quotaLimit(key, PlanQuota.activeLeases) ?? 0,
    ),
    l10n.proPricingBulletDocuments(
      PlanMatrix.quotaLimit(key, PlanQuota.documents) ?? 0,
    ),
    l10n.proPricingBulletScenarios(
      PlanMatrix.quotaLimit(key, PlanQuota.scenarios) ?? 0,
    ),
    l10n.proPricingBulletChargeRegularization,
    l10n.proPricingBulletScenarioComparison,
    l10n.proPricingBulletSupportStandard,
  ];
}

List<String> _maxBullets(BuildContext context) {
  final l10n = context.l10n;
  const key = 'max';
  final sizeMb = _bytesToMb(
    PlanMatrix.quotaLimit(key, PlanQuota.documentMaxBytes),
  );
  return [
    l10n.proPricingBulletCoreQuota(
      PlanMatrix.quotaLimit(key, PlanQuota.properties) ?? 0,
      PlanMatrix.quotaLimit(key, PlanQuota.tenants) ?? 0,
      PlanMatrix.quotaLimit(key, PlanQuota.activeLeases) ?? 0,
    ),
    l10n.proPricingBulletDocumentsWithSize(
      PlanMatrix.quotaLimit(key, PlanQuota.documents) ?? 0,
      sizeMb,
    ),
    l10n.proPricingBulletScenarios(
      PlanMatrix.quotaLimit(key, PlanQuota.scenarios) ?? 0,
    ),
    l10n.proPricingBulletPaymentReminders,
    l10n.proPricingBulletListings,
    l10n.proPricingBulletSupportPriority,
  ];
}

List<String> _ultraBullets(BuildContext context) {
  final l10n = context.l10n;
  final sizeMb = _bytesToMb(
    PlanMatrix.quotaLimit('ultra', PlanQuota.documentMaxBytes),
  );
  return [
    l10n.proPricingBulletUnlimitedCore,
    l10n.proPricingBulletAccountingExport,
    l10n.proPricingBulletCollaborators,
    l10n.proPricingBulletDocumentSizeOnly(sizeMb),
    l10n.proPricingBulletSupportDedicated,
  ];
}
