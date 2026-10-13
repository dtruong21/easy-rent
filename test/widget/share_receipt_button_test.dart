/// Tests widget de [ShareReceiptButton].
///
/// Couvre :
/// - icône share_outlined si jamais partagée
/// - icône share si déjà partagée
/// - bouton désactivé (gris) si voided ou stale
/// - bouton désactivé si tenantEmail null ou vide
/// - clic → dialog confirmingResend si déjà partagée
/// - clic → état preparing → spinner CircularProgressIndicator
/// - partage natif réussi → SnackBar "presse-papier"
/// - fallback réussi → SnackBar "attacher manuellement"
/// - erreur → SnackBar avec message
library;

import 'dart:typed_data';
import 'dart:async';

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/receipts/application/share_receipt_controller.dart';
import 'package:easyrent/features/receipts/data/receipts_repository.dart';
import 'package:easyrent/features/receipts/data/web_share_service_bridge.dart';
import 'package:easyrent/features/receipts/domain/document_type.dart';
import 'package:easyrent/features/receipts/domain/receipt.dart';
import 'package:easyrent/features/receipts/domain/receipt_action_error.dart';
import 'package:easyrent/features/receipts/domain/receipt_generation_result.dart';
import 'package:easyrent/features/receipts/domain/share_receipt_state.dart';
import 'package:easyrent/features/receipts/presentation/widgets/share_receipt_button.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements ReceiptsRepository {
  final Completer<Receipt>? _completer;
  final Receipt? _markedReceipt;

  const _FakeRepo({Completer<Receipt>? completer, Receipt? markedReceipt})
    : _completer = completer,
      _markedReceipt = markedReceipt;

  @override
  Future<Receipt> markReceiptAsShared({
    required String receiptId,
    required String tenantEmail,
  }) async {
    if (_completer != null) return _completer.future;
    if (_markedReceipt != null) return _markedReceipt;
    throw StateError('no result configured');
  }

  @override
  Future<String> signedUrl(String pdfPath) async =>
      'https://example.com/signed.pdf';

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
  }) async => throw UnimplementedError();

  @override
  Future<void> voidReceipt(String id, String reason) async {}

  @override
  Future<Uint8List> renderPdfBytes(String receiptId) async => Uint8List(0);
}

// ---------------------------------------------------------------------------
// Mock WebShareService
// ---------------------------------------------------------------------------

class _MockWebShare implements WebShareService {
  final bool _canShare;
  final Exception? _shareException;
  final Completer<void>? _shareCompleter;

  const _MockWebShare({
    bool canShare = true,
    Exception? shareException,
    Completer<void>? shareCompleter,
  }) : _canShare = canShare,
       _shareException = shareException,
       _shareCompleter = shareCompleter;

  @override
  bool canShareFiles() => _canShare;

  @override
  Future<bool> openPdfBytes({
    required List<int> pdfBytes,
    required String filename,
  }) async => false;

  @override
  Future<void> sharePdf({
    required String title,
    required String text,
    required List<int> pdfBytes,
    required String filename,
  }) async {
    if (_shareCompleter != null) return _shareCompleter.future;
    if (_shareException != null) throw _shareException;
  }

  @override
  Future<bool> copyToClipboard(String text) async => true;

  @override
  Future<List<int>> fetchBytes(String url) async => [1, 2, 3];

