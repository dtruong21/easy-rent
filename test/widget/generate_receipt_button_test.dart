/// Tests widget de [GenerateReceiptButton].
///
/// Couvre : submit → success (dialog preview), error (SnackBar),
/// profileIncomplete (dialog profil), état submitting (spinner).
library;

import 'dart:typed_data';
import 'dart:async';

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:easyrent/features/receipts/presentation/widgets/generate_receipt_button.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeReceiptsRepo implements ReceiptsRepository {
  final ReceiptGenerationResult? _result;
  final Exception? _exception;

  const _FakeReceiptsRepo({
    ReceiptGenerationResult? result,
    Exception? exception,
  }) : _result = result,
       _exception = exception;

  @override
  Future<List<Receipt>> listForLease(String leaseId) async => [];

  @override
  Future<Receipt> getById(String id) async => throw UnimplementedError();

  @override
  Future<ReceiptGenerationResult> generate({
    List<String>? paymentIds,
    String? leaseId,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    if (_exception != null) throw _exception;
    if (_result != null) return _result;
    throw StateError('no result configured');
  }

  @override
  Future<String> signedUrl(String pdfPath) async => throw UnimplementedError();

  @override
  Future<void> voidReceipt(String id, String reason) async {}

  @override
  Future<Receipt> markReceiptAsShared({
    required String receiptId,
    required String tenantEmail,
  }) async => throw UnimplementedError();

  @override
  Future<Uint8List> renderPdfBytes(String receiptId) async => Uint8List(0);
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

ReceiptGenerationResult _makeResult() => ReceiptGenerationResult(
  receiptId: 'r-1',
  pdfUrl: 'https://example.com/r-1.pdf',
  documentType: DocumentType.quittance,
  totalCents: 90000,
  periodStart: DateTime(2026, 1, 1),
  periodEnd: DateTime(2026, 1, 31),
);

Widget _buildWidget({required ReceiptsRepository repo}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: GenerateReceiptButton(paymentId: 'pay-1', leaseId: 'lease-1'),
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, _) => const Scaffold(body: Text('Profile Page')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [receiptsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
    ),
  );
}

/// Deux boutons "Générer une quittance" (deux paiements distincts) montés
/// côte à côte, comme dans une liste de paiements réelle. Sert à prouver que
/// l'état de génération est bien isolé par paiement : cliquer sur une ligne ne
/// doit ni allumer le spinner des autres lignes ni ouvrir plusieurs dialogues.
Widget _buildTwoButtons({required ReceiptsRepository repo}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Column(
            children: const [
              GenerateReceiptButton(paymentId: 'pay-1', leaseId: 'lease-1'),
              GenerateReceiptButton(paymentId: 'pay-2', leaseId: 'lease-1'),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, _) => const Scaffold(body: Text('Profile Page')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [receiptsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GenerateReceiptButton', () {
    testWidgets('icône receipt_long_outlined visible par défaut', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWidget(repo: _FakeReceiptsRepo(result: _makeResult())),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('btn_generate_receipt_pay-1')),
        findsOneWidget,
      );
    });

    testWidgets('clic → state submitting → spinner affiché', (tester) async {
      // Completer pour bloquer la génération sans laisser de timer pendant.
      final completer = Completer<ReceiptGenerationResult>();
      var generating = false;
      final repo = _ControlledRepo(() async {
        generating = true;
        return completer.future;
      });

      await tester.pumpWidget(_buildWidget(repo: repo));
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_generate_receipt_pay-1')));
      await tester.pump(); // laisse le future démarrer

      expect(generating, true);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Compléter pour nettoyer le future avant la fin du test.
      completer.complete(_makeResult());
      await tester.pumpAndSettle();
    });

    testWidgets('succès → dialog preview affiché', (tester) async {
      await tester.pumpWidget(
        _buildWidget(repo: _FakeReceiptsRepo(result: _makeResult())),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_generate_receipt_pay-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog_receipt_preview')), findsOneWidget);
    });

    testWidgets('erreur → SnackBar affiché', (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          repo: _FakeReceiptsRepo(
            exception: const ReceiptGenerationException('pdf error'),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_generate_receipt_pay-1')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('profileIncomplete → dialog ProfileIncompleteDialog affiché', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWidget(
          repo: _FakeReceiptsRepo(
            exception: const ProfileIncompleteException(
              missing: ['full_name', 'address'],
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_generate_receipt_pay-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('dialog_profile_incomplete')),
        findsOneWidget,
      );
    });
  });

  group('GenerateReceiptButton — isolation par paiement (bugs multi-lignes)', () {
    testWidgets(
      'clic sur une ligne → spinner UNIQUEMENT sur cette ligne, pas les autres',
      (tester) async {
        // Génération bloquée : le bouton cliqué reste en submitting le temps
        // de l'assertion.
        final completer = Completer<ReceiptGenerationResult>();
        final repo = _ControlledRepo(() => completer.future);

        await tester.pumpWidget(_buildTwoButtons(repo: repo));
        await tester.pump();

        await tester.tap(find.byKey(const Key('btn_generate_receipt_pay-1')));
        await tester.pump();

        // Un seul spinner, celui de pay-1 — pas un par ligne.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // pay-2 garde son icône au repos.
        expect(
          find.descendant(
            of: find.byKey(const Key('btn_generate_receipt_pay-2')),
            matching: find.byIcon(Icons.receipt_long_outlined),
          ),
          findsOneWidget,
        );

        completer.complete(_makeResult());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'succès avec plusieurs boutons montés → un SEUL dialog preview',
      (tester) async {
        await tester.pumpWidget(
          _buildTwoButtons(repo: _FakeReceiptsRepo(result: _makeResult())),
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('btn_generate_receipt_pay-1')));
        await tester.pumpAndSettle();

        // Un seul dialogue, pas un empilement (sinon N clics pour fermer).
        expect(find.byKey(const Key('dialog_receipt_preview')), findsOneWidget);
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Repo contrôlable pour test submitting
// ---------------------------------------------------------------------------

class _ControlledRepo implements ReceiptsRepository {
  final Future<ReceiptGenerationResult> Function() _generateFn;

  _ControlledRepo(this._generateFn);

  @override
  Future<List<Receipt>> listForLease(String leaseId) async => [];

  @override
  Future<Receipt> getById(String id) async => throw UnimplementedError();

  @override
  Future<ReceiptGenerationResult> generate({
    List<String>? paymentIds,
    String? leaseId,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) => _generateFn();

  @override
  Future<String> signedUrl(String pdfPath) async => throw UnimplementedError();

  @override
  Future<void> voidReceipt(String id, String reason) async {}

  @override
  Future<Receipt> markReceiptAsShared({
    required String receiptId,
    required String tenantEmail,
  }) async => throw UnimplementedError();

  @override
  Future<Uint8List> renderPdfBytes(String receiptId) async => Uint8List(0);
}
