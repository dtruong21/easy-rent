import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/card_empty_state.dart';
import '../../../../core/ui/theme/app_colors.dart';
import '../../../../core/ui/theme/app_radii.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/chart_format_provider.dart';
import '../../application/chart_period_provider.dart';
import '../../application/dashboard_provider.dart';
import '../../domain/chart_format.dart';
import '../../domain/chart_period.dart';
import '../../domain/monthly_amount.dart';
import '../chart_format_l10n.dart';
import '../chart_period_l10n.dart';

/// Graphique "Loyers" (période sélectionnable), format switchable.
///
/// Les montants mensuels viennent de [monthlyAmountsProvider], indépendant du
/// dashboard principal : changer de période (6/12/24 mois) ne recharge QUE ce
/// graphique, pas les KPI ni l'activité récente.
///
/// Deux sélecteurs dans l'en-tête, persistés séparément :
/// - Format ([chartFormatProvider]) : [ChartFormat.bars] (2 barres/mois,
///   défaut), [ChartFormat.line] (courbes), [ChartFormat.area] (aires).
/// - Période ([chartPeriodProvider]) : [ChartPeriod.m6] (défaut),
///   [ChartPeriod.m12], [ChartPeriod.m24].
///
/// Couleurs : Encaissé = [AppColors.success.solid] (vert — argent rentré) ;
/// Dû = gris pâle en barres, gris soutenu en courbes (un trait pâle serait
/// illisible).
///
/// Enveloppé dans un card container (border, radius, padding, bg surface).
/// Hauteur : 200 px desktop, 160 px mobile (<600 px).
/// Si toutes les données sont à zéro → [CardEmptyState] (toggles masqués).
class MonthlyBarchart extends ConsumerStatefulWidget {
  const MonthlyBarchart({super.key});

  @override
  ConsumerState<MonthlyBarchart> createState() => _MonthlyBarchartState();
}

class _MonthlyBarchartState extends ConsumerState<MonthlyBarchart> {
  int? _touchedGroupIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final radii = theme.extension<AppRadii>() ?? const AppRadii();
    final asyncMonths = ref.watch(monthlyAmountsProvider);
    final months = asyncMonths.valueOrNull;
    // `hasData` détermine l'affichage des toggles — même définition que
    // l'empty state de [_ChartBody] (tous les montants à zéro), sinon les
    // toggles resteraient visibles pendant que la card affiche déjà l'empty
    // state (incohérence visuelle).
    final hasData = months != null && !_isAllZero(months);