  @override
  Future<void> deliverFile({
    required String filename,
    required String mimeType,
    required List<int> bytes,
    String? shareTitle,
  }) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Receipt _makeReceipt({
  String id = 'r-1',
  bool isVoided = false,
  bool isStale = false,
  DateTime? sentAt,
  String? sentToEmail,
}) => Receipt(
  id: id,
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  paymentIds: ['pay-1'],
  periodStart: DateTime(2026, 3, 1),
  periodEnd: DateTime(2026, 3, 31),
  totalCents: 90000,
  rentCents: 85000,
  chargesCents: 5000,
  documentType: DocumentType.quittance,
  pdfPath: 'landlord-1/r-1.pdf',
  isVoided: isVoided,
  isStale: isStale,
  generatedAt: DateTime(2026, 4, 1),
  createdAt: DateTime(2026, 4, 1),
  sentAt: sentAt,
  sentToEmail: sentToEmail,
);

Receipt _makeSharedReceipt() => _makeReceipt(
  sentAt: DateTime(2026, 5, 1, 10),
  sentToEmail: 'loc@example.com',
);

Widget _buildWidget({
  required Receipt receipt,
  ReceiptsRepository? repo,
  WebShareService? webShare,
  String? tenantEmail = 'loc@example.com',
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: ShareReceiptButton(
            receipt: receipt,
            leaseId: 'lease-1',
            tenantEmail: tenantEmail,
            tenantFirstName: 'Jean',
            propertyAddress: '12 rue de la Paix',
            landlordFullName: 'Marie Martin',
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      if (repo != null) receiptsRepositoryProvider.overrideWithValue(repo),
      if (webShare != null) webShareServiceProvider.overrideWithValue(webShare),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
    ),
  );
}

/// Deux boutons de partage (deux quittances distinctes) montés côte à côte,
/// comme dans une liste de quittances. Sert à prouver que l'état de partage est
/// isolé par quittance : partager une ligne ne doit pas allumer le spinner des
/// autres.
Widget _buildTwoButtons({
  required ReceiptsRepository repo,
  required WebShareService webShare,
}) {
  ShareReceiptButton button(String id) => ShareReceiptButton(
    receipt: _makeReceipt(id: id),
    leaseId: 'lease-1',
    tenantEmail: 'loc@example.com',
    tenantFirstName: 'Jean',
    propertyAddress: '12 rue de la Paix',
    landlordFullName: 'Marie Martin',
  );

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) =>
            Scaffold(body: Column(children: [button('r-1'), button('r-2')])),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      receiptsRepositoryProvider.overrideWithValue(repo),
      webShareServiceProvider.overrideWithValue(webShare),
    ],
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
  group('ShareReceiptButton — icônes au repos', () {
    testWidgets('icône share_outlined si jamais partagée', (tester) async {
      await tester.pumpWidget(
        _buildWidget(receipt: _makeReceipt(), repo: const _FakeRepo()),
      );
      await tester.pump();
      expect(find.byKey(const Key('btn_share_receipt_r-1')), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsWidgets);
      expect(find.byIcon(Icons.share), findsNothing);
    });

    testWidgets('icône share (plein) si déjà partagée', (tester) async {
      await tester.pumpWidget(
        _buildWidget(receipt: _makeSharedReceipt(), repo: const _FakeRepo()),
      );
      await tester.pump();
      expect(find.byKey(const Key('btn_share_receipt_r-1')), findsOneWidget);
      // Icons.share est présent (bouton actif, déjà partagée).
      expect(find.byIcon(Icons.share), findsWidgets);
    });
  });

  group('ShareReceiptButton — boutons désactivés', () {
    testWidgets('bouton désactivé si voided', (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(isVoided: true),
          repo: const _FakeRepo(),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('btn_share_receipt_disabled_r-1')),
        findsOneWidget,
      );
    });

    testWidgets('bouton désactivé si stale', (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(isStale: true),
          repo: const _FakeRepo(),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('btn_share_receipt_disabled_r-1')),
        findsOneWidget,
      );
    });

    testWidgets('bouton désactivé si tenantEmail null', (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(),
          repo: const _FakeRepo(),
          tenantEmail: null,
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('btn_share_receipt_no_email_r-1')),
        findsOneWidget,
      );
    });

    testWidgets('bouton désactivé si tenantEmail vide', (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(),
          repo: const _FakeRepo(),
          tenantEmail: '',
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('btn_share_receipt_no_email_r-1')),
        findsOneWidget,
      );
    });
  });

  group('ShareReceiptButton — état preparing', () {
    testWidgets('clic → spinner CircularProgressIndicator', (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(),
          repo: const _FakeRepo(markedReceipt: null),
          webShare: _MockWebShare(canShare: true, shareCompleter: completer),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_share_receipt_r-1')));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.completeError(Exception('cleanup'));
      await tester.pumpAndSettle();
    });
  });

  group('ShareReceiptButton — partage natif réussi', () {
    testWidgets('SnackBar "presse-papier" après partage natif', (tester) async {
      final markedReceipt = _makeReceipt(
        sentAt: DateTime(2026, 6, 1),
        sentToEmail: 'loc@example.com',
      );
      await tester.pumpWidget(
        _buildWidget(
          receipt: _makeReceipt(),
          repo: _FakeRepo(markedReceipt: markedReceipt),
          webShare: const _MockWebShare(canShare: true),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_share_receipt_r-1')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('presse-papier'), findsOneWidget);
    });
  });

  group('ShareReceiptButton — dialog confirmingResend', () {
    testWidgets('clic sur quittance déjà partagée → dialog confirmation', (
      tester,
    ) async {
      final sharedReceipt = _makeSharedReceipt();
      await tester.pumpWidget(
        _buildWidget(
          receipt: sharedReceipt,
          repo: _FakeRepo(markedReceipt: sharedReceipt),
          webShare: const _MockWebShare(canShare: true),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_share_receipt_r-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog_confirm_resend')), findsOneWidget);
    });

    testWidgets('annuler le dialog → dialog fermé', (tester) async {
      final sharedReceipt = _makeSharedReceipt();
      await tester.pumpWidget(
        _buildWidget(
          receipt: sharedReceipt,
          repo: _FakeRepo(markedReceipt: sharedReceipt),
          webShare: const _MockWebShare(canShare: true),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_share_receipt_r-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_resend_cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog_confirm_resend')), findsNothing);
    });
  });

  group('ShareReceiptButton — erreur', () {
    testWidgets('erreur générique → SnackBar avec message', (tester) async {
      // On override directement le controller pour simuler l'erreur.
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: ShareReceiptButton(
                receipt: _makeReceipt(),
                leaseId: 'lease-1',
                tenantEmail: 'loc@example.com',
                tenantFirstName: 'Jean',
                propertyAddress: '12 rue de la Paix',
                landlordFullName: 'Marie Martin',
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            receiptsRepositoryProvider.overrideWithValue(const _FakeRepo()),
            // Override du controller pour injecter directement l'état erreur.
            shareReceiptControllerProvider.overrideWith(
              (ref, _) => _ErrorController(ref),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            locale: const Locale('fr'),
            supportedLocales: supportedLocales,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_share_receipt_r-1')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      // FEAT-043 (i18n) : le contrôleur ne stocke plus un message FR libre
      // mais le nom (stable) du ReceiptActionError ; la présentation le
      // reconvertit via ReceiptActionErrorL10n. Un code non reconnu retombe
      // sur le message générique `unknown`.
      expect(find.textContaining('Une erreur est survenue'), findsOneWidget);
    });
  });

  group('ShareReceiptButton — isolation par quittance (bug multi-lignes)', () {
    testWidgets('partager une quittance → spinner UNIQUEMENT sur cette ligne', (
      tester,
    ) async {
      // Partage bloqué : le bouton cliqué reste en "preparing" (spinner) le
      // temps de l'assertion.
      final completer = Completer<void>();
      await tester.pumpWidget(
        _buildTwoButtons(
          repo: const _FakeRepo(),
          webShare: _MockWebShare(canShare: true, shareCompleter: completer),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_share_receipt_r-1')));
      await tester.pump();

      // Un seul spinner (r-1), pas un par ligne.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // r-2 garde son icône de partage au repos.
      expect(find.byKey(const Key('btn_share_receipt_r-2')), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();
    });
  });
}

/// Controller de test qui génère une erreur simulée (générique, non
/// reconnue — retombe sur [ReceiptActionError.unknown] côté présentation).
class _ErrorController extends ShareReceiptController {
  _ErrorController(super.ref);

  @override
  Future<void> initiate({
    required Receipt receipt,
    required String leaseId,
    required String tenantEmail,
    required String tenantFirstName,
    required String propertyAddress,
    required String landlordFullName,
  }) async {
    state = ShareReceiptState.error(message: ReceiptActionError.unknown.name);
  }
}
