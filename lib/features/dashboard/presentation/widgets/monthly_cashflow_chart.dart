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
import '../../domain/monthly_cashflow.dart';
import '../chart_format_l10n.dart';
import '../chart_period_l10n.dart';

/// Graphique "Cash-flow mensuel" (période sélectionnable), format switchable.
///
/// Remplace l'ancien barchart « Loyers » (encaissé vs dû) : un loyer est
/// fixe, le voir en barres n'apprenait rien au bailleur qui le connaît déjà
/// de tête. Ce graphique montre le cash flow **réel** de chaque mois — loyers
/// encaissés moins dépenses non récupérables réellement engagées — qui, lui,
/// n'est jamais connu à l'avance.
///
/// Les données viennent de [monthlyCashflowProvider], indépendant du
/// dashboard principal : changer de période (6/12/24 mois) ne recharge QUE ce
/// graphique, pas les KPI ni l'activité récente.
///
/// **Ne pas confondre avec la section « Rentabilité portfolio » juste
/// au-dessus** : celle-ci affiche un cash flow LISSÉ (moyenne sur 12 mois
/// glissants, avec bascule réel/prévisionnel par catégorie de charge) — ce
/// graphique-ci montre le réel BRUT mois par mois, forcément plus irrégulier
/// (une grosse facture de travaux peut créer un mois franchement négatif).
/// Les deux sont légitimes et ne se contredisent pas ; le sous-titre
/// ([AppLocalizations.dashboardMonthlyChartMethodologyCaption]) le rappelle
/// explicitement pour ne jamais laisser l'utilisateur croire à une erreur.
///
/// Deux sélecteurs dans l'en-tête, persistés séparément :
/// - Format ([chartFormatProvider]) : [ChartFormat.bars] (1 barre/mois,
///   défaut — seul format qui montre clairement un mois négatif),
///   [ChartFormat.line] (courbe), [ChartFormat.area] (aire).
/// - Période ([chartPeriodProvider]) : [ChartPeriod.m6] (défaut),
///   [ChartPeriod.m12], [ChartPeriod.m24].
///
/// Couleurs : cash flow positif = [AppColors.success], négatif =
/// [AppColors.danger] — jamais de constante brute (`Colors.green` etc.), ces
/// deux tons portent des variantes claire ET sombre.
///
/// Un mois sans AUCUNE donnée (`MonthlyCashflow.hasData == false`) diffère
/// d'un mois à zéro net mesuré : la barre "zéro mesuré" affiche un trait
/// plat neutre visible, la barre "sans donnée" reste un vide (rien à
/// mesurer) — la nuance reste accessible en infobulle au survol/tap.
///
/// Enveloppé dans un card container (border, radius, padding, bg surface).
/// Hauteur : 200 px desktop, 160 px mobile (<600 px).
/// Si aucun mois de la période n'a de donnée → [CardEmptyState] (toggles
/// masqués).
class MonthlyCashflowChart extends ConsumerStatefulWidget {
  const MonthlyCashflowChart({super.key});

  @override
  ConsumerState<MonthlyCashflowChart> createState() =>
      _MonthlyCashflowChartState();
}

