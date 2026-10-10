import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_session_provider.dart';
import '../../features/auth/domain/session_state.dart';
import '../../features/auth/presentation/delete_account_request_page.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/reset_password_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/etat_des_lieux/presentation/etat_des_lieux_form_page.dart';
import '../../features/etat_des_lieux/presentation/etat_des_lieux_list_page.dart';
import '../../features/expenses/presentation/expense_form_page.dart';
import '../../features/expenses/presentation/property_expenses_page.dart';
import '../../features/landing/presentation/landing_page.dart';
import '../../features/paid_plan/presentation/pro_cancel_page.dart';
import '../../features/paid_plan/presentation/pro_pricing_page.dart';
import '../../features/paid_plan/presentation/pro_success_page.dart';
import '../../features/privacy/presentation/legal_page.dart';
import '../../features/privacy/presentation/privacy_page.dart';
import '../../features/privacy/presentation/terms_page.dart';
import '../../features/properties/presentation/properties_list_page.dart';
import '../../features/properties/presentation/property_detail_page.dart';
import '../../features/properties/presentation/property_form_page.dart';
import '../../features/leases/domain/lease_filter.dart';
import '../../features/leases/presentation/lease_detail_page.dart';
import '../../features/leases/presentation/lease_form_page.dart';
import '../../features/leases/presentation/leases_list_page.dart';
import '../../features/payments/presentation/payment_form_page.dart';
import '../../features/profile/presentation/change_password_page.dart';
import '../../features/profile/presentation/delete_account_page.dart';
import '../../features/profile/presentation/profile_details_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/receipts/presentation/lease_receipts_page.dart';
import '../../features/support/presentation/faq_page.dart';
import '../../features/support/presentation/feedback_page.dart';
import '../../features/support/presentation/support_page.dart';
import '../../features/tenants/presentation/tenant_detail_page.dart';
import '../../features/simulator/presentation/scenario_comparison_page.dart';
import '../../features/simulator/presentation/simulator_page.dart';
import '../../features/tenants/presentation/tenant_form_page.dart';
import '../../features/tenants/presentation/tenants_list_page.dart';
import '../ui/navigation/adaptive_navigation_scaffold.dart';
import 'transitions.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // Réévalue la garde (redirect) à chaque CHANGEMENT d'état de session
  // (login, logout, link anonyme → compte).
  //
  // ⚠️ On écoute sessionStateProvider, PAS le stream Firebase brut. L'ancien
  // câblage (GoRouterRefreshStream sur authStateChanges) perdait une course
  // systématique : la notification du stream brut arrivait avant que
  // sessionStateProvider n'ait intégré l'événement, la garde lisait donc
  // l'état PÉRIMÉ et n'était jamais réévaluée ensuite — un sign-in à chaud
  // laissait l'utilisateur planté sur /login ou /signup (« la popup Google
  // se ferme et rien ne se passe », 2026-07-02). Riverpod notifie ref.listen
  // APRÈS la mise à jour du provider : la garde lit toujours l'état frais.
  // Régression couverte par router_auth_refresh_test.dart.
  final refreshNotifier = _RouterRefreshNotifier();
  ref.onDispose(refreshNotifier.dispose);
  ref.listen<SessionState>(sessionStateProvider, (previous, next) {
    if (previous != next) refreshNotifier.refresh();
  });

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      // sessionStateProvider expose l'état 3-branches dérivé du user
      // FirebaseAuth (data du StreamProvider, fallback sur currentUser en
      // cache sur loading/error). Override possible en test via
      // override(sessionStateProvider, ...).
      final sessionState = ref.read(sessionStateProvider);
      final location = state.matchedLocation;

      // Routes accessibles à TOUS, quel que soit sessionState (landing +
      // auth forms + légal). `/` a un traitement spécial ci-dessous (les
      // sessions actives y sont redirigées ailleurs).
      const publicRoutes = {
        '/login',
        '/signup',
        '/forgot-password',
        '/reset-password',
        '/privacy',
        '/terms',
        // Mentions légales (LCEN) — publiques, liées depuis le hub Profil.
        '/legal',
        // FEAT-045 : URL de demande de suppression de compte, déclarée sur
        // la fiche Google Play — doit rester accessible sans login (et aux
        // anonymes, qui y suppriment leur essai).
        '/delete-account',
        // FAQ produit — consultable avant inscription et par les anonymes.
        '/faq',
      };

      // Routes accessibles aux anonymes ET aux comptes complets (le
      // simulateur est le carrefour d'onboarding — BAILLAN-M1). `state.
      // matchedLocation` résout les segments dynamiques (`/simulator/:id`
      // devient `/simulator/abc123`), d'où le `startsWith` pour couvrir les
      // deux routes `/simulator` et `/simulator/:id` en une seule règle.
      final isAnonAccessible =
          location == '/simulator' || location.startsWith('/simulator/');

      switch (sessionState) {
        case SessionState.unauthenticated:
          if (location == '/') return null; // landing publique
          if (publicRoutes.contains(location)) return null;
          return '/login';

        case SessionState.anonymous:
          // Un anonyme qui atterrit sur la landing repart directement vers
          // le simulateur (déjà "dans" son essai sans compte).
          if (location == '/') return '/simulator';
          if (publicRoutes.contains(location)) return null;
          if (isAnonAccessible) return null;
          // Toute route métier complète (dashboard, properties, etc.) est
          // hors de portée d'un anonyme — retour à la landing.
          return '/';

        case SessionState.fullyAuthenticated:
          if (location == '/') return '/dashboard';
          // /login et /signup redirigent un compte déjà connecté.
          if (location == '/login' || location == '/signup') {
            return '/dashboard';
          }
          // /reset-password reste accessible même connecté (cas où
          // l'utilisateur clique son lien email après avoir réauthentifié
          // manuellement) ; /forgot-password et /privacy aussi.
          return null;
      }
    },
    routes: [
      // -----------------------------------------------------------------------
      // Landing publique (BAILLAN-M1) — carrefour d'onboarding.
      // Hors shell (FEAT-026) : plein écran, pas d'onglets.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const LandingPage(),
          transition: AppTransition.fade,
        ),
      ),

      // -----------------------------------------------------------------------
      // Routes auth (transition fade — pas de slide)
      // Hors shell (FEAT-026) : plein écran, pas d'onglets.
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
      GoRoute(
        path: '/terms',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const TermsPage(),
          transition: AppTransition.fade,
        ),
      ),
      GoRoute(
        path: '/legal',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const LegalPage(),
          transition: AppTransition.fade,
        ),
      ),
      GoRoute(
        path: '/delete-account',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const DeleteAccountRequestPage(),
          transition: AppTransition.fade,
        ),
      ),
      GoRoute(
        path: '/faq',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const FaqPage(),
          transition: AppTransition.fade,
        ),
      ),

      // -----------------------------------------------------------------------
      // Baillan Pro — checkout flow (FEAT-044)
      // Hors shell : fullyAuth requis (le guard global redirige les autres).
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/pro',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const ProPricingPage(),
          transition: AppTransition.standard,
        ),
        routes: [
          GoRoute(
            path: 'success',
            pageBuilder: (context, state) => appPage(
              key: state.pageKey,
              child: const ProSuccessPage(),
              transition: AppTransition.fade,
            ),
          ),
          GoRoute(
            path: 'cancel',
            pageBuilder: (context, state) => appPage(
              key: state.pageKey,
              child: const ProCancelPage(),
              transition: AppTransition.fade,
            ),
          ),
        ],
      ),

      // -----------------------------------------------------------------------
      // Simulateur d'investissement (FEAT-018)
      // Hors shell (FEAT-026 — docs/UX_NAVIGATION.md §3.4) : accessible aux
      // anonymes (essai 14j) qui n'ont pas accès aux branches métier ; pour un
      // compte complet, point d'entrée depuis Accueil (CTA), push plein écran
      // par-dessus le shell.
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/simulator',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: const SimulatorPage(),
          transition: AppTransition.standard,
        ),
      ),
      // Comparaison de scénarios (FEAT-055, Pro).
      // ⚠ Doit être déclaré AVANT `/simulator/:id`, sinon go_router matcherait
      // `:id = "compare"` et l'écran de comparaison serait inatteignable.
      GoRoute(
        path: '/simulator/compare',
        pageBuilder: (context, state) {
          final raw = state.uri.queryParameters['ids'] ?? '';
          final ids = raw
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .take(3)
              .toList(growable: false);
          return appPage(
            key: state.pageKey,
            child: ScenarioComparisonPage(ids: ids),
            transition: AppTransition.standard,
          );
        },
      ),
      GoRoute(
        path: '/simulator/:id',
        pageBuilder: (context, state) => appPage(
          key: state.pageKey,
          child: SimulatorPage(scenarioId: state.pathParameters['id']),
          transition: AppTransition.standard,
        ),
      ),

      // -----------------------------------------------------------------------
      // Shell adaptatif (FEAT-026) — 5 branches à état préservé.
      // Protégé par la garde auth globale : si !isAuthed → redirect /login.
      // Un utilisateur anonyme n'atteint jamais une branche (le redirect le
      // sort avant, cf. la garde 3-états ci-dessus, INCHANGÉE).
      //
      // Sous-routes imbriquées (`routes:` sur chaque GoRoute) plutôt que
      // chemins absolus frères, pour que GoRouter empile dans la bonne
      // branche. Les segments relatifs (`new`, `:id`, `edit`) se résolvent en
      // absolu à l'URL — aucune URL publique ne change (docs/UX_NAVIGATION.md
      // §8.1).
      // -----------------------------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdaptiveNavigationScaffold(navigationShell: navigationShell),
        branches: [
          // --- Branche 0 : Accueil ---------------------------------------
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                pageBuilder: (context, state) => appPage(
                  key: state.pageKey,
                  child: const DashboardPage(),
                  transition: AppTransition.standard,
                ),
              ),
            ],
          ),

          // --- Branche 1 : Biens (FEAT-003) -------------------------------
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/properties',
                pageBuilder: (context, state) => appPage(
                  key: state.pageKey,
                  child: const PropertiesListPage(),
                  transition: AppTransition.standard,
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    pageBuilder: (context, state) => appPage(
                      key: state.pageKey,
                      child: const PropertyFormPage(),
                      transition: AppTransition.standard,
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (context, state) => appPage(
                      key: state.pageKey,
                      child: PropertyDetailPage(
                        id: state.pathParameters['id']!,
                      ),
                      transition: AppTransition.standard,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        pageBuilder: (context, state) => appPage(
                          key: state.pageKey,
                          child: PropertyEditPage(
                            id: state.pathParameters['id']!,
                          ),
                          transition: AppTransition.standard,
                        ),
                      ),
                      // --- Dépenses (FEAT-041a) -------------------------
                      GoRoute(
                        path: 'expenses',
                        pageBuilder: (context, state) => appPage(
                          key: state.pageKey,
                          child: PropertyExpensesPage(
                            propertyId: state.pathParameters['id']!,
                          ),
                          transition: AppTransition.standard,
                        ),
                        routes: [
                          GoRoute(
                            path: 'new',
                            pageBuilder: (context, state) => appPage(
                              key: state.pageKey,
                              // extra: {'leaseId': ...} — pré-remplissage
                              // depuis la fiche bail (point d'entrée
                              // secondaire, cf. plan § h).
                              child: ExpenseFormPage(
                                propertyId: state.pathParameters['id']!,
                                preselectedLeaseId:
                                    (state.extra as Map?)?['leaseId']
                                        as String?,
                              ),
                              transition: AppTransition.standard,
                            ),
                          ),
                          GoRoute(
                            path: ':eid/edit',
                            pageBuilder: (context, state) => appPage(
                              key: state.pageKey,
                              child: ExpenseEditPage(
                                propertyId: state.pathParameters['id']!,
                                expenseId: state.pathParameters['eid']!,
                              ),
                              transition: AppTransition.standard,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // --- Branche 2 : Locataires (FEAT-004) --------------------------
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tenants',
                pageBuilder: (context, state) => appPage(
                  key: state.pageKey,
                  child: const TenantsListPage(),
                  transition: AppTransition.standard,
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    pageBuilder: (context, state) => appPage(
                      key: state.pageKey,
                      // ?picker=1 : ouvert en push depuis un autre formulaire
                      // (ex. bail) → au succès, pop(tenantId) au lieu de
                      // go('/tenants').
                      child: TenantFormPage(
                        popOnSuccess:
                            state.uri.queryParameters['picker'] == '1',
                      ),
                      transition: AppTransition.standard,
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (context, state) => appPage(
                      key: state.pageKey,
                      child: TenantDetailPage(id: state.pathParameters['id']!),
                      transition: AppTransition.standard,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        pageBuilder: (context, state) => appPage(
                          key: state.pageKey,
                          child: TenantEditPage(
                            id: state.pathParameters['id']!,
                          ),
                          transition: AppTransition.standard,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // --- Branche 3 : Baux (FEAT-005) + paiements/quittances imbriqués
          // (FEAT-006, FEAT-007) -------------------------------------------
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/leases',
                pageBuilder: (context, state) => appPage(
                  key: state.pageKey,
                  // ?filter=active|renewable|... : drill-down depuis un KPI
                  // dashboard.
                  child: LeasesListPage(
                    initialFilter: LeaseFilter.fromQueryParam(
                      state.uri.queryParameters['filter'],
                    ),
                  ),
                  transition: AppTransition.standard,
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    pageBuilder: (context, state) => appPage(
                      key: state.pageKey,
                      // Présélection depuis une fiche / carte : bien ou
                      // locataire en query (`?propertyId=` / `?tenantId=`),
                      // ou bien dans `extra` (carte de rentabilité). Ignorés
                      // jusqu'ici — recette iOS, #197.
                      child: LeaseFormPage(
                        initialPropertyId:
                            state.uri.queryParameters['propertyId'] ??
                            _extraString(state.extra, 'propertyId'),
                        initialTenantId: state.uri.queryParameters['tenantId'],
                      ),
                      transition: AppTransition.standard,
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (context, state) => appPage(
                      key: state.pageKey,
                      // ?action=regularize : raccourci FEAT-030 depuis la
                      // liste Baux (action visible uniquement pour les baux
                      // nus) — la fiche ouvre le dialog de régularisation dès
                      // que ses données sont chargées.
                      child: LeaseDetailPage(
                        id: state.pathParameters['id']!,
                        openRegularizationOnLoad:
                            state.uri.queryParameters['action'] == 'regularize',
                      ),
                      transition: AppTransition.standard,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        pageBuilder: (context, state) => appPage(
                          key: state.pageKey,
                          child: LeaseEditPage(id: state.pathParameters['id']!),
                          transition: AppTransition.standard,
                        ),
                      ),
                      GoRoute(
                        path: 'payments/new',
                        pageBuilder: (context, state) => appPage(
                          key: state.pageKey,
                          child: PaymentFormPage(
                            leaseId: state.pathParameters['id']!,
                          ),
                          transition: AppTransition.standard,
                        ),
                      ),
                      GoRoute(
                        path: 'payments/:pid/edit',
                        pageBuilder: (context, state) => appPage(
                          key: state.pageKey,
                          child: PaymentEditPage(
                            leaseId: state.pathParameters['id']!,
                            paymentId: state.pathParameters['pid']!,
                          ),
                          transition: AppTransition.standard,
                        ),
                      ),
                      GoRoute(
                        path: 'receipts',
                        pageBuilder: (context, state) => appPage(
                          key: state.pageKey,
                          child: LeaseReceiptsPage(
                            leaseId: state.pathParameters['id']!,
                          ),
                          transition: AppTransition.standard,
                        ),
                      ),
                      GoRoute(
                        path: 'etat-des-lieux',
                        pageBuilder: (context, state) => appPage(
                          key: state.pageKey,
                          child: EtatDesLieuxListPage(
                            leaseId: state.pathParameters['id']!,
                          ),
                          transition: AppTransition.standard,
                        ),
                        routes: [
                          GoRoute(
                            path: 'new',
                            pageBuilder: (context, state) => appPage(
                              key: state.pageKey,
                              child: EtatDesLieuxFormPage(
                                leaseId: state.pathParameters['id']!,
                              ),
                              transition: AppTransition.standard,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // --- Branche 4 : Profil (FEAT-007, FEAT-025b) -------------------
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) => appPage(
                  key: state.pageKey,
                  child: const ProfilePage(),
                  transition: AppTransition.standard,
                ),
                routes: [
                  GoRoute(
                    path: 'details',
                    pageBuilder: (context, state) => appPage(
                      key: state.pageKey,
                      child: const ProfileDetailsPage(),
                      transition: AppTransition.standard,
                    ),
                  ),
                  GoRoute(
                    path: 'password',
                    pageBuilder: (context, state) => appPage(
                      key: state.pageKey,
                      child: const ChangePasswordPage(),
                      transition: AppTransition.standard,
                    ),
                  ),
                  GoRoute(
                    path: 'support',
                    pageBuilder: (context, state) => appPage(
                      key: state.pageKey,
                      child: const SupportPage(),
                      transition: AppTransition.standard,
                    ),
                  ),
                  GoRoute(
                    path: 'feedback',
                    pageBuilder: (context, state) => appPage(
                      key: state.pageKey,
                      child: const FeedbackPage(),
                      transition: AppTransition.standard,
                    ),
                  ),
                  GoRoute(
                    path: 'delete-account',
                    pageBuilder: (context, state) => appPage(
                      key: state.pageKey,
                      child: const DeleteAccountPage(),
                      transition: AppTransition.standard,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// [ChangeNotifier] minimal branché sur [GoRouter.refreshListenable] —
/// notifié depuis le `ref.listen(sessionStateProvider…)` du
/// [appRouterProvider], donc toujours APRÈS la mise à jour de l'état de
/// session (contrairement à l'écoute du stream Firebase brut, cf. commentaire
/// du provider).
class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

/// Valeur texte [key] d'un `extra` de route de type `Map`, sinon `null`.
String? _extraString(Object? extra, String key) {
  if (extra is Map) {
    final value = extra[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}
