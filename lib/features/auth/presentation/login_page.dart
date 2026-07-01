import 'package:easyrent/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'widgets/login_form.dart';

/// Page de connexion — concept "La Page du Registre".
///
/// Métaphore : la page IS un feuillet de registre notarial posé sur un bureau
/// d'encre. Un grand rectangle crème (max 800px) centré, cartouche éditorial
/// en tête ("Baillan." + "art. 1 — Session"), filet olive hairline, aphorisme
/// en Cochin italique au-dessus du formulaire, paraphe SVG et pagination
/// verticale dans la marge extérieure gauche (desktop). Ombre portée très
/// douce sous la feuille pour l'effet "posé". Animation d'entrée : fade-up
/// de la feuille, tracé du filet olive gauche-droite, apparition différée du
/// paraphe (comme s'il venait d'être signé).
///
/// Concept issu du redesign 2026-07-01 (workflow parallèle 4 concepts + jury
/// brand + Flutter engineer). Le juge Flutter a scoré 8.5/10 et flag les
/// watchouts appliqués ici : disableAnimations gate, RepaintBoundary autour
/// du paraphe, ExcludeSemantics sur le watermark, opacités d'ombre bornées.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  static const _kDesktopBreakpoint = 900.0;
  static const _kSheetMaxWidth = 800.0;

  late final AnimationController _controller;
  late final Animation<double> _sheetFade;
  late final Animation<Offset> _sheetSlide;
  late final Animation<double> _ruleDraw;
  late final Animation<double> _paraphInk;

  bool _animationsStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    // La feuille apparaît en premier (0 -> 0.5).
    _sheetFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    );
    _sheetSlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
          ),
        );

    // Puis le filet olive se trace (0.35 -> 0.75).
    _ruleDraw = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.75, curve: Curves.easeInOutCubic),
    );

    // Enfin le paraphe s'écrit (0.65 -> 1.0).
    _paraphInk = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.65, 1.0, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect de `prefers-reduced-motion` (accessibilité) : si l'utilisateur
    // a demandé des animations réduites, on saute directement à l'état final
    // sans jouer la séquence fade/trace/écrit-paraphe. On lit la préférence
    // ici (pas dans initState) car MediaQuery est disponible via
    // didChangeDependencies.
    if (_animationsStarted) return;
    _animationsStarted = true;
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (disableAnimations) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Le bureau (background derrière la feuille) s'inverse selon
    // l'ambiance : sombre la nuit, clair le jour. C'est le seul élément qui
    // change selon le mode.
    final Color deskColor = isDark ? AppTheme.ink : AppTheme.paperDeep;

    // La feuille elle-même NE S'INVERSE PAS. Un papier est un objet
    // physique, il reste papier peu importe l'éclairage ambiant. En dark
    // mode, on lit "l'acte à la lampe de bureau" — la feuille est
    // toujours illuminée papier/encre, le décor autour est sombre. Cette
    // approche : (a) préserve la métaphore "acte notarial posé", (b)
    // garantit que le FilledButton olive et le texte ink restent lisibles
    // quel que soit le mode.
    const Color sheetColor = AppTheme.cream;
    const Color inkColor = AppTheme.ink;
    const Color mutedColor = AppTheme.inkMuted;
    const Color oliveTone = AppTheme.olive;
    const Color ruleTone = AppTheme.ruleStrong;

    return Scaffold(
      backgroundColor: deskColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= _kDesktopBreakpoint;
          // Force le thème LIGHT dans le sous-arbre de la feuille : ainsi
          // le LoginForm interne (FilledButton, TextField, IconButton…)
          // pioche partout les couleurs light-mode et reste cohérent avec
          // le papier même quand l'utilisateur est en dark mode global.
          return Theme(
            data: AppTheme.light,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 40 : 16,
                  vertical: isDesktop ? 48 : 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _kSheetMaxWidth + (isDesktop ? 140 : 0),
                    ),
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        return FadeTransition(
                          opacity: _sheetFade,
                          child: SlideTransition(
                            position: _sheetSlide,
                            child: _buildRegisterSpread(
                              context: context,
                              isDesktop: isDesktop,
                              sheetColor: sheetColor,
                              inkColor: inkColor,
                              mutedColor: mutedColor,
                              oliveTone: oliveTone,
                              ruleTone: ruleTone,
                              isAmbientDark: isDark,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Compose la double-page : marge extérieure (paraphe + pagination) à
  /// gauche + feuille centrale. Sur mobile la marge est masquée.
  ///
  /// [isAmbientDark] : le fond bureau est-il en mode sombre ? Sert à ajuster
  /// deux choses hors du sous-arbre thème light forcé : (a) la couleur des
  /// éléments de marge (paraphe + pagination) qui vivent SUR le bureau, pas
  /// sur la feuille, (b) l'intensité de l'ombre portée de la feuille.
  Widget _buildRegisterSpread({
    required BuildContext context,
    required bool isDesktop,
    required Color sheetColor,
    required Color inkColor,
    required Color mutedColor,
    required Color oliveTone,
    required Color ruleTone,
    required bool isAmbientDark,
  }) {
    // Sur le bureau (autour de la feuille), les éléments de marge doivent
    // s'adapter à l'ambiance : olive pâle sur bureau sombre, olive dense sur
    // bureau clair. Sinon ils disparaissent.
    final Color marginMuted = isAmbientDark
        ? AppTheme.oliveSoft
        : AppTheme.inkMuted;
    final Color marginOlive = isAmbientDark
        ? AppTheme.oliveSoft
        : AppTheme.olive;

    final sheet = _buildSheet(
      context: context,
      isDesktop: isDesktop,
      sheetColor: sheetColor,
      inkColor: inkColor,
      mutedColor: mutedColor,
      oliveTone: oliveTone,
      ruleTone: ruleTone,
      isAmbientDark: isAmbientDark,
    );

    if (!isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sheet,
          const SizedBox(height: 20),
          _buildFooterPagination(mutedColor: marginMuted),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Padding(
            padding: const EdgeInsets.only(top: 72, right: 24),
            child: _buildOuterMargin(
              mutedColor: marginMuted,
              oliveTone: marginOlive,
            ),
          ),
        ),
        Expanded(child: sheet),
        // Marge droite symétrique pour équilibrer visuellement la "reliure".
        const SizedBox(width: 120),
      ],
    );
  }

  /// La marge extérieure gauche (desktop uniquement) : paraphe SVG + pagination
  /// verticale. C'est là qu'on met la signature notariale.
  Widget _buildOuterMargin({
    required Color mutedColor,
    required Color oliveTone,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Pagination verticale "p. 1"
        RotatedBox(
          quarterTurns: 3,
          child: Text(
            'p. 1  —  Session',
            style: TextStyle(
              fontFamily: 'Cochin',
              fontFamilyFallback: _serifFallback,
              fontStyle: FontStyle.italic,
              fontSize: 13,
              letterSpacing: 1.2,
              color: mutedColor,
            ),
          ),
        ),
        const SizedBox(height: 48),
        // Paraphe calligraphique, s'écrit après la feuille. RepaintBoundary
        // isole le SVG pour éviter des repaints inutiles pendant la saisie
        // du formulaire (le fade opacity ne repeindra que cette sous-scene).
        RepaintBoundary(
          child: FadeTransition(
            opacity: _paraphInk,
            child: SizedBox(
              width: 96,
              height: 72,
              child: SvgPicture.string(
                _paraphSvg(oliveTone),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// La feuille de registre elle-même : cartouche + filet + aphorisme + form.
  Widget _buildSheet({
    required BuildContext context,
    required bool isDesktop,
    required Color sheetColor,
    required Color inkColor,
    required Color mutedColor,
    required Color oliveTone,
    required Color ruleTone,
    required bool isAmbientDark,
  }) {
    // Ombre portée : plus marquée sur bureau sombre pour que la feuille
    // décolle bien du fond ; plus subtile sur bureau clair. Opacités
    // toujours bornées pour ne pas passer en look Material Card 3.
    final shadow = isAmbientDark
        ? const [
            BoxShadow(
              color: Color(
                0x66000000,
              ), // ~40% — feuille éclairée sur bureau nuit
              blurRadius: 48,
              offset: Offset(0, 20),
              spreadRadius: -6,
            ),
            BoxShadow(
              color: Color(0x33000000), // ~20% halo proche
              blurRadius: 12,
              offset: Offset(0, 4),
              spreadRadius: -2,
            ),
          ]
        : const [
            BoxShadow(
              color: Color(0x0F000000), // ~6%
              blurRadius: 36,
              offset: Offset(0, 14),
              spreadRadius: -10,
            ),
            BoxShadow(
              color: Color(0x08000000), // ~3%
              blurRadius: 8,
              offset: Offset(0, 2),
              spreadRadius: -2,
            ),
          ];

    return Container(
      constraints: const BoxConstraints(maxWidth: _kSheetMaxWidth),
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: BorderRadius.circular(2),
        boxShadow: shadow,
        border: Border.all(color: ruleTone.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Stack(
        children: [
          // Watermark filigrane subtil — "Registre" tramé sur toute la feuille.
          // ExcludeSemantics pour ne pas polluer les lecteurs d'écran (c'est
          // décoratif, pas contenu).
          Positioned.fill(
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _WatermarkPainter(
                        // Feuille toujours en light-mode → opacité fixe.
                        color: inkColor.withValues(alpha: 0.028),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 72 : 28,
              vertical: isDesktop ? 64 : 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCartouche(
                  context: context,
                  inkColor: inkColor,
                  mutedColor: mutedColor,
                ),
                const SizedBox(height: 20),
                // Filet olive hairline animé.
                AnimatedBuilder(
                  animation: _ruleDraw,
                  builder: (context, _) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _ruleDraw.value,
                        child: Container(
                          height: 1,
                          color: oliveTone.withValues(alpha: 0.55),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                // Deuxième filet plus fin — double-filet typographique.
                Container(
                  height: 0.5,
                  color: oliveTone.withValues(alpha: 0.25),
                ),
                SizedBox(height: isDesktop ? 44 : 32),
                _buildAphorism(mutedColor: mutedColor),
                SizedBox(height: isDesktop ? 40 : 28),
                // Le formulaire — inchangé, importé tel quel.
                const LoginForm(),
                SizedBox(height: isDesktop ? 40 : 28),
                // Bas de page : mention légale style pied de registre.
                _buildSheetFooter(mutedColor: mutedColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Le cartouche typographique en tête de page : wordmark + numéro d'article.
  Widget _buildCartouche({
    required BuildContext context,
    required Color inkColor,
    required Color mutedColor,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Baillan.',
                style: theme.textTheme.displayMedium?.copyWith(
                  color: inkColor,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tenir registre.',
                style: TextStyle(
                  fontFamily: 'Cochin',
                  fontFamilyFallback: _serifFallback,
                  fontStyle: FontStyle.italic,
                  fontSize: 16,
                  color: mutedColor,
                ),
              ),
            ],
          ),
        ),
        // Numéro d'article — la contrepartie éditoriale du wordmark.
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'art. 1',
                style: TextStyle(
                  fontFamily: 'Cochin',
                  fontFamilyFallback: _serifFallback,
                  fontStyle: FontStyle.italic,
                  fontSize: 15,
                  letterSpacing: 0.4,
                  color: mutedColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Session',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w500,
                  color: mutedColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// L'aphorisme éditorial au-dessus du formulaire.
  Widget _buildAphorism({required Color mutedColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'En cas de doute, sortez le registre.',
          style: TextStyle(
            fontFamily: 'Cochin',
            fontFamilyFallback: _serifFallback,
            fontStyle: FontStyle.italic,
            fontSize: 22,
            height: 1.35,
            letterSpacing: -0.2,
            color: mutedColor,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Consignez votre entrée pour reprendre le fil des quittances, '
          'des baux et des échéances.',
          style: TextStyle(fontSize: 13.5, height: 1.55, color: mutedColor),
        ),
      ],
    );
  }

  /// Pied de la feuille — mention légale en tout petit, style pied de registre.
  Widget _buildSheetFooter({required Color mutedColor}) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 0.5,
            color: mutedColor.withValues(alpha: 0.25),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'fin. art. 1',
            style: TextStyle(
              fontFamily: 'Cochin',
              fontFamilyFallback: _serifFallback,
              fontStyle: FontStyle.italic,
              fontSize: 12,
              letterSpacing: 1.2,
              color: mutedColor,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 0.5,
            color: mutedColor.withValues(alpha: 0.25),
          ),
        ),
      ],
    );
  }

  /// Pagination de repli affichée sous la feuille sur mobile (la marge
  /// extérieure gauche desktop étant masquée).
  Widget _buildFooterPagination({required Color mutedColor}) {
    return Center(
      child: Text(
        'p. 1  —  Session',
        style: TextStyle(
          fontFamily: 'Cochin',
          fontFamilyFallback: _serifFallback,
          fontStyle: FontStyle.italic,
          fontSize: 12,
          letterSpacing: 1.2,
          color: mutedColor,
        ),
      ),
    );
  }

  /// Paraphe SVG — un geste calligraphique inspiré d'une signature notariale.
  /// Trait unique, spontané, olive. Encre légère : opacité déjà baissée par
  /// la couleur de trait pour rester une marque de marge, pas un logo.
  String _paraphSvg(Color oliveTone) {
    final r = oliveTone.r.round();
    final g = oliveTone.g.round();
    final b = oliveTone.b.round();
    final hex =
        '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
    return '''
<svg viewBox="0 0 120 90" xmlns="http://www.w3.org/2000/svg">
  <g fill="none" stroke="$hex" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" opacity="0.85">
    <!-- Boucle principale : un paraphe qui monte, tourne, redescend -->
    <path d="M 8 62 C 22 40, 42 22, 60 26 C 76 30, 78 46, 66 52 C 54 58, 40 50, 44 38 C 48 26, 66 22, 82 30 C 96 38, 104 54, 96 66 C 90 74, 78 74, 70 68" />
    <!-- Trait de plume final, comme la queue d'un paraphe -->
    <path d="M 70 68 L 112 76" stroke-width="1.2" />
    <!-- Point d'encre initial -->
    <circle cx="8" cy="62" r="1.8" fill="$hex" stroke="none" />
  </g>
</svg>
''';
  }
}

/// Stack sérif partagé — Cochin/Palatino avec fallback lisible.
const List<String> _serifFallback = [
  'Palatino Linotype',
  'Book Antiqua',
  'Palatino',
  'Georgia',
  'serif',
];

/// Peint un watermark répété "Registre" en filigrane très pâle sur la feuille.
/// C'est le détail "notarial" — comme le filigrane d'un papier officiel qu'on
/// ne voit qu'en inclinant la page.
class _WatermarkPainter extends CustomPainter {
  const _WatermarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: color,
      fontFamily: 'Cochin',
      fontFamilyFallback: _serifFallback,
      fontStyle: FontStyle.italic,
      fontSize: 88,
      fontWeight: FontWeight.w400,
      letterSpacing: 8,
    );
    final tp = TextPainter(
      text: TextSpan(text: 'Registre', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    // Centre le watermark, rotation légère pour un feel "cachet posé de biais".
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.35);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WatermarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
