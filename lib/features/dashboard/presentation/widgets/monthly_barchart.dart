import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/cards/card_empty_state.dart';
import '../../../../core/ui/theme/app_colors.dart';
import '../../../../core/ui/theme/app_radii.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../application/chart_format_provider.dart';
import '../../domain/chart_format.dart';
import '../../domain/monthly_amount.dart';

/// Graphique 6 mois "Encaissé / Dû", format switchable.
///
/// Trois formats via le toggle d'en-tête, persistés ([chartFormatProvider]) :
/// - [ChartFormat.bars] : 2 barres côte à côte par mois (défaut)
/// - [ChartFormat.line] : 2 courbes (tendance)
/// - [ChartFormat.area] : courbes + aires remplies (volume)
///
/// Couleurs : Encaissé = [AppColors.success.solid] (vert — argent rentré) ;
/// Dû = gris pâle en barres, gris soutenu en courbes (un trait pâle serait
/// illisible).
///
/// Enveloppé dans un card container (border, radius, padding, bg surface).
/// Hauteur : 200 px desktop, 160 px mobile (<600 px).
/// Si toutes les données sont à zéro → [CardEmptyState] (toggle masqué).
class MonthlyBarchart extends ConsumerStatefulWidget {
  const MonthlyBarchart({super.key, required this.months});

  final List<MonthlyAmount> months;

  @override
  ConsumerState<MonthlyBarchart> createState() => _MonthlyBarchartState();
}

class _MonthlyBarchartState extends ConsumerState<MonthlyBarchart> {
  int? _touchedGroupIndex;

  static IconData _iconFor(ChartFormat format) => switch (format) {
    ChartFormat.bars => Icons.bar_chart,
    ChartFormat.line => Icons.show_chart,
    ChartFormat.area => Icons.area_chart_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final radii = theme.extension<AppRadii>() ?? const AppRadii();
    final colors = theme.extension<AppColors>()!;
    final format = ref.watch(chartFormatProvider);
    final isEmpty = widget.months.every(
      (m) => m.encaissedCents == 0 && m.dueCents == 0,
    );

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
          Row(
            children: [
              Text(
                'Loyers — 6 derniers mois',
                style: theme.textTheme.titleSmall,
              ),
              const Spacer(),
              if (!isEmpty)
                SegmentedButton<ChartFormat>(
                  key: const Key('segments_chart_format'),
                  segments: [
                    for (final f in ChartFormat.values)
                      ButtonSegment(
                        value: f,
                        icon: Icon(_iconFor(f), size: 16),
                        tooltip: f.labelFr,
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
                      ref
                          .read(chartFormatProvider.notifier)
                          .setFormat(selection.first);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (isEmpty)
            const CardEmptyState(
              icon: Icons.bar_chart_outlined,
              title: "Pas encore d'historique",
              message: 'Les loyers apparaîtront ici dès le 1er paiement.',
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final chartHeight = constraints.maxWidth > 600 ? 200.0 : 160.0;
                return SizedBox(
                  height: chartHeight,
                  child: switch (format) {
                    ChartFormat.bars => BarChart(_buildBarChart(theme, colors)),
                    ChartFormat.line => LineChart(
                      _buildLineChart(theme, colors, filled: false),
                    ),
                    ChartFormat.area => LineChart(
                      _buildLineChart(theme, colors, filled: true),
                    ),
                  },
                );
              },
            ),
            const SizedBox(height: 8),
            _Legend(
              encaissedColor: colors.success.solid,
              // Un trait gris pâle serait invisible : les courbes utilisent
              // le gris soutenu, la légende suit le format affiché.
              dueColor: format == ChartFormat.bars
                  ? colors.neutral.surface
                  : colors.neutral.solid,
            ),
          ],
        ],
      ),
    );
  }

  BarChartData _buildBarChart(ThemeData theme, AppColors colors) {
    final encaissedColor = colors.success.solid;
    final dueColor = colors.neutral.surface;
    final groups = <BarChartGroupData>[];

    for (int i = 0; i < widget.months.length; i++) {
      final m = widget.months[i];
      final isTouched = _touchedGroupIndex == i;
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
            final label = rodIndex == 0 ? 'Encaissé' : 'Dû';
            final euros = _formatCompactEuros((rod.toY * 100).round());
            return BarTooltipItem(
              '$label\n$euros',
              TextStyle(color: theme.colorScheme.onSurface, fontSize: 11),
            );
          },
        ),
        touchCallback: (event, response) {
          setState(() {
            if (response?.spot != null && event is FlTapUpEvent) {
              _touchedGroupIndex = response!.spot!.touchedBarGroupIndex;
            } else {
              _touchedGroupIndex = null;
            }
          });
        },
      ),
      titlesData: _titlesData(theme, yInterval),
      gridData: _gridData(theme, yInterval),
      borderData: FlBorderData(show: false),
    );
  }

  /// Courbes "Encaissé / Dû" — [filled] ajoute l'aire sous chaque courbe.
  LineChartData _buildLineChart(
    ThemeData theme,
    AppColors colors, {
    required bool filled,
  }) {
    List<FlSpot> spotsOf(int Function(MonthlyAmount) cents) => [
      for (int i = 0; i < widget.months.length; i++)
        FlSpot(i.toDouble(), cents(widget.months[i]) / 100),
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
                '${s.barIndex == 0 ? 'Encaissé' : 'Dû'}\n'
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
    final maxY = widget.months
        .expand((m) => [m.encaissedCents / 100, m.dueCents / 100])
        .fold(0.0, (prev, v) => v > prev ? v : prev);
    return maxY > 0 ? _niceInterval(maxY) : 100.0;
  }

  FlTitlesData _titlesData(ThemeData theme, double yInterval) {
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
          // 1 = un libellé par mois (les courbes génèrent sinon des ticks
          // fractionnaires ; sans effet sur les barres, x entiers).
          interval: 1,
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i >= widget.months.length) {
              return const SizedBox.shrink();
            }
            final m = widget.months[i];
            final label = _shortMonthFr(m.month);
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

/// Retourne l'abréviation FR du mois (1=jan. ... 12=déc.).
///
/// Utilisation locale manuelle pour éviter la dépendance sur
/// les données de locale intl qui nécessitent une initialisation explicite.
String _shortMonthFr(int month) {
  const shorts = [
    '',
    'jan.',
    'fév.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sep.',
    'oct.',
    'nov.',
    'déc.',
  ];
  if (month < 1 || month > 12) return '';
  return shorts[month];
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
  const _Legend({required this.encaissedColor, required this.dueColor});
  final Color encaissedColor;
  final Color dueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendChip(color: encaissedColor, label: 'Encaissé'),
        const SizedBox(width: 16),
        _LegendChip(color: dueColor, label: 'Dû'),
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
