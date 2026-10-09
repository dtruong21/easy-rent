/// Tests widget de [FeedbackPage] (FEAT-060).
///
/// Couvre : bouton désactivé sans note, envoi (note + commentaire →
/// repo + remerciement + retour au profil), échec d'envoi (message inline,
/// formulaire conservé).
library;

import 'dart:async';

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/support/data/support_repository.dart';
import 'package:easyrent/features/support/presentation/feedback_page.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _FakeRepo implements SupportRepository {
  final List<Map<String, Object>> feedbacks = [];
  Object? error;

  @override
  Future<void> submit({
    required String subject,
    required String message,
    required String appVersion,
    required String appEnv,
  }) async {}

  @override
  Future<void> submitFeedback({
    required int rating,
    required String comment,
    required String appVersion,
    required String appEnv,
    required String platform,
  }) async {
    if (error != null) throw error!;
    feedbacks.add({'rating': rating, 'comment': comment});
  }
}

/// Monte la page sous un [GoRouter] minimal : `/profile` (placeholder) puis
/// `/profile/feedback` poussé, pour que le `pop` du succès fonctionne.
Future<void> _pump(WidgetTester tester, _FakeRepo repo) async {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (context, state) => const Scaffold(body: Text('page profil')),
        routes: [
          GoRoute(
            path: 'feedback',
            builder: (context, state) => const FeedbackPage(),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [supportRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: supportedLocales,
        locale: const Locale('fr'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(router.push('/profile/feedback'));
  await tester.pumpAndSettle();
}

void main() {
  late _FakeRepo repo;

  setUp(() {
    repo = _FakeRepo();
    PackageInfo.setMockInitialValues(
      appName: 'Baillan',
      packageName: 'app.baillan',
      version: '1.0.0',
      buildNumber: '42',
      buildSignature: '',
      installerStore: null,
    );
  });

  testWidgets('« Envoyer » désactivé tant qu\'aucune note', (tester) async {
    await _pump(tester, repo);

    expect(find.text('Votre avis'), findsOneWidget);
    final btn = tester.widget<FilledButton>(
      find.byKey(const Key('btn_feedback_submit')),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('4 étoiles + commentaire → avis envoyé et remerciement', (
    tester,
  ) async {
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('btn_feedback_star_4')));
    await tester.enterText(
      find.byKey(const Key('field_feedback_comment')),
      'Pratique',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn_feedback_submit')));
    await tester.pumpAndSettle();

    expect(repo.feedbacks.single['rating'], 4);
    expect(repo.feedbacks.single['comment'], 'Pratique');
    expect(find.byKey(const Key('snackbar_feedback_success')), findsOneWidget);
    // Retour au profil après l'envoi.
    expect(find.byType(FeedbackPage), findsNothing);
    expect(find.text('page profil'), findsOneWidget);
  });

  testWidgets('échec d\'envoi → message d\'erreur, formulaire conservé', (
    tester,
  ) async {
    repo.error = StateError('réseau');
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('btn_feedback_star_2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn_feedback_submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('Envoi impossible. Réessayez dans quelques instants.'),
      findsOneWidget,
    );
    expect(find.byType(FeedbackPage), findsOneWidget);
    final btn = tester.widget<FilledButton>(
      find.byKey(const Key('btn_feedback_submit')),
    );
    expect(btn.onPressed, isNotNull);
  });
}
