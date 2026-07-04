import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../branding/brand_mark.dart';
import '../breakpoints.dart';
import 'rail_expanded_provider.dart';

/// Shell de navigation adaptatif Baillan (FEAT-026).
///
/// Enveloppe un [StatefulNavigationShell] de GoRouter (5 branches : Accueil,
/// Biens, Locataires, Baux, Profil) et rend :
/// - `< 600 px` : [Scaffold] + [NavigationBar] en bas (idiome mobile / PWA
///   étroite).
/// - `>= 600 px` : `Row(NavigationRail, VerticalDivider, contenu)` (idiome
///   desktop / tablette / web large). Le rail est **repliable** via un bouton
///   menu (icône seule ↔ icône + libellé au large), état persisté
///   ([railExpandedProvider]).
///
/// Le simulateur d'investissement (hors shell, accessible aussi aux anonymes)
/// est épinglé en bas du rail comme action secondaire — c'est le seul
/// « ailleurs » utile, cf. `docs/UX_NAVIGATION.md` §3.4 / §7.
///
/// Voir `docs/UX_NAVIGATION.md` §8.2 pour le contrat complet. Le breakpoint
/// (600 px) est celui déjà utilisé ailleurs dans l'app ([Breakpoints.mobile]).
class AdaptiveNavigationScaffold extends StatelessWidget {
  const AdaptiveNavigationScaffold({super.key, required this.navigationShell});

  /// Shell injecté par `StatefulShellRoute.indexedStack` — porte l'index de
  /// branche actif et le callback `goBranch`.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < Breakpoints.mobile;
        return isNarrow
            ? _NarrowLayout(navigationShell: navigationShell)
            : _WideLayout(navigationShell: navigationShell);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Destinations (partagées entre NavigationBar et NavigationRail)
// ---------------------------------------------------------------------------

class _Destination {
  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _destinations = <_Destination>[
  _Destination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Accueil',
  ),
  _Destination(
    icon: Icons.home_work_outlined,
    selectedIcon: Icons.home_work,
    label: 'Biens',
  ),
  _Destination(
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
    label: 'Locataires',
  ),
  _Destination(
    icon: Icons.description_outlined,
    selectedIcon: Icons.description,
    label: 'Baux',
  ),
  _Destination(
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: 'Profil',
  ),
];

/// Bascule vers la branche [index]. Re-tap de l'onglet déjà actif → retour à
/// la racine de la branche (`initialLocation: true`), idiome Material
/// standard (« pop to root »).
void _onDestinationSelected(StatefulNavigationShell shell, int index) {
  shell.goBranch(index, initialLocation: index == shell.currentIndex);
}

// ---------------------------------------------------------------------------
// Layout étroit (< 600 px) — NavigationBar en bas
// ---------------------------------------------------------------------------

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        child: NavigationBar(
          key: const Key('adaptive_nav_bar'),
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) =>
              _onDestinationSelected(navigationShell, index),
          destinations: [
            for (final destination in _destinations)
              NavigationDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: destination.label,
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout large (>= 600 px) — NavigationRail repliable à gauche
// ---------------------------------------------------------------------------

class _WideLayout extends ConsumerWidget {
  const _WideLayout({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Déplié/replié piloté par l'utilisateur (bouton menu), persisté.
    // extended=true → icône + libellé au large ; extended=false → rail compact
    // (icône + libellé court). Flutter exige labelType=none quand extended.
    final expanded = ref.watch(railExpandedProvider);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              key: const Key('adaptive_nav_rail'),
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (index) =>
                  _onDestinationSelected(navigationShell, index),
              extended: expanded,
              labelType: expanded
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              // En-tête de marque : logo Baillan (+ wordmark si déplié) qui
              // porte aussi la bascule déplier/replier.
              leading: _RailBrand(expanded: expanded),
              // Simulateur épinglé en bas (action secondaire, hors shell).
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RailSimulatorAction(expanded: expanded),
                  ),
                ),
              ),
              destinations: [
                for (final destination in _destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: navigationShell),
          ],
        ),
      ),
    );
  }
}

/// En-tête de marque du rail — maximise la présence Baillan dans la
/// navigation, et porte la bascule déplier/replier :
/// - **Replié** : le logo seul (« que le logo »), cliquable pour déplier.
/// - **Déplié** : logo + wordmark « Baillan. » + bouton replier.
class _RailBrand extends ConsumerWidget {
  const _RailBrand({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final toggle = ref.read(railExpandedProvider.notifier).toggle;

    if (!expanded) {
      // Replié : logo seul, tap = déplier (tooltip pour la découvrabilité).
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Tooltip(
          message: 'Déplier le menu',
          child: InkWell(
            key: const Key('rail_menu_toggle'),
            onTap: toggle,
            borderRadius: BorderRadius.circular(10),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: BrandMark(key: Key('rail_brand_logo'), size: 32),
            ),
          ),
        ),
      );
    }

    // Déplié : logo + wordmark + bouton replier.
    // mainAxisSize.min + aucun enfant flex (Expanded/Spacer) : le `leading`
    // d'un NavigationRail étendu est mesuré sous contrainte de largeur NON
    // bornée — un flex y déclenche un RenderFlex unbounded.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrandMark(key: Key('rail_brand_logo'), size: 32),
          const SizedBox(width: 10),
          Text(
            'Baillan.',
            key: const Key('rail_brand_wordmark'),
            maxLines: 1,
            style: TextStyle(
              fontFamily: 'EB Garamond',
              fontFamilyFallback: const ['Georgia', 'serif'],
              fontWeight: FontWeight.w500,
              fontSize: 22,
              height: 1.0,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('rail_menu_toggle'),
            icon: const Icon(Icons.menu_open),
            tooltip: 'Replier le menu',
            onPressed: toggle,
          ),
        ],
      ),
    );
  }
}

/// Action « Simuler un investissement » épinglée en bas du rail. Le simulateur
/// vit hors du shell (accessible aussi aux anonymes) → `go()` (pas `goBranch`).
class _RailSimulatorAction extends StatelessWidget {
  const _RailSimulatorAction({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    void go() => context.go('/simulator');

    if (!expanded) {
      return IconButton(
        key: const Key('rail_simulator_action'),
        icon: const Icon(Icons.calculate_outlined),
        tooltip: 'Simuler un investissement',
        color: color,
        onPressed: go,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        key: const Key('rail_simulator_action'),
        onTap: go,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calculate_outlined, size: 20, color: color),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Simuler un investissement',
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
