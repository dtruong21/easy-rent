import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../breakpoints.dart';

/// Shell de navigation adaptatif Baillan (FEAT-026).
///
/// Enveloppe un [StatefulNavigationShell] de GoRouter (5 branches : Accueil,
/// Biens, Locataires, Baux, Profil) et rend :
/// - `< 600 px` : [Scaffold] + [NavigationBar] en bas (idiome mobile / PWA
///   étroite).
/// - `>= 600 px` : `Row(NavigationRail, VerticalDivider, contenu)` (idiome
///   desktop / tablette / web large).
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
// Layout large (>= 600 px) — NavigationRail à gauche
// ---------------------------------------------------------------------------

class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    // Rail étendu (avec labels visibles) au-delà de la limite tablette pour
    // laisser de la place au contenu sur les largeurs intermédiaires.
    final isExtended = MediaQuery.sizeOf(context).width >= Breakpoints.tablet;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              key: const Key('adaptive_nav_rail'),
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (index) =>
                  _onDestinationSelected(navigationShell, index),
              extended: isExtended,
              labelType: isExtended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
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
