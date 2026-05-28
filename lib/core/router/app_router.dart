import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_session_provider.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/privacy/presentation/privacy_page.dart';
import '../../features/properties/presentation/properties_list_page.dart';
import '../../features/properties/presentation/property_detail_page.dart';
import '../../features/properties/presentation/property_form_page.dart';
import 'go_router_refresh_stream.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // GoRouterRefreshStream écoute le flux d'auth et déclenche une réévaluation
  // de la garde (redirect) à chaque changement de session (login, logout, refresh).
  final refreshStream = GoRouterRefreshStream(
    ref.watch(authRepositoryProvider).authStateChanges,
  );

  // Le ref.onDispose garantit que le ChangeNotifier est libéré quand le
  // provider est détruit (hot-reload, tests…).
  ref.onDispose(refreshStream.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshStream,
    redirect: (context, state) {
      // On lit la valeur synchrone du provider (pas de watch ici car on est
      // en dehors du build tree). Le GoRouterRefreshStream garantit que cette
      // fonction est rappelée dès que la session change.
      final isAuthed = ref.read(isAuthenticatedProvider);
      final goingToLogin = state.matchedLocation == '/login';
      final goingToPrivacy = state.matchedLocation == '/privacy';

      // La page /privacy est publique — jamais redirigée.
      if (goingToPrivacy) return null;

      if (!isAuthed && !goingToLogin) return '/login';
      if (isAuthed && goingToLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const DashboardPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const PrivacyPage(),
      ),

      // -----------------------------------------------------------------------
      // Routes biens immobiliers (FEAT-003)
      // Protégées par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/properties',
        builder: (context, state) => const PropertiesListPage(),
      ),
      GoRoute(
        path: '/properties/new',
        builder: (context, state) => const PropertyFormPage(),
      ),
      GoRoute(
        path: '/properties/:id',
        builder: (context, state) =>
            PropertyDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/properties/:id/edit',
        builder: (context, state) =>
            PropertyEditPage(id: state.pathParameters['id']!),
      ),
    ],
  );
});
