import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/ui/cards/card_empty_state.dart';
import '../../../../core/ui/theme/app_colors.dart';
import '../../../../core/ui/theme/app_radii.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../domain/monthly_amount.dart';

/// Mini-barchart 6 mois "Encaissé / Dû".
///
/// Chaque mois = 2 barres côte à côte :
/// - Encaissé : [AppColors.success.solid] (vert — argent rentré)
/// - Dû       : [AppColors.neutral.surface] (gris pâle)
///
/// Enveloppé dans un card container (border, radius, padding, bg surface).
/// Hauteur : 200 px desktop, 160 px mobile (<600 px).
/// Si toutes les données sont à zéro → [CardEmptyState].
class MonthlyBarchart extends StatefulWidget {
  const MonthlyBarchart({super.key, required this.months});

  final List<MonthlyAmount> months;

  @override
  State<MonthlyBarchart> createState() => _MonthlyBarchartState();
}

class _MonthlyBarchartState extends State<MonthlyBarchart> {
  int? _touchedGroupIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final radii = theme.extension<AppRadii>() ?? const AppRadii();
    final colors = theme.extension<AppColors>()!;
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
          Text('Loyers — 6 derniers mois', style: theme.textTheme.titleSmall),
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
                  child: BarChart(_buildBarChart(theme, colors)),
                );
              },
            ),
            const SizedBox(height: 8),
            _Legend(
              encaissedColor: colors.success.solid,
              dueColor: colors.neutral.surface,
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

    final maxY = widget.months
        .expand((m) => [m.encaissedCents / 100, m.dueCents / 100])
        .fold(0.0, (prev, v) => v > prev ? v : prev);
    final yInterval = maxY > 0 ? _niceInterval(maxY) : 100.0;

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
      titlesData: FlTitlesData(
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
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),
      gridData: FlGridData(
        drawHorizontalLine: true,
        drawVerticalLine: false,
        horizontalInterval: yInterval,
        getDrawingHorizontalLine: (value) => FlLine(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
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
