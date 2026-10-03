import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/ui/breakpoints.dart';
import '../../../core/ui/theme/app_spacing.dart';
import '../../profile/application/landlord_profile_provider.dart';
import '../../profile/presentation/widgets/section_header.dart';
import '../../pwa/application/install_prompt_controller.dart';
import '../../pwa/presentation/install_prompt_banner.dart';
import '../application/dashboard_provider.dart';
import '../domain/dashboard_snapshot.dart';
import 'widgets/action_items_panel.dart';
import 'widgets/collapsible_cashflow_section.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/kpi_grid.dart';
import 'widgets/onboarding_first_steps.dart';
import 'widgets/portfolio_yield_section.dart';
import 'widgets/recent_activity_section.dart';
import 'widgets/shortcuts_row.dart';

/// Onglet Accueil (branche 0 du shell adaptatif, FEAT-026) — cockpit du
/// bailleur Baillan.
///
/// Composition :
/// - [InstallPromptBanner] (conditionnel, en haut)
/// - [DashboardHeader] (bonjour + date)
/// - Contenu conditionnel :
///   - Onboarding si 0 biens/locataires/baux → [OnboardingFirstSteps]
///   - Sinon, 3 zones nommées (chacune introduite par un [SectionHeader]),
///     actions en tête :
///     1. « À traiter » → [ActionItemsPanel]
///     2. « Mon patrimoine » → [KpiGrid] + [PortfolioYieldSection]
///     3. « Analyse » → [CollapsibleCashflowSection] +
///        [RecentActivitySection]
/// - [ShortcutsRow] (mobile uniquement, en bas) — réduite au seul CTA
///   simulateur : sur desktop le simulateur est épinglé au rail de
///   navigation (FEAT-026), le raccourci y serait redondant ; Biens/
///   Locataires/Baux sont déjà des destinations du shell
///   (docs/UX_NAVIGATION.md §7).
///
/// Pull-to-refresh via [RefreshIndicator] + [dashboardProvider]. Le
/// graphique « Cash-flow mensuel » a son propre cycle de chargement
/// indépendant ([monthlyCashflowProvider]) : changer sa période ne relance
/// pas ce `refresh()`.
///
/// Le dashboard n'est plus le hub de navigation (§2 du doc) : pas de bouton
/// retour (`showBackButton: false`), et les icônes profil/déconnexion ont
/// disparu de l'AppBar — l'onglet Profil du shell les porte désormais
/// (déconnexion : `ProfileSessionSection`).
///
/// BLOCKER-2 : au 1er rendu après login, déclenche [InstallPromptController.evaluate]
/// avec le flag `isFirstLogin` basé sur SharedPreferences.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  static const _firstLoginKey = 'has_completed_first_login';

  @override
  void initState() {
    super.initState();
    // Évalue le prompt PWA au 1er rendu, après que le frame soit dessiné,
    // pour ne pas bloquer l'UI.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _evaluateInstallPrompt(),
    );
  }

  Future<void> _evaluateInstallPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenBefore = prefs.getBool(_firstLoginKey) ?? false;
    await prefs.setBool(_firstLoginKey, true);
    await ref
        .read(installPromptControllerProvider.notifier)
        .evaluate(isFirstLogin: !hasSeenBefore);
  }

  @override
  Widget build(BuildContext context) {
    final asyncSnapshot = ref.watch(dashboardProvider);
    final asyncProfile = ref.watch(landlordProfileProvider);

    final firstName = asyncProfile.valueOrNull?.fullName
        ?.split(' ')
        .firstOrNull;

    return Scaffold(
      appBar: AppAppBar(title: context.l10n.navHome, showBackButton: false),
      body: RefreshIndicator(
        onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
        child: Builder(
          builder: (context) {
            final spacing =
                Theme.of(context).extension<AppSpacing>() ?? const AppSpacing();
            // ShortcutsRow (CTA simulateur) : mobile uniquement. Sur desktop
            // le simulateur est épinglé au rail de navigation (FEAT-026),
            // le raccourci y serait redondant.
            final showShortcuts = context.isMobile;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                spacing.lg,
                spacing.lg,
                spacing.lg,
                spacing.xxl,
              ),
              children: [
                const InstallPromptBanner(),
                DashboardHeader(firstName: firstName),
                _DashboardContent(asyncSnapshot: asyncSnapshot),
                if (showShortcuts) ...[
                  SizedBox(height: spacing.xl),
                  const ShortcutsRow(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contenu principal (loading / error / data)
// ---------------------------------------------------------------------------

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.asyncSnapshot});

  final AsyncValue<DashboardSnapshot> asyncSnapshot;

  @override
  Widget build(BuildContext context) {
    return asyncSnapshot.when(
      loading: () => const _LoadingSkeleton(),
      error: (e, _) => _ErrorView(error: e),
      data: (snapshot) => _DataView(snapshot: snapshot),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.dashboardLoadErrorMessage,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('btn_retry'),
              onPressed: () => ref.read(dashboardProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataView extends StatelessWidget {
  const _DataView({required this.snapshot});
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final spacing =
        Theme.of(context).extension<AppSpacing>() ?? const AppSpacing();
    final onboarding = snapshot.onboarding;
    if (onboarding != null) {
      return OnboardingFirstSteps(progress: onboarding);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ZONE 1 — À traiter
        SectionHeader(title: context.l10n.dashboardZoneTodoTitle),
        SizedBox(height: spacing.md),
        ActionItemsPanel(
          loyers: snapshot.loyers,
          docsPendingCount: snapshot.docs.count,
        ),
        SizedBox(height: spacing.xl),
        // ZONE 2 — Mon patrimoine
        SectionHeader(title: context.l10n.dashboardZonePatrimonyTitle),
        SizedBox(height: spacing.md),
        const KpiGrid(),
        SizedBox(height: spacing.xl),
        const PortfolioYieldSection(),
        SizedBox(height: spacing.xl),
        // ZONE 3 — Analyse
        SectionHeader(title: context.l10n.dashboardZoneAnalysisTitle),
        SizedBox(height: spacing.md),
        const CollapsibleCashflowSection(),
        SizedBox(height: spacing.xl),
        RecentActivitySection(items: snapshot.activity),
      ],
    );
  }
}
