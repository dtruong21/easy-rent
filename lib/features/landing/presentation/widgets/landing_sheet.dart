import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/app_info/app_info_provider.dart';
import '../../../../core/config/env.dart';
import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/theme/app_theme.dart';

/// Fallback du sérif EB Garamond bundlé en asset (miroir de
/// `login_page.dart`) — ne sert qu'en cas d'asset manquant.
const List<String> serifFallback = ['Georgia', 'serif'];

/// La feuille « Page de garde » du registre — couverture éditoriale de la
/// landing (BAILLAN-M1, redesign 2026-07-02).
///
/// Même vocabulaire que la login page (« La Page du Registre ») : feuillet
/// crème bordé d'un hairline, ombre douce, EB Garamond, filets olive. Ici la
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
            _buildCartouche(context),
            SizedBox(height: isDesktop ? 56 : 40),
            _buildMasthead(context),
            const SizedBox(height: 26),
            _buildDoubleRule(),
            SizedBox(height: isDesktop ? 40 : 30),
            _buildPitch(context),
            SizedBox(height: isDesktop ? 40 : 30),
            _buildSommaire(context),
            SizedBox(height: isDesktop ? 48 : 36),
            _buildCtas(context),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                key: const Key('landing_cta_login'),
                onPressed: onLogin,
                child: Text(context.l10n.landingCtaLoginLink),
              ),
            ),
            SizedBox(height: isDesktop ? 32 : 22),
            _buildFooter(context),
            const SizedBox(height: 8),
            _buildSecondaryLinks(context),
            const _EnvVersionLine(),
          ],
        ),
      ),
    );
  }

  /// Liens secondaires sous le pied : FAQ + pages légales — mêmes teintes
  /// discrètes que le pied, jamais en concurrence avec les CTAs.
  Widget _buildSecondaryLinks(BuildContext context) {
    TextButton link(String label, String route, Key key) => TextButton(
      key: key,
      onPressed: () => context.push(route),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.inkMuted,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12, letterSpacing: 0.4),
      ),
      child: Text(label),
    );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        link('FAQ', '/faq', const Key('landing_link_faq')),
        _linkSeparator(),
        link(
          context.l10n.landingLinkPrivacy,
          '/privacy',
          const Key('landing_link_privacy'),
        ),
        _linkSeparator(),
        link(
          context.l10n.landingLinkTerms,
          '/terms',
          const Key('landing_link_terms'),
        ),
      ],
    );
  }

  Widget _linkSeparator() =>
      const Text('·', style: TextStyle(fontSize: 12, color: AppTheme.inkMuted));

  /// Cartouche d'en-tête : date à gauche, intitulé à droite.
  Widget _buildCartouche(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _formatFrenchDate(context, DateTime.now()),
          style: const TextStyle(
            fontFamily: 'EB Garamond',
            fontFamilyFallback: serifFallback,
            fontStyle: FontStyle.italic,
            fontSize: 15,
            letterSpacing: 0.4,
            color: AppTheme.inkMuted,
          ),
        ),
        Text(
          context.l10n.landingCartoucheLabel,
          style: const TextStyle(
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
  Widget _buildMasthead(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Text(
          l10n.appTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'EB Garamond',
            fontFamilyFallback: serifFallback,
            fontSize: isDesktop ? 64 : 48,
            fontWeight: FontWeight.w500,
            color: AppTheme.ink,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.landingTagline,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'EB Garamond',
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
  Widget _buildPitch(BuildContext context) {
    return Text(
      context.l10n.landingPitch,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'EB Garamond',
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
  Widget _buildSommaire(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SommaireEntry(
              numeral: 'I.',
              title: l10n.landingSommaireSimulatorTitle,
              detail: l10n.landingSommaireSimulatorDetail,
            ),
            const SizedBox(height: 14),
            _SommaireEntry(
              numeral: 'II.',
              title: l10n.landingSommaireRegisterTitle,
              detail: l10n.landingSommaireRegisterDetail,
            ),
          ],
        ),
      ),
    );
  }

  /// Les 2 CTAs — POIDS VISUEL ÉQUIVALENT (product lock #2) : mêmes
  /// FilledButton olive, même taille. Empilés quand la feuille est étroite.
  Widget _buildCtas(BuildContext context) {
    final l10n = context.l10n;
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
          : Text(l10n.landingCtaAnonymousButton),
    );
    final signup = FilledButton(
      key: const Key('landing_cta_signup'),
      onPressed: onCreateAccount,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
      ),
      child: Text(l10n.landingCtaSignupButton),
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
  Widget _buildFooter(BuildContext context) {
    final l10n = context.l10n;
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
            l10n.landingFooterSignature(
              _formatFrenchDate(context, DateTime.now()),
              l10n.appTitle,
            ),
            style: const TextStyle(
              fontFamily: 'EB Garamond',
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
///
/// `numeral` reste en dur (chiffre romain, identique dans toutes les
/// locales) — seuls `title`/`detail` sont déjà localisés par l'appelant.
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
              fontFamily: 'EB Garamond',
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

/// Formate une date style contrat dans la locale active de l'app, ex.
/// « 1er juillet 2026 » (FR, ordinal réservé au 1er du mois — convention
/// FR) ou « July 1, 2026 » (EN via `DateFormat.yMMMMd`).
///
/// FEAT-043 : délègue à `package:intl` (piloté par la locale résolue,
/// symboles initialisés via les délégués `AppLocalizations`) — même pattern
/// que `login_page.dart`/`dashboard_header.dart` (nom conservé pour la
/// continuité avec le fichier miroir, bien qu'il formate désormais aussi
/// l'anglais).
String _formatFrenchDate(BuildContext context, DateTime d) {
  final localeName = Localizations.localeOf(context).toString();
  if (localeName.startsWith('fr') && d.day == 1) {
    final month = DateFormat.MMMM(localeName).format(d);
    return '1er $month ${d.year}';
  }
  return DateFormat.yMMMMd(localeName).format(d);
}

/// Version de l'app + environnement, en pied de la page de garde.
///
/// But : **distinguer d'un coup d'œil la prod du staging** sans ouvrir le
/// Profil. Réutilise exactement les mêmes sources que « Profil → À propos »
/// ([appInfoProvider] + [Env.isProd]) — une seule vérité sur la version.
///
/// Rendu volontairement asymétrique :
/// - **hors prod** : pastille d'environnement bien visible (c'est tout
///   l'intérêt — on doit voir immédiatement qu'on n'est PAS en prod) ;
/// - **en prod** : version seule, discrète. Afficher « production » à des
///   utilisateurs réels serait du bruit : l'absence de pastille suffit à
///   signifier la prod.
///
/// Si la version n'est pas encore chargée (ou illisible), on n'affiche rien
/// plutôt qu'un placeholder — évite un saut de mise en page sur la 1re vue.
class _EnvVersionLine extends ConsumerWidget {
  const _EnvVersionLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final version = ref
        .watch(appInfoProvider)
        .maybeWhen(
          data: (info) =>
              l10n.profileAboutVersionValue(info.version, info.buildNumber),
          orElse: () => null,
        );

    if (version == null && Env.isProd) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          if (!Env.isProd)
            Container(
              key: const Key('landing_env_badge'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l10n.profileAboutEnvDevStaging.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          if (version != null)
            Text(
              version,
              key: const Key('landing_app_version'),
              style: const TextStyle(fontSize: 11, color: AppTheme.inkMuted),
            ),
        ],
      ),
    );
  }
}
