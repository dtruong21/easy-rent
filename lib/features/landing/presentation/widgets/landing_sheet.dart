import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Stack sérif partagé — Cochin/Palatino avec fallback lisible (miroir de
/// `login_page.dart`).
const List<String> serifFallback = [
  'Palatino Linotype',
  'Book Antiqua',
  'Palatino',
  'Georgia',
  'serif',
];

/// La feuille « Page de garde » du registre — couverture éditoriale de la
/// landing (BAILLAN-M1, redesign 2026-07-02).
///
/// Même vocabulaire que la login page (« La Page du Registre ») : feuillet
/// crème bordé d'un hairline, ombre douce, Cochin, filets olive. Ici la
/// composition est CENTRÉE (typographie de page de titre) : cartouche
/// date/intitulé, masthead, double filet animé, pitch, sommaire en articles,
/// deux CTAs de poids égal (product lock #2 — aucun biais visuel entre
/// « sans compte » et « créer un compte »), pied « Fait le … ».
class LandingSheet extends StatelessWidget {
  const LandingSheet({
    required this.isDesktop,
    required this.isAmbientDark,
    required this.ruleDraw,
    required this.isStartingAnonymous,
    required this.onContinueWithoutAccount,
    required this.onCreateAccount,
    required this.onLogin,
    super.key,
  });

  final bool isDesktop;
  final bool isAmbientDark;

  /// Progression du tracé des filets olive (0 → 1), pilotée par la page.
  final Animation<double> ruleDraw;

  final bool isStartingAnonymous;
  final VoidCallback onContinueWithoutAccount;
  final VoidCallback onCreateAccount;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    // Ombre : marquée sur bureau sombre (feuille à la lampe), subtile en
    // plein jour — mêmes valeurs que la feuille de la login page.
    final shadow = isAmbientDark
        ? const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 48,
              offset: Offset(0, 20),
              spreadRadius: -6,
            ),
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
              spreadRadius: -2,
            ),
          ]
        : const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 36,
              offset: Offset(0, 14),
              spreadRadius: -10,
            ),
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 8,
              offset: Offset(0, 2),
              spreadRadius: -2,
            ),
          ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cream,
        borderRadius: BorderRadius.circular(2),
        boxShadow: shadow,
        border: Border.all(
          color: AppTheme.ruleStrong.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 72 : 28,
          vertical: isDesktop ? 60 : 40,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCartouche(),
            SizedBox(height: isDesktop ? 56 : 40),
            _buildMasthead(),
            const SizedBox(height: 26),
            _buildDoubleRule(),
            SizedBox(height: isDesktop ? 40 : 30),
            _buildPitch(),
            SizedBox(height: isDesktop ? 40 : 30),
            _buildSommaire(),
            SizedBox(height: isDesktop ? 48 : 36),
            _buildCtas(),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                key: const Key('landing_cta_login'),
                onPressed: onLogin,
                child: const Text('J\'ai déjà un compte'),
              ),
            ),
            SizedBox(height: isDesktop ? 32 : 22),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  /// Cartouche d'en-tête : date à gauche, intitulé à droite.
  Widget _buildCartouche() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _formatFrenchDate(DateTime.now()),
          style: const TextStyle(
            fontFamily: 'Cochin',
            fontFamilyFallback: serifFallback,
            fontStyle: FontStyle.italic,
            fontSize: 15,
            letterSpacing: 0.4,
            color: AppTheme.inkMuted,
          ),
        ),
        const Text(
          'PAGE DE GARDE',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 2.5,
            fontWeight: FontWeight.w500,
            color: AppTheme.inkMuted,
          ),
        ),
      ],
    );
  }

  /// Masthead centré : wordmark + tagline — composition de page de titre.
  Widget _buildMasthead() {
    return Column(
      children: [
        Text(
          'Baillan.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cochin',
            fontFamilyFallback: serifFallback,
            fontSize: isDesktop ? 64 : 48,
            fontWeight: FontWeight.w500,
            color: AppTheme.ink,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Tenir registre.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cochin',
            fontFamilyFallback: serifFallback,
            fontStyle: FontStyle.italic,
            fontSize: 18,
            color: AppTheme.inkMuted,
          ),
        ),
      ],
    );
  }

  /// Double filet olive qui se déploie depuis le centre.
  Widget _buildDoubleRule() {
    return AnimatedBuilder(
      animation: ruleDraw,
      builder: (context, _) {
        return Column(
          children: [
            FractionallySizedBox(
              widthFactor: ruleDraw.value.clamp(0.0, 1.0),
              child: Container(
                height: 1,
                color: AppTheme.olive.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 4),
            FractionallySizedBox(
              widthFactor: (ruleDraw.value * 0.72).clamp(0.0, 1.0),
              child: Container(
                height: 0.5,
                color: AppTheme.olive.withValues(alpha: 0.25),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Le pitch produit — phrase inchangée (testée), en italique de couverture.
  Widget _buildPitch() {
    return const Text(
      'Simulez votre prochain investissement locatif, ou gérez le '
      'registre de vos biens.',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'Cochin',
        fontFamilyFallback: serifFallback,
        fontStyle: FontStyle.italic,
        fontSize: 21,
        height: 1.45,
        letterSpacing: -0.2,
        color: AppTheme.ink,
      ),
    );
  }

  /// Sommaire du registre — deux articles, numérotation romaine olive.
  Widget _buildSommaire() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            _SommaireEntry(
              numeral: 'I.',
              title: 'Simulateur d\'investissement',
              detail: 'rendement, cash-flow, coût du crédit',
            ),
            SizedBox(height: 14),
            _SommaireEntry(
              numeral: 'II.',
              title: 'Registre des biens',
              detail: 'baux, quittances, échéances',
            ),
          ],
        ),
      ),
    );
  }

  /// Les 2 CTAs — POIDS VISUEL ÉQUIVALENT (product lock #2) : mêmes
  /// FilledButton olive, même taille. Empilés quand la feuille est étroite.
  Widget _buildCtas() {
    final anonymous = FilledButton(
      key: const Key('landing_cta_anonymous'),
      onPressed: isStartingAnonymous ? null : onContinueWithoutAccount,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
      ),
      child: isStartingAnonymous
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Continuer sans compte'),
    );
    final signup = FilledButton(
      key: const Key('landing_cta_signup'),
      onPressed: onCreateAccount,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
      ),
      child: const Text('Créer un compte'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [anonymous, const SizedBox(height: 12), signup],
          );
        }
        return Row(
          children: [
            Expanded(child: anonymous),
            const SizedBox(width: 16),
            Expanded(child: signup),
          ],
        );
      },
    );
  }

  /// Pied de feuille « Fait le … · Baillan. » entre deux hairlines.
  Widget _buildFooter() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 0.5,
            color: AppTheme.inkMuted.withValues(alpha: 0.25),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'Fait le ${_formatFrenchDate(DateTime.now())} · Baillan.',
            style: const TextStyle(
              fontFamily: 'Cochin',
              fontFamilyFallback: serifFallback,
              fontStyle: FontStyle.italic,
              fontSize: 12,
              letterSpacing: 1.2,
              color: AppTheme.inkMuted,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 0.5,
            color: AppTheme.inkMuted.withValues(alpha: 0.25),
          ),
        ),
      ],
    );
  }
}

/// Une entrée du sommaire : numéral romain olive + intitulé + détail.
class _SommaireEntry extends StatelessWidget {
  const _SommaireEntry({
    required this.numeral,
    required this.title,
    required this.detail,
  });

  final String numeral;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 34,
          child: Text(
            numeral,
            style: const TextStyle(
              fontFamily: 'Cochin',
              fontFamilyFallback: serifFallback,
              fontStyle: FontStyle.italic,
              fontSize: 16,
              color: AppTheme.olive,
            ),
          ),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.ink,
                  ),
                ),
                TextSpan(
                  text: ' — $detail',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppTheme.inkMuted,
                  ),
                ),
              ],
            ),
            style: const TextStyle(height: 1.5),
          ),
        ),
      ],
    );
  }
}

/// Formate une date française style contrat : « 1er juillet 2026 ».
/// Ordinal seulement sur le 1er du mois (convention FR) — miroir de
/// `login_page.dart`.
String _formatFrenchDate(DateTime d) {
  const months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  final day = d.day == 1 ? '1er' : d.day.toString();
  return '$day ${months[d.month - 1]} ${d.year}';
}
