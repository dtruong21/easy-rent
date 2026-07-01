import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/anon_expiry_renewer.dart';
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

class BaillanApp extends ConsumerStatefulWidget {
  const BaillanApp({super.key});

  @override
  ConsumerState<BaillanApp> createState() => _BaillanAppState();
}

class _BaillanAppState extends ConsumerState<BaillanApp> {
  @override
  void initState() {
    super.initState();
    // BAILLAN-M1 : renouvelle anonExpiresAt au boot si la session est
    // anonyme (throttlé côté renewer — voir anon_expiry_renewer.dart). Ne
    // bloque jamais le premier rendu (fire-and-forget).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(anonExpiryRenewerProvider.notifier).renewIfNeeded());
    });
  }

  @override
  Widget build(BuildContext context) {
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