class _MonthlyCashflowChartState extends ConsumerState<MonthlyCashflowChart> {
  int? _touchedGroupIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final radii = theme.extension<AppRadii>() ?? const AppRadii();
    final asyncMonths = ref.watch(monthlyCashflowProvider);
    final months = asyncMonths.valueOrNull;
    // `hasData` détermine l'affichage des toggles — même définition que
    // l'empty state de [_ChartBody] (aucun mois avec des données), sinon les
    // toggles resteraient visibles pendant que la card affiche déjà l'empty
    // state (incohérence visuelle).
    final hasData = months != null && !_isAllEmpty(months);

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
          if (months != null && _hasNoExpenseAtAll(months)) ...[
            const SizedBox(height: 8),
            const _NoExpenseNote(),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// En-tête : titre + sous-titre méthodologique + sélecteurs période/format
// ---------------------------------------------------------------------------

class _ChartHeader extends ConsumerWidget {
  const _ChartHeader({required this.hasData});

  /// `true` si au moins un mois avec des données est chargé — masque les
  /// toggles sinon (cohérent avec le comportement historique du sélecteur de
  /// format).
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
    final selectorsRow = Wrap(
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        selectorsRow,
        const SizedBox(height: 4),
        // Différencie explicitement ce graphique (réel, brut, non lissé) de
        // la section « Rentabilité portfolio » juste au-dessus (cash flow
        // lissé sur 12 mois glissants) — sans ça, un mois franchement
        // négatif ici pourrait sembler contredire un cash flow agrégé positif
        // là-haut.
        Text(
          l10n.dashboardMonthlyChartMethodologyCaption,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
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

/// Note affichée sous le graphique quand la période ne contient AUCUNE dépense.
///
/// Le cash-flow égale alors les loyers encaissés, ce qui donne l'impression que
/// les dépenses sont ignorées. Cette note lève l'ambiguïté — signalée en
/// recette, où le calcul était juste mais rien ne l'expliquait.
class _NoExpenseNote extends StatelessWidget {
  const _NoExpenseNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            context.l10n.dashboardMonthlyChartNoExpenseNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
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

  final List<MonthlyCashflow> months;
  final int? touchedGroupIndex;
  final ValueChanged<int?> onGroupTouched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final isEmpty = _isAllEmpty(months);
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
              positiveLabel: l10n.dashboardMonthlyChartPositiveLabel,
              negativeLabel: l10n.dashboardMonthlyChartNegativeLabel,
              positiveColor: colors.success.solid,
              negativeColor: colors.danger.solid,
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
/// [onGroupTouched] remplacent l'ancien `setState` local de `_MonthlyCashflowChartState`.
class _ChartBuilder {
  const _ChartBuilder({
    required this.months,
    required this.touchedGroupIndex,
    required this.onGroupTouched,
    required this.l10n,
    required this.localeName,
  });

  final List<MonthlyCashflow> months;
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

  /// Fraction de l'intervalle Y utilisée comme hauteur du trait plat qui
  /// signale un mois « zéro net mesuré » (données présentes, solde nul) — un
  /// vrai zéro ne dessinerait sinon aucun pixel, indiscernable d'un mois
  /// « sans donnée » (qui, lui, reste un vide volontaire).
  static const double _zeroMarkerFraction = 0.03;

  BarChartData buildBarChart(ThemeData theme, AppColors colors) {
    final bounds = _yBounds();
    final groups = <BarChartGroupData>[];

    for (int i = 0; i < months.length; i++) {
      final m = months[i];
      final isTouched = touchedGroupIndex == i;
      final color = _colorFor(m, colors);
      final height = _barHeightFor(m, bounds.interval);
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              fromY: 0,
              toY: height,
              color: color.withAlpha(isTouched ? 255 : 200),
              width: 14,
              borderRadius: height >= 0
                  ? const BorderRadius.vertical(top: Radius.circular(4))
                  : const BorderRadius.vertical(bottom: Radius.circular(4)),
            ),
          ],
        ),
      );
    }

    return BarChartData(
      barGroups: groups,
      minY: bounds.minY,
      maxY: bounds.maxY,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            return BarTooltipItem(
              _tooltipText(months[groupIndex], l10n),
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
      titlesData: _titlesData(theme, bounds.interval),
      gridData: _gridData(theme, bounds.interval),
      borderData: FlBorderData(show: false),
      extraLinesData: bounds.minY < 0
          ? _zeroLine(colors)
          : const ExtraLinesData(),
    );
  }

  /// Courbe unique de cash flow net — [filled] ajoute l'aire sous la courbe,
  /// bornée à la ligne zéro des deux côtés (`applyCutOffY`/`cutOffY: 0`)
  /// plutôt qu'au bord du graphique, pour un rendu correct quand la courbe
  /// passe sous zéro.
  LineChartData buildLineChart(
    ThemeData theme,
    AppColors colors, {
    required bool filled,
  }) {
    final bounds = _yBounds();
    final spots = [
      for (int i = 0; i < months.length; i++)
        FlSpot(i.toDouble(), months[i].netCents / 100),
    ];

    // Un seul trait (pas de segmentation par signe : fl_chart ne permet pas
    // de colorer un `LineChartBarData` par tronçon selon le signe des
    // valeurs) — le signe reste porté par la couleur de chaque point
    // ([FlDotCirclePainter] ci-dessous) et par le tooltip.
    final lineColor = theme.colorScheme.primary;

    final series = LineChartBarData(
      spots: spots,
      color: lineColor,
      barWidth: 2.5,
      isCurved: true,
      curveSmoothness: 0.25,
      preventCurveOverShooting: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) {
          final m = months[index];
          return FlDotCirclePainter(
            radius: m.hasData ? 3.5 : 2.5,
            color: _colorFor(m, colors),
            strokeWidth: 0,
          );
        },
      ),
      belowBarData: BarAreaData(
        show: filled,
        color: lineColor.withAlpha(46),
        applyCutOffY: true,
        cutOffY: 0,
      ),
    );

    return LineChartData(
      minY: bounds.minY,
      maxY: bounds.maxY,
      lineBarsData: [series],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                _tooltipText(months[s.x.toInt()], l10n),
                TextStyle(color: theme.colorScheme.onSurface, fontSize: 11),
              ),
          ],
        ),
      ),
      titlesData: _titlesData(theme, bounds.interval),
      gridData: _gridData(theme, bounds.interval),
      borderData: FlBorderData(show: false),
      extraLinesData: bounds.minY < 0
          ? _zeroLine(colors)
          : const ExtraLinesData(),
    );
  }

  // ---------------------------------------------------------------------
  // Couleur / hauteur / tooltip — partagés bars + line/area
  // ---------------------------------------------------------------------

  /// Couleur sémantique d'un mois : succès si net positif, danger si négatif,
  /// neutre si net exactement zéro (mesuré) ou si le mois n'a aucune donnée.
  static Color _colorFor(MonthlyCashflow m, AppColors colors) {
    if (!m.hasData) return colors.neutral.surface;
    if (m.netCents > 0) return colors.success.solid;
    if (m.netCents < 0) return colors.danger.solid;
    return colors.neutral.solid;
  }

  /// Hauteur (en euros, signée) de la barre représentant [m].
  ///
  /// - Sans donnée : 0 — vide volontaire, rien à mesurer.
  /// - Zéro net mesuré : trait plat minimal visible (sinon indiscernable du
  ///   cas précédent, cf. [_zeroMarkerFraction]).
  /// - Sinon : le net réel, signé (peut dépasser sous l'axe des abscisses).
  static double _barHeightFor(MonthlyCashflow m, double interval) {
    if (!m.hasData) return 0;
    final net = m.netCents / 100;
    if (net == 0) return interval * _zeroMarkerFraction;
    return net;
  }

  static String _tooltipText(MonthlyCashflow m, AppLocalizations l10n) {
    if (!m.hasData) return l10n.dashboardMonthlyChartNoDataLabel;
    return _formatCompactEuros(m.netCents);
  }

  static ExtraLinesData _zeroLine(AppColors colors) => ExtraLinesData(
    horizontalLines: [
      HorizontalLine(
        y: 0,
        color: colors.neutral.solid.withAlpha(140),
        strokeWidth: 1,
        dashArray: const [4, 4],
      ),
    ],
  );

  // ---------------------------------------------------------------------
  // Axes, grille, échelle — partagés entre les trois formats
  // ---------------------------------------------------------------------

  /// Bornes Y « nice » (alignées sur [interval]) englobant systématiquement
  /// zéro — même quand tous les mois sont positifs (bas = 0, comportement
  /// historique) ou tous négatifs (haut = 0, tout le graphique sous l'axe).
  ({double minY, double maxY, double interval}) _yBounds() {
    double maxNet = 0;
    double minNet = 0;
    for (final m in months) {
      if (!m.hasData) continue;
      final net = m.netCents / 100;
      if (net > maxNet) maxNet = net;
      if (net < minNet) minNet = net;
    }
    final maxAbs = maxNet > -minNet ? maxNet : -minNet;
    final interval = maxAbs > 0 ? _niceInterval(maxAbs) : 100.0;
    final maxY = maxNet > 0
        ? (maxNet / interval).ceilToDouble() * interval
        : 0.0;
    final minY = minNet < 0
        ? (-minNet / interval).ceilToDouble() * -interval
        : 0.0;
    return (minY: minY, maxY: maxY, interval: interval);
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
                  // Mois sans donnée : libellé atténué — signal visuel
                  // discret que ce mois n'a rien à montrer.
                  color: m.hasData
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurfaceVariant.withAlpha(120),
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

/// `true` si aucun mois de la liste n'a de donnée (`hasData == false`
/// partout) — une liste VIDE (période sans aucun document Firestore) est
/// vacuously "tout vide" (`every` sur liste vide), cohérent avec le
/// comportement historique.
///
/// Diffère volontairement de "tous les mois à net zéro" : un mois mesuré à
/// zéro net (loyers encaissés == dépenses non récupérables) a des données,
/// il ne doit PAS déclencher l'empty state.
bool _isAllEmpty(List<MonthlyCashflow> months) =>
    months.every((m) => !m.hasData);

/// `true` si la période contient des données MAIS aucune dépense.
///
/// Sans cette mention, le graphique affiche exactement les loyers encaissés et
/// paraît ignorer les dépenses — ce qui a été signalé en recette comme un bug
/// alors que le calcul était juste : le bailleur n'avait simplement saisi
/// aucune dépense. Le chiffre était bon, c'est l'absence d'explication qui
/// coûtait cher.
///
/// Volontairement muet sur une période entièrement vide : `_ChartBody` affiche
/// déjà son propre état vide, et empiler deux messages brouillerait le propos.
bool _hasNoExpenseAtAll(List<MonthlyCashflow> months) =>
    !_isAllEmpty(months) &&
    months.every((m) => m.nonRecoverableExpenseCents == 0);

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

/// Formate des centimes (signés) en euros compacts : `"1,2k €"`, `"-450 €"`.
String _formatCompactEuros(int cents) {
  final sign = cents < 0 ? '-' : '';
  final euros = cents.abs() / 100;
  if (euros >= 1000) {
    final k = euros / 1000;
    final formatted = k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1);
    return '$sign${formatted.replaceAll('.', ',')}k €';
  }
  return '$sign${euros.toStringAsFixed(0)} €';
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.positiveLabel,
    required this.negativeLabel,
    required this.positiveColor,
    required this.negativeColor,
  });
  final String positiveLabel;
  final String negativeLabel;
  final Color positiveColor;
  final Color negativeColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _LegendChip(color: positiveColor, label: positiveLabel),
        _LegendChip(color: negativeColor, label: negativeLabel),
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
