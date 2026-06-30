import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_session_provider.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/reset_password_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/privacy/presentation/privacy_page.dart';
import '../../features/properties/presentation/properties_list_page.dart';
import '../../features/properties/presentation/property_detail_page.dart';
import '../../features/properties/presentation/property_form_page.dart';
import '../../features/leases/presentation/lease_detail_page.dart';
import '../../features/leases/presentation/lease_form_page.dart';
import '../../features/leases/presentation/leases_list_page.dart';
import '../../features/payments/presentation/payment_form_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/receipts/presentation/lease_receipts_page.dart';
import '../../features/tenants/presentation/tenant_detail_page.dart';
import '../../features/simulator/presentation/simulator_page.dart';
import '../../features/tenants/presentation/tenant_form_page.dart';
import '../../features/tenants/presentation/tenants_list_page.dart';
import 'go_router_refresh_stream.dart';
import 'transitions.dart';

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
      // isAuthenticatedProvider expose le user FirebaseAuth (data du
      // StreamProvider, fallback sur currentUser en cache sur loading/error).
      // Override possible en test via override(isAuthenticatedProvider, ...).
      final isAuthed = ref.read(isAuthenticatedProvider);
      final location = state.matchedLocation;

      // Routes publiques accessibles sans session.
      const publicRoutes = {
        '/login',
        '/signup',
        '/forgot-password',
        '/reset-password',
        '/privacy',
      };
      if (publicRoutes.contains(location)) {
        // Si déjà connecté, /login et /signup redirigent vers /.
        // /reset-password reste accessible même connecté (cas où l'utilisateur
        // clique son lien email après avoir réauthentifié manuellement).
        if (isAuthed && (location == '/login' || location == '/signup')) {
          return '/';
        }
        return null;
      }

      if (!isAuthed) return '/login';
      return null;
    },
    routes: [
      // -----------------------------------------------------------------------
      // Dashboard
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const DashboardPage(),
          transition: AppTransition.standard,
        ),
      ),

      // -----------------------------------------------------------------------
      // Routes auth (transition fade — pas de slide)
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const LoginPage(),
          transition: AppTransition.fade,
        ),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const SignupPage(),
          transition: AppTransition.fade,
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const ForgotPasswordPage(),
          transition: AppTransition.fade,
        ),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const ResetPasswordPage(),
          transition: AppTransition.fade,
        ),
      ),
      GoRoute(
        path: '/privacy',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const PrivacyPage(),
          transition: AppTransition.fade,
        ),
      ),

      // -----------------------------------------------------------------------
      // Routes biens immobiliers (FEAT-003)
      // Protégées par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/properties',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const PropertiesListPage(),
          transition: AppTransition.standard,
        ),
      ),
      GoRoute(
        path: '/properties/new',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const PropertyFormPage(),
          transition: AppTransition.standard,
        ),
      ),
      GoRoute(
        path: '/properties/:id',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: PropertyDetailPage(id: state.pathParameters['id']!),
          transition: AppTransition.standard,
        ),
      ),
      GoRoute(
        path: '/properties/:id/edit',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: PropertyEditPage(id: state.pathParameters['id']!),
          transition: AppTransition.standard,
        ),
      ),

      // -----------------------------------------------------------------------
      // Routes locataires (FEAT-004)
      // Protégées par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/tenants',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const TenantsListPage(),
          transition: AppTransition.standard,
        ),
      ),
      GoRoute(
        path: '/tenants/new',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const TenantFormPage(),
          transition: AppTransition.standard,
        ),
      ),
      GoRoute(
        path: '/tenants/:id',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: TenantDetailPage(id: state.pathParameters['id']!),
          transition: AppTransition.standard,
        ),
      ),
      GoRoute(
        path: '/tenants/:id/edit',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: TenantEditPage(id: state.pathParameters['id']!),
          transition: AppTransition.standard,
        ),
      ),

      // -----------------------------------------------------------------------
      // Routes baux (FEAT-005)
      // Protégées par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/leases',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const LeasesListPage(),
          transition: AppTransition.standard,
        ),
      ),
      GoRoute(
        path: '/leases/new',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const LeaseFormPage(),
          transition: AppTransition.standard,
        ),
      ),
      GoRoute(
        path: '/leases/:id',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: LeaseDetailPage(id: state.pathParameters['id']!),
          transition: AppTransition.standard,
        ),
      ),
      GoRoute(
        path: '/leases/:id/edit',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: LeaseEditPage(id: state.pathParameters['id']!),
          transition: AppTransition.standard,
        ),
      ),

      // -----------------------------------------------------------------------
      // Routes paiements (FEAT-006)
      // Protégées par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/leases/:id/payments/new',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: PaymentFormPage(leaseId: state.pathParameters['id']!),
          transition: AppTransition.standard,
        ),
      ),
      GoRoute(
        path: '/leases/:id/payments/:pid/edit',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: PaymentEditPage(
            leaseId: state.pathParameters['id']!,
            paymentId: state.pathParameters['pid']!,
          ),
          transition: AppTransition.standard,
        ),
      ),

      // -----------------------------------------------------------------------
      // Routes quittances (FEAT-007)
      // Protégées par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/leases/:id/receipts',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: LeaseReceiptsPage(leaseId: state.pathParameters['id']!),
          transition: AppTransition.standard,
        ),
      ),

      // -----------------------------------------------------------------------
      // Route profil bailleur (FEAT-007 — sous-feature /profile)
      // Protégée par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/profile',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const ProfilePage(),
          transition: AppTransition.standard,
        ),
      ),

      // -----------------------------------------------------------------------
      // Simulateur d'investissement (FEAT-018)
      // Protégées par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/simulator',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const SimulatorPage(),
          transition: AppTransition.standard,
        ),
      ),
      GoRoute(
        path: '/simulator/:id',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: SimulatorPage(scenarioId: state.pathParameters['id']),
          transition: AppTransition.standard,
        ),
      ),
    ],
  );
});
