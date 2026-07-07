import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:logging/logging.dart';

import 'core/config/env.dart';
import 'core/i18n/locale_provider.dart';
import 'core/i18n/locale_resolution.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/auth/application/anon_expiry_renewer.dart';
import 'features/pwa/data/install_prompt_js_bridge_interface.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // URLs path-based sur le web (« /delete-account », pas « /#/delete-account »)
  // — FEAT-045 : l'URL de suppression de compte déclarée sur la fiche Google
  // Play doit résoudre telle quelle ; rend au passage les liens email Firebase
  // ($origin/login, $origin/reset-password?oobCode=…) routables en accès
  // direct. No-op sur iOS/Android. Le serving SPA est déjà en place
  // (firebase.json : rewrites ** → /index.html).
  usePathUrlStrategy();

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
    // Thème choisi par l'utilisateur (Profil → Apparence), persisté en
    // localStorage. Défaut : suit le système.
    final themeMode = ref.watch(themeModeProvider);
    // Langue choisie par l'utilisateur (Profil → Langue), persistée en
    // localStorage (FEAT-043). `null` = suit le système (résolution via
    // localeResolutionCallback ci-dessous) ; non-null court-circuite la
    // résolution système (override manuel).
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'Baillan.',
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      localeResolutionCallback: resolveLocale,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
