import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/domain/plan_matrix.g.dart';

/// Tableau comparatif Gratuit/Pro/Max/Ultra affiché sous les 4 cartes en
/// desktop (`>= Breakpoints.tablet`, FEAT-056 §8.1 — patron repris de
/// `ScenarioComparisonTable`, FEAT-055).
///
/// Limité aux 6 plafonds de volume (la table de config, jamais codés en
/// dur) : les features (régularisation, comparaison de scénarios, support...)
/// restent visibles dans les bullets des cartes juste au-dessus, inutile de
/// les dupliquer ici.
class PlanComparisonTable extends StatelessWidget {
  const PlanComparisonTable({super.key});

  static const _columns = ['free', 'pro', 'max', 'ultra'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final headers = [
      l10n.planLevelFree,
      l10n.planLevelPro,
      l10n.planLevelMax,
      l10n.planLevelUltra,
    ];
    final rows = <(String, PlanQuota)>[
      (l10n.proPricingRowProperties, PlanQuota.properties),
      (l10n.proPricingRowTenants, PlanQuota.tenants),
      (l10n.proPricingRowLeases, PlanQuota.activeLeases),
      (l10n.proPricingRowDocuments, PlanQuota.documents),
      (l10n.proPricingRowDocumentSize, PlanQuota.documentMaxBytes),
      (l10n.proPricingRowScenarios, PlanQuota.scenarios),
    ];

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        0: const IntrinsicColumnWidth(),
        for (var i = 1; i <= _columns.length; i++) i: const FlexColumnWidth(),
      },
      border: TableBorder(
        horizontalInside: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.4),
        ),
      ),
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            for (final header in headers)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Text(
                  header,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        for (final (label, quota) in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 24, 12),
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final column in _columns)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Text(
                    _formatValue(l10n, quota, column),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  String _formatValue(AppLocalizations l10n, PlanQuota quota, String column) {
    final value = PlanMatrix.quotaLimit(column, quota);
    if (value == null) return l10n.proQuotaUnlimited;
    if (quota == PlanQuota.documentMaxBytes) return ByteFormat.format(value);
    return value.toString();
  }
}
