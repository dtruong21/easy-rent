import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/pwa/data/install_prompt_js_bridge_interface.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configuration du système de logs.
  // En prod (Env.isProd) : niveau WARNING minimum — les logs INFO/FINE ne
  // partent pas en console et ne risquent pas d'exposer des données perso.
  // Hors prod : niveau ALL pour le débogage.
  // Choix : Env.isProd (basé sur SUPABASE_SCHEMA dart-define) est la variable
  // d'env déjà disponible à compile-time ; plus explicite que kReleaseMode qui
  // ne distingue pas dev-release de prod-release.
  Logger.root.level = Env.isProd ? Level.WARNING : Level.ALL;
  if (!Env.isProd) {
    Logger.root.onRecord.listen((record) {
      // ignore: avoid_print — seul point d'entrée autorisé pour les logs en dev.
      // En prod, brancher sur un service externe (Sentry, Datadog…).
      debugPrint(
        '[${record.level.name}] ${record.loggerName}: ${record.message}'
        '${record.error != null ? '\nError: ${record.error}' : ''}'
        '${record.stackTrace != null ? '\n${record.stackTrace}' : ''}',
      );
    });
  } else {
    // En prod : seuls WARNING et au-dessus sont émis ; on attache un listener
    // minimal pour ne pas perdre les erreurs critiques dans la console.
    Logger.root.onRecord.listen((record) {
      // ignore: avoid_print
      debugPrint(
        '[${record.level.name}] ${record.loggerName}: ${record.message}'
        '${record.error != null ? '\nError: ${record.error}' : ''}',
      );
    });
  }

  // Garde-fou : si Env non configuré, afficher un écran d'erreur plutôt que
  // crasher lors de l'appel à Supabase.initialize (URL vide = exception).
  if (!Env.isConfigured) {
    runApp(const _EnvErrorApp());
    return;
  }

  // Initialise Firebase (FEAT-019). Tourne en parallèle de Supabase pendant
  // toute la phase de migration — le data layer continue d'utiliser Supabase
  // jusqu'à ce que chaque feature soit migrée vers Firestore.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    // PKCE est recommandé pour Flutter Web (meilleure sécurité que implicit).
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // BLOCKER-1 : capture l'événement beforeinstallprompt le plus tôt possible,
  // avant runApp, pour ne pas le rater (l'event est émis par le navigateur
  // très tôt au chargement de la page).
  InstallPromptJsBridge.captureDeferred();

  runApp(const ProviderScope(child: EasyRentApp()));
}

/// Application principale.
class EasyRentApp extends ConsumerWidget {
  const EasyRentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'EasyRent',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Écran d'erreur affiché si les variables d'environnement ne sont pas
/// configurées (Supabase URL / Anon Key manquantes).
class _EnvErrorApp extends StatelessWidget {
  const _EnvErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyRent',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: Colors.orange,
                ),
                const SizedBox(height: 24),
                Text(
                  'Configuration manquante',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  "L'application n'est pas correctement configurée.\n"
                  'Les variables SUPABASE_URL et SUPABASE_ANON_KEY '
                  'sont requises.\n\n'
                  'Lancez l\'application avec :\n'
                  'flutter run --dart-define-from-file=dart-defines.dev.json',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