    return Container(
      padding: EdgeInsets.all(spacing.cardPaddingStandard),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(radii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChartHeader(hasData: hasData),
          const SizedBox(height: 8),
          asyncMonths.when(
            loading: () => const _ChartLoading(),
            error: (e, _) => const _ChartError(),
            data: (months) => _ChartBody(
              months: months,
              touchedGroupIndex: _touchedGroupIndex,
              onGroupTouched: (i) => setState(() => _touchedGroupIndex = i),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// En-tête : titre + sélecteurs période/format
// ---------------------------------------------------------------------------

class _ChartHeader extends ConsumerWidget {
  const _ChartHeader({required this.hasData});

  /// `true` si des montants non nuls sont chargés — masque les toggles sinon
  /// (cohérent avec le comportement historique du sélecteur de format).
  final bool hasData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final period = ref.watch(chartPeriodProvider);
    final format = ref.watch(chartFormatProvider);
    final l10n = context.l10n;

    final title = Text(
      l10n.dashboardMonthlyChartTitle,
      style: theme.textTheme.titleSmall,
    );

    if (!hasData) {
      return Row(children: [title]);
    }

    final periodSelector = SegmentedButton<ChartPeriod>(
      key: const Key('segments_chart_period'),
      segments: [
        for (final p in ChartPeriod.values)
          ButtonSegment(value: p, label: Text(p.label(context))),
      ],
      selected: {period},
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          ref.read(chartPeriodProvider.notifier).setPeriod(selection.first);
        }
      },
    );

    final formatSelector = SegmentedButton<ChartFormat>(
      key: const Key('segments_chart_format'),
      segments: [
        for (final f in ChartFormat.values)
          ButtonSegment(
            value: f,
            icon: Icon(_iconForFormat(f), size: 16),
            tooltip: f.label(context),
          ),
      ],
      selected: {format},
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          ref.read(chartFormatProvider.notifier).setFormat(selection.first);
        }
      },
    );

    // Mobile : les deux SegmentedButton côte à côte serrent trop — on les
    // enroule sur une 2e ligne via Wrap plutôt que de les comprimer.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: spacing.sm,
      runSpacing: spacing.sm,
      children: [
        title,
        Wrap(
          spacing: spacing.sm,
          runSpacing: spacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [periodSelector, formatSelector],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// États loading / error
// ---------------------------------------------------------------------------

/// Skeleton discret pendant le chargement d'une nouvelle période — évite de
/// faire clignoter toute la card (le titre + sélecteurs restent affichés par
/// [_ChartHeader], seul le corps du graphique est en cours de chargement).
class _ChartLoading extends StatelessWidget {
  const _ChartLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 160,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ChartError extends StatelessWidget {
  const _ChartError();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 160,
      child: Center(
        child: Text(
          context.l10n.dashboardMonthlyChartErrorMessage,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Corps du graphique (empty state ou chart + légende)
// ---------------------------------------------------------------------------

class _ChartBody extends StatelessWidget {
  const _ChartBody({
    required this.months,
    required this.touchedGroupIndex,
    required this.onGroupTouched,
  });

  final List<MonthlyAmount> months;
  final int? touchedGroupIndex;
  final ValueChanged<int?> onGroupTouched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final isEmpty = _isAllZero(months);
    final l10n = context.l10n;

    if (isEmpty) {
      return CardEmptyState(
        icon: Icons.bar_chart_outlined,
        title: l10n.dashboardMonthlyChartEmptyTitle,
        message: l10n.dashboardMonthlyChartEmptyMessage,
      );
    }

    final localeName = Localizations.localeOf(context).toString();

    return Consumer(
      builder: (context, ref, _) {
        final format = ref.watch(chartFormatProvider);
        final builder = _ChartBuilder(
          months: months,
          touchedGroupIndex: touchedGroupIndex,
          onGroupTouched: onGroupTouched,
          l10n: l10n,
          localeName: localeName,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final chartHeight = constraints.maxWidth > 600 ? 200.0 : 160.0;
                return SizedBox(
                  height: chartHeight,
                  child: switch (format) {
                    ChartFormat.bars => BarChart(
                      builder.buildBarChart(theme, colors),
                    ),
                    ChartFormat.line => LineChart(
                      builder.buildLineChart(theme, colors, filled: false),
                    ),
                    ChartFormat.area => LineChart(
                      builder.buildLineChart(theme, colors, filled: true),
                    ),
                  },
                );
              },
            ),
            const SizedBox(height: 8),
            _Legend(
              encaissedLabel: l10n.dashboardMonthlyChartEncaisseLabel,
              dueLabel: l10n.dashboardMonthlyChartDueLabel,
              encaissedColor: colors.success.solid,
              // Un trait gris pâle serait invisible : les courbes utilisent
              // le gris soutenu, la légende suit le format affiché.
              dueColor: format == ChartFormat.bars
                  ? colors.neutral.surface
                  : colors.neutral.solid,
            ),
          ],
        );
      },
    );
  }
}

/// Construit les données fl_chart (barres/courbes) à partir des [months].
///
/// Extrait dans une classe dédiée (plutôt que des méthodes de State) car
/// [_ChartBody] est désormais un widget sans state — [touchedGroupIndex] et
/// [onGroupTouched] remplacent l'ancien `setState` local de `_MonthlyBarchartState`.
class _ChartBuilder {
  const _ChartBuilder({
    required this.months,
    required this.touchedGroupIndex,
    required this.onGroupTouched,
    required this.l10n,
    required this.localeName,
  });

  final List<MonthlyAmount> months;
  final int? touchedGroupIndex;
  final ValueChanged<int?> onGroupTouched;

  /// Localisations résolues, capturées dans le widget parent (a un
  /// [BuildContext]) — [_ChartBuilder] ne construit pas de widgets, il
  /// produit des données `fl_chart` consommées par des callbacks sans
  /// contexte (`getTooltipItem`, `getTitlesWidget`).
  final AppLocalizations l10n;

  /// Nom de la locale active (ex. `fr`, `en`), utilisé par [DateFormat] pour
  /// l'abréviation du mois sur l'axe des abscisses.
  final String localeName;

  BarChartData buildBarChart(ThemeData theme, AppColors colors) {
    final encaissedColor = colors.success.solid;
    final dueColor = colors.neutral.surface;
    final groups = <BarChartGroupData>[];

    for (int i = 0; i < months.length; i++) {
      final m = months[i];
      final isTouched = touchedGroupIndex == i;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: m.encaissedCents / 100,
              color: encaissedColor.withAlpha(isTouched ? 255 : 200),
              width: 10,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
            BarChartRodData(
              toY: m.dueCents / 100,
              color: dueColor.withAlpha(isTouched ? 255 : 200),
              width: 10,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
    }

    final yInterval = _yInterval();

    return BarChartData(
      barGroups: groups,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final label = rodIndex == 0
                ? l10n.dashboardMonthlyChartEncaisseLabel
                : l10n.dashboardMonthlyChartDueLabel;
            final euros = _formatCompactEuros((rod.toY * 100).round());
            return BarTooltipItem(
              '$label\n$euros',
              TextStyle(color: theme.colorScheme.onSurface, fontSize: 11),
            );
          },
        ),
        touchCallback: (event, response) {
          if (response?.spot != null && event is FlTapUpEvent) {
            onGroupTouched(response!.spot!.touchedBarGroupIndex);
          } else {
            onGroupTouched(null);
          }
        },
      ),
      titlesData: _titlesData(theme, yInterval),
      gridData: _gridData(theme, yInterval),
      borderData: FlBorderData(show: false),
    );
  }

  /// Courbes "Encaissé / Dû" — [filled] ajoute l'aire sous chaque courbe.
  LineChartData buildLineChart(
    ThemeData theme,
    AppColors colors, {
    required bool filled,
  }) {
    List<FlSpot> spotsOf(int Function(MonthlyAmount) cents) => [
      for (int i = 0; i < months.length; i++)
        FlSpot(i.toDouble(), cents(months[i]) / 100),
    ];

    LineChartBarData series(List<FlSpot> spots, Color color) =>
        LineChartBarData(
          spots: spots,
          color: color,
          barWidth: 2.5,
          isCurved: true,
          curveSmoothness: 0.25,
          preventCurveOverShooting: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: filled, color: color.withAlpha(46)),
        );

    final yInterval = _yInterval();

    return LineChartData(
      minY: 0,
      lineBarsData: [
        series(spotsOf((m) => m.encaissedCents), colors.success.solid),
        // Gris soutenu (pas le gris pâle des barres) : un trait pâle sur
        // fond surface serait illisible.
        series(spotsOf((m) => m.dueCents), colors.neutral.solid),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                '${s.barIndex == 0 ? l10n.dashboardMonthlyChartEncaisseLabel : l10n.dashboardMonthlyChartDueLabel}\n'
                '${_formatCompactEuros((s.y * 100).round())}',
                TextStyle(color: theme.colorScheme.onSurface, fontSize: 11),
              ),
          ],
        ),
      ),
      titlesData: _titlesData(theme, yInterval),
      gridData: _gridData(theme, yInterval),
      borderData: FlBorderData(show: false),
    );
  }

  // ---------------------------------------------------------------------
  // Axes, grille, échelle — partagés entre les trois formats
  // ---------------------------------------------------------------------

  double _yInterval() {
    final maxY = months
        .expand((m) => [m.encaissedCents / 100, m.dueCents / 100])
        .fold(0.0, (prev, v) => v > prev ? v : prev);
    return maxY > 0 ? _niceInterval(maxY) : 100.0;
  }

  /// Densité des libellés de l'axe X : avec 12/24 mois, afficher tous les
  /// mois ferait chevaucher le texte. On vise ~6 libellés max, soit un
  /// libellé tous les `ceil(months.length / 6)` mois. Les tooltips restent
  /// disponibles sur TOUTES les barres/points, indépendamment des libellés.
  int get _labelStride => (months.length / 6).ceil().clamp(1, months.length);

  FlTitlesData _titlesData(ThemeData theme, double yInterval) {
    final stride = _labelStride;
    return FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 50,
          interval: yInterval,
          getTitlesWidget: (value, meta) => Text(
            _formatCompactEuros((value * 100).round()),
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          // 1 = un tick par mois (les courbes génèrent sinon des ticks
          // fractionnaires ; sans effet sur les barres, x entiers). La
          // densité d'affichage est filtrée dans getTitlesWidget via [stride].
          interval: 1,
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i >= months.length) {
              return const SizedBox.shrink();
            }
            // N'affiche qu'un libellé tous les [stride] mois, en gardant
            // toujours le dernier mois (mois courant) visible.
            final isLastMonth = i == months.length - 1;
            if (i % stride != 0 && !isLastMonth) {
              return const SizedBox.shrink();
            }
            final m = months[i];
            final label = _shortMonth(m.month, localeName);
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          },
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  FlGridData _gridData(ThemeData theme, double yInterval) {
    return FlGridData(
      drawHorizontalLine: true,
      drawVerticalLine: false,
      horizontalInterval: yInterval,
      getDrawingHorizontalLine: (value) => FlLine(
        color: theme.colorScheme.outlineVariant.withAlpha(80),
        strokeWidth: 1,
      ),
    );
  }

  static double _niceInterval(double maxY) {
    if (maxY <= 0) return 100;
    final magnitude = maxY.toString().length - 1;
    final base = _pow10(magnitude);
    if (maxY / base <= 2) return base / 2;
    if (maxY / base <= 5) return base;
    return base * 2;
  }

  static double _pow10(int exp) {
    double r = 1;
    for (int i = 0; i < exp; i++) {
      r *= 10;
    }
    return r;
  }
}

