import 'package:easyrent/features/auth/application/auth_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/login_form_state.dart';
import 'package:easyrent/features/auth/presentation/login_page.dart';
import 'package:easyrent/features/auth/presentation/widgets/magic_link_sent_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Fake repo — aucun appel réseau.
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  bool sendCalled = false;
  String? lastEmail;
  Exception? sendError;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;

  @override
  Future<void> sendMagicLink(String email) async {
    sendCalled = true;
    lastEmail = email;
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> signOut() async {}
}

// ---------------------------------------------------------------------------
// Helper de montage — MaterialApp minimal avec GoRouter (pour context.go).
// ---------------------------------------------------------------------------

Widget _buildLoginPage({
  required _FakeAuthRepository repo,
  LoginFormState? initialState,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/privacy',
        builder: (context, state) =>
            const Scaffold(body: Text('Politique de confidentialité')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      if (initialState != null)
        authControllerProvider.overrideWith(
          (ref) =>
              AuthController(ref.read(authRepositoryProvider))
                ..state = initialState,
        ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LoginForm — critères d\'acceptation FEAT-001', () {
    // -----------------------------------------------------------------------
    // Case RGPD — non pré-cochée
    // -----------------------------------------------------------------------
    testWidgets('la case RGPD est non pré-cochée à l\'ouverture', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
    });

    // -----------------------------------------------------------------------
    // Texte RGPD + lien
    // Le texte RGPD est rendu via RichText/TextSpan, pas un simple Text widget.
    // On vérifie la présence du RichText contenant "politique de confidentialité".
    // -----------------------------------------------------------------------
    testWidgets('le texte RGPD contient "politique de confidentialité"', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      // RichText contenant le texte RGPD.
      final richTextFinder = find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('politique de confidentialité'),
      );
      expect(richTextFinder, findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Bouton désactivé par défaut
    // -----------------------------------------------------------------------
    testWidgets('bouton désactivé si email vide et RGPD non cochée', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    // -----------------------------------------------------------------------
    // Bouton désactivé email invalide + RGPD cochée
    // -----------------------------------------------------------------------
    testWidgets('bouton désactivé si email invalide même avec RGPD cochée', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'invalid-email');
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    // -----------------------------------------------------------------------
    // Bouton désactivé email valide + RGPD non cochée
    // -----------------------------------------------------------------------
    testWidgets('bouton désactivé si email valide mais RGPD non cochée', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'user@exemple.fr');
      await tester.pump();

      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    // -----------------------------------------------------------------------
    // Bouton activé — email valide + RGPD cochée
    // -----------------------------------------------------------------------
    testWidgets('bouton activé quand email valide ET RGPD cochée', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'user@exemple.fr');
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNotNull);
    });

    // -----------------------------------------------------------------------
    // Erreur inline "Adresse email invalide" — visible après submit email vide
    // -----------------------------------------------------------------------
    testWidgets(
      'erreur inline "Adresse email invalide" visible quand email invalide soumis via controller',
      (tester) async {
        final repo = _FakeAuthRepository();
        await tester.pumpWidget(
          _buildLoginPage(
            repo: repo,
            initialState: const LoginFormState.error(
              message: 'Adresse email invalide',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Adresse email invalide'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Message d'erreur Supabase affiché sous le champ
    // -----------------------------------------------------------------------
    testWidgets('message d\'erreur Supabase affiché sous le champ', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildLoginPage(
          repo: _FakeAuthRepository(),
          initialState: const LoginFormState.error(
            message:
                'Trop de demandes. Attendez quelques minutes avant de réessayer.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Trop de demandes'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Vue de confirmation après envoi
    // -----------------------------------------------------------------------
    testWidgets(
      'MagicLinkSentView affiche le message de confirmation et l\'email',
      (tester) async {
        await tester.pumpWidget(
          _buildLoginPage(
            repo: _FakeAuthRepository(),
            initialState: const LoginFormState.linkSent(
              email: 'user@exemple.fr',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Vérifiez votre boîte mail'), findsOneWidget);
        expect(find.text('user@exemple.fr'), findsOneWidget);
        expect(
          find.textContaining('Un lien de connexion vous a été envoyé'),
          findsOneWidget,
        );
      },
    );

    // -----------------------------------------------------------------------
    // Message PKCE (autre navigateur)
    // -----------------------------------------------------------------------
    testWidgets(
      'MagicLinkSentView affiche le message PKCE (autre navigateur)',
      (tester) async {
        await tester.pumpWidget(
          _buildLoginPage(
            repo: _FakeAuthRepository(),
            initialState: const LoginFormState.linkSent(
              email: 'user@exemple.fr',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('autre navigateur'), findsOneWidget);
        expect(find.textContaining('même navigateur'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Bouton "Renvoyer un lien" visible et fonctionnel
    // -----------------------------------------------------------------------
    testWidgets(
      'bouton "Renvoyer un lien" visible dans MagicLinkSentView et repasse à idle',
      (tester) async {
        await tester.pumpWidget(
          _buildLoginPage(
            repo: _FakeAuthRepository(),
            initialState: const LoginFormState.linkSent(
              email: 'user@exemple.fr',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Renvoyer un lien'), findsOneWidget);
        // Le bouton peut être en dehors de l'écran test — on le fait défiler.
        await tester.ensureVisible(find.text('Renvoyer un lien'));
        await tester.tap(find.text('Renvoyer un lien'));
        await tester.pumpAndSettle();

        // Après reset, le formulaire (TextField) doit s'afficher à nouveau.
        expect(find.byType(TextField), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // MagicLinkSentView — rendu direct (test unitaire du widget)
    // -----------------------------------------------------------------------
    testWidgets('MagicLinkSentView seul affiche l\'email passé en paramètre', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MagicLinkSentView(email: 'test@test.fr')),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('test@test.fr'), findsOneWidget);
      expect(find.text('Vérifiez votre boîte mail'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Indicateur de chargement pendant submitting
    // -----------------------------------------------------------------------
    testWidgets(
      'affiche un CircularProgressIndicator quand en état submitting',
      (tester) async {
        await tester.pumpWidget(
          _buildLoginPage(
            repo: _FakeAuthRepository(),
            initialState: const LoginFormState.submitting(),
          ),
        );
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );
  });
}
