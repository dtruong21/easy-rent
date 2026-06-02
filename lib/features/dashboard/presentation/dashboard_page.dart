import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/application/auth_controller.dart';
import '../../profile/application/landlord_profile_provider.dart';
import '../../pwa/application/install_prompt_controller.dart';
import '../../pwa/presentation/install_prompt_banner.dart';
import '../application/dashboard_provider.dart';
import '../domain/dashboard_snapshot.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/kpi_grid.dart';
import 'widgets/monthly_barchart.dart';
import 'widgets/onboarding_first_steps.dart';
import 'widgets/recent_activity_section.dart';
import 'widgets/shortcuts_row.dart';

/// Dashboard principal — cockpit du bailleur EasyRent.
///
/// Composition :
/// - [InstallPromptBanner] (conditionnel, en haut)
/// - [DashboardHeader] (bonjour + date)
/// - Contenu conditionnel :
///   - Onboarding si 0 biens/locataires/baux → [OnboardingFirstSteps]
///   - Sinon : [KpiGrid] + [MonthlyBarchart] + [RecentActivitySection]
/// - [ShortcutsRow] (toujours visible en bas)
///
/// Pull-to-refresh via [RefreshIndicator] + [dashboardProvider].
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
      appBar: AppBar(
        title: const Text('EasyRent'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Mon profil',
            onPressed: () => context.go('/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Déconnexion',
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const InstallPromptBanner(),
            DashboardHeader(firstName: firstName),
            _DashboardContent(asyncSnapshot: asyncSnapshot),
            const SizedBox(height: 24),
            const ShortcutsRow(),
          ],
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
              'Impossible de charger le tableau de bord.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('btn_retry'),
              onPressed: () => ref.read(dashboardProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
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
    if (snapshot.isOnboarding) {
      return const OnboardingFirstSteps();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KpiGrid(snapshot: snapshot),
        const SizedBox(height: 24),
        MonthlyBarchart(months: snapshot.monthly),
        const SizedBox(height: 24),
        RecentActivitySection(items: snapshot.activity),
      ],
    );
  }
}