/// `true` si tous les [MonthlyAmount] de la liste ont encaissé ET dû à zéro.
///
/// Définition partagée entre [_ChartHeader] (masque les toggles) et
/// [_ChartBody] (affiche le [CardEmptyState]) — une liste VIDE (période sans
/// aucun document Firestore) est considérée comme "tout à zéro" (`every` sur
/// liste vide est vacuously true), cohérent avec le comportement historique.
bool _isAllZero(List<MonthlyAmount> months) =>
    months.every((m) => m.encaissedCents == 0 && m.dueCents == 0);

/// Icône associée à chaque [ChartFormat], utilisée dans le toggle d'en-tête.
IconData _iconForFormat(ChartFormat format) => switch (format) {
  ChartFormat.bars => Icons.bar_chart,
  ChartFormat.line => Icons.show_chart,
  ChartFormat.area => Icons.area_chart_outlined,
};

/// Retourne l'abréviation du mois dans la locale active (1=jan. ... 12=déc.).
///
/// FEAT-043 : délègue à `DateFormat.MMM(localeName)` de `package:intl`
/// (remplace l'ancien tableau FR en dur) — l'année importe peu ici, seul le
/// mois est extrait de l'objet [DateTime] factice.
String _shortMonth(int month, String localeName) {
  if (month < 1 || month > 12) return '';
  return DateFormat.MMM(localeName).format(DateTime(2024, month));
}

String _formatCompactEuros(int cents) {
  final euros = cents / 100;
  if (euros >= 1000) {
    final k = euros / 1000;
    final formatted = k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1);
    return '${formatted.replaceAll('.', ',')}k €';
  }
  return '${euros.toStringAsFixed(0)} €';
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.encaissedLabel,
    required this.dueLabel,
    required this.encaissedColor,
    required this.dueColor,
  });
  final String encaissedLabel;
  final String dueLabel;
  final Color encaissedColor;
  final Color dueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendChip(color: encaissedColor, label: encaissedLabel),
        const SizedBox(width: 16),
        _LegendChip(color: dueColor, label: dueLabel),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
