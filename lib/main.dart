import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/pwa/data/install_prompt_js_bridge_interface.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Système de logs : WARNING+ en prod (Env.isProd), ALL en dev.
  Logger.root.level = Env.isProd ? Level.WARNING : Level.ALL;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    debugPrint(
      '[${record.level.name}] ${record.loggerName}: ${record.message}'
      '${record.error != null ? '\nError: ${record.error}' : ''}'
      '${!Env.isProd && record.stackTrace != null ? '\n${record.stackTrace}' : ''}',
    );
  });

  // Initialise Firebase (FEAT-019). Source unique de la couche data.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // BLOCKER-1 : capture l'événement beforeinstallprompt le plus tôt possible,
  // avant runApp, pour ne pas le rater (émis très tôt par le navigateur).
  InstallPromptJsBridge.captureDeferred();

  runApp(const ProviderScope(child: BaillanApp()));
}

class BaillanApp extends ConsumerWidget {
  const BaillanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Baillan.',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
