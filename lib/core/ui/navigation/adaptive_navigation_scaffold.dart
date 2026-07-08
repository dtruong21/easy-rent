import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../i18n/l10n_extensions.dart';
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

/// Destinations localisées (FEAT-043) — construites à chaque `build` à
/// partir du [BuildContext] pour suivre la langue active.
List<_Destination> _destinations(BuildContext context) {
  final l10n = context.l10n;
  return [
    _Destination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: l10n.navHome,
    ),
    _Destination(
      icon: Icons.home_work_outlined,
      selectedIcon: Icons.home_work,
      label: l10n.navProperties,
    ),
    _Destination(
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      label: l10n.navTenants,
    ),
    _Destination(
      icon: Icons.description_outlined,
      selectedIcon: Icons.description,
      label: l10n.navLeases,
    ),
    _Destination(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: l10n.navProfile,
    ),
  ];
}

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
            for (final destination in _destinations(context))
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
                for (final destination in _destinations(context))
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
    final l10n = context.l10n;
    final toggle = ref.read(railExpandedProvider.notifier).toggle;

    if (!expanded) {
      // Replié : logo seul, tap = déplier (tooltip pour la découvrabilité).
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Tooltip(
          message: l10n.navRailExpandTooltip,
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
            tooltip: l10n.navRailCollapseTooltip,
            onPressed: toggle,
          ),
        ],
      ),
    );
  }
}

/// Action « Simuler un investissement » épinglée en bas du rail. Le simulateur
/// vit hors du shell mais reste une destination de premier niveau — on
/// l'empile PAR-DESSUS le shell (`push()`, pas `go()`) pour que le retour
/// natif dépile directement vers le dashboard, sans aller-retour parasite par
/// la garde de session (docs/UX_NAVIGATION.md §3.4).
class _RailSimulatorAction extends StatelessWidget {
  const _RailSimulatorAction({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final label = context.l10n.navRailSimulatorAction;
    void go() => context.push('/simulator');

    if (!expanded) {
      return IconButton(
        key: const Key('rail_simulator_action'),
        icon: const Icon(Icons.calculate_outlined),
        tooltip: label,
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
                  label,
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
