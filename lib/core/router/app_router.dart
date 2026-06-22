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
import '../../features/tenants/presentation/tenant_form_page.dart';
import '../../features/tenants/presentation/tenants_list_page.dart';
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
      // currentSession est mis à jour synchroniquement par le SDK Supabase
      // AVANT l'émission du stream. Le StreamProvider, lui, propage la
      // nouvelle valeur en microtask suivante — race avec GoRouterRefreshStream
      // qui peut déclencher le redirect avant cette propagation. On lit donc
      // directement la session du repo pour éviter ce race au signup.
      final isAuthed = ref.read(authRepositoryProvider).currentSession != null;
      final isRecovery = ref.read(isInPasswordRecoveryProvider);
      final location = state.matchedLocation;

      // Cas passwordRecovery : Supabase émet une session temporaire lors du
      // clic sur le lien de reset password. Sans cette garde, isAuthed serait
      // true et l'utilisateur serait redirigé vers / sans avoir changé son
      // mot de passe. On force /reset-password jusqu'à ce que l'event change
      // (userUpdated après updatePassword, ou signedOut).
      if (isRecovery && location != '/reset-password') {
        return '/reset-password';
      }

      // Routes publiques accessibles sans session.
      const publicRoutes = {
        '/login',
        '/signup',
        '/forgot-password',
        '/reset-password',
        '/privacy',
      };
      if (publicRoutes.contains(location)) {
        // Redirige vers / si l'utilisateur est déjà connecté et tente d'aller
        // sur /login ou /signup (inutile de les faire remplir le formulaire).
        // En mode recovery, isAuthed est true mais on a déjà géré ce cas
        // au-dessus, donc ici isRecovery est toujours false.
        if (isAuthed && (location == '/login' || location == '/signup')) {
          return '/';
        }
        return null;
      }

      if (!isAuthed) return '/login';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const DashboardPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupPage()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordPage(),
      ),
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

      // -----------------------------------------------------------------------
      // Routes locataires (FEAT-004)
      // Protégées par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/tenants',
        builder: (context, state) => const TenantsListPage(),
      ),
      GoRoute(
        path: '/tenants/new',
        builder: (context, state) => const TenantFormPage(),
      ),
      GoRoute(
        path: '/tenants/:id',
        builder: (context, state) =>
            TenantDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/tenants/:id/edit',
        builder: (context, state) =>
            TenantEditPage(id: state.pathParameters['id']!),
      ),

      // -----------------------------------------------------------------------
      // Routes baux (FEAT-005)
      // Protégées par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/leases',
        builder: (context, state) => const LeasesListPage(),
      ),
      GoRoute(
        path: '/leases/new',
        builder: (context, state) => const LeaseFormPage(),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (context, state) =>
            LeaseDetailPage(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/leases/:id/edit',
        builder: (context, state) =>
            LeaseEditPage(id: state.pathParameters['id']!),
      ),

      // -----------------------------------------------------------------------
      // Routes paiements (FEAT-006)
      // Protégées par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/leases/:id/payments/new',
        builder: (context, state) =>
            PaymentFormPage(leaseId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/leases/:id/payments/:pid/edit',
        builder: (context, state) => PaymentEditPage(
          leaseId: state.pathParameters['id']!,
          paymentId: state.pathParameters['pid']!,
        ),
      ),

      // -----------------------------------------------------------------------
      // Routes quittances (FEAT-007)
      // Protégées par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/leases/:id/receipts',
        builder: (context, state) =>
            LeaseReceiptsPage(leaseId: state.pathParameters['id']!),
      ),

      // -----------------------------------------------------------------------
      // Route profil bailleur (FEAT-007 — sous-feature /profile)
      // Protégée par la garde auth globale : si !isAuthed → redirect /login.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfilePage(),
      ),
    ],
  );
});
