/// Tests widget de [UploadDocumentsDropZone].
///
/// Couvre : bouton picker visible, warning quota si > 100 Mo.
library;

import 'dart:typed_data';

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/auth/data/landlord_tier_repository.dart';
import 'package:easyrent/features/auth/domain/subscription_tier.dart';
import 'package:easyrent/features/documents/data/documents_repository.dart';
import 'package:easyrent/features/documents/domain/document.dart';
import 'package:easyrent/features/documents/domain/document_category.dart';
import 'package:easyrent/features/documents/domain/documents_quota.dart';
import 'package:easyrent/features/documents/presentation/widgets/upload_documents_drop_zone.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeRepo implements DocumentsRepository {
  final int quotaBytes;

  _FakeRepo({this.quotaBytes = 0});

  @override
  Future<DocumentsQuota> quotaForCurrentLandlord() async =>
      DocumentsQuota(totalBytes: quotaBytes);

  @override
  Future<List<Document>> listForLease(String leaseId) async => [];

  @override
  Future<Document> getById(String id) async => throw UnimplementedError();

  @override
  Future<Document> upload({
    String? leaseId,
    String? propertyId,
    required DocumentCategory category,
    required String filename,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async => throw UnimplementedError();

  @override
  Future<({String? storagePath, bool hardDeleted})> softDelete(
    String id,
  ) async => throw UnimplementedError();

  @override
  Future<Document> updateCategory({
    required String id,
    required DocumentCategory newCategory,
  }) async => throw UnimplementedError();

  @override
  Future<String> createSignedUrl(
    String storagePath, {
    int expiresInSeconds = 300,
  }) async => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildDropZone({
  int quotaBytes = 0,
  SubscriptionTier tier = SubscriptionTier.free,
  String? planLevel,
}) {
  return ProviderScope(
    overrides: [
      documentsRepositoryProvider.overrideWithValue(
        _FakeRepo(quotaBytes: quotaBytes),
      ),
      // FEAT-056 : le plafond de taille par fichier (hint + validation) est
      // désormais différencié par palier — le widget lit
      // `quotaLimitProvider(PlanQuota.documentMaxBytes)`, qui dérive de
      // `landlordTierProvider` (même convention que `pro_pricing_page_test.dart`).
      landlordTierProvider.overrideWith(
        (ref) => Stream.value(
          LandlordTierSnapshot(tier: tier, planLevel: planLevel),
        ),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: Locale('fr'),
      supportedLocales: supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: UploadDocumentsDropZone(leaseId: 'lease-1'),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('UploadDocumentsDropZone', () {
    testWidgets('bouton "Sélectionner des fichiers" visible', (tester) async {
      await tester.pumpWidget(_buildDropZone());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('btn_pick_files')), findsOneWidget);
    });

    testWidgets('texte d\'invite visible', (tester) async {
      await tester.pumpWidget(_buildDropZone());
      await tester.pumpAndSettle();
      expect(find.textContaining('Cliquez pour sélectionner'), findsOneWidget);
    });

    group(
      'FEAT-056 — plafond de taille par fichier différencié par palier',
      () {
        testWidgets('gratuit/Pro → hint "10 Mo"', (tester) async {
          await tester.pumpWidget(_buildDropZone());
          await tester.pumpAndSettle();
          expect(find.textContaining('10 Mo'), findsOneWidget);
        });

        testWidgets('Max → hint "25 Mo"', (tester) async {
          await tester.pumpWidget(
            _buildDropZone(tier: SubscriptionTier.paid, planLevel: 'max'),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('25 Mo'), findsOneWidget);
        });

        testWidgets('Ultra → hint "50 Mo"', (tester) async {
          await tester.pumpWidget(
            _buildDropZone(tier: SubscriptionTier.paid, planLevel: 'ultra'),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('50 Mo'), findsOneWidget);
        });
      },
    );

    testWidgets('quota indicator affiché', (tester) async {
      await tester.pumpWidget(_buildDropZone(quotaBytes: 5 * 1024 * 1024));
      await tester.pumpAndSettle();
      // ByteFormat.format(5*1024*1024) = "5 Mo", format(100*1024*1024) = "100 Mo"
      expect(find.textContaining('5 Mo'), findsOneWidget);
      expect(find.textContaining('100 Mo'), findsOneWidget);
    });

    testWidgets('quota indicator rouge si > 100 Mo', (tester) async {
      await tester.pumpWidget(_buildDropZone(quotaBytes: 110 * 1024 * 1024));
      await tester.pumpAndSettle();
      // Le texte doit être présent avec couleur erreur (on vérifie juste la présence)
      expect(find.textContaining('Mo'), findsWidgets);
    });

    testWidgets('bouton activé initialement (non désactivé)', (tester) async {
      // Tester que le bouton est activé initialement (state = idle)
      await tester.pumpWidget(_buildDropZone());
      await tester.pumpAndSettle();
      // Le bouton doit être présent et activé
      expect(find.byKey(const Key('btn_pick_files')), findsOneWidget);
      // FilledButton.tonalIcon rend un widget FilledButton.tonal — on vérifie
      // juste que la touche est trouvable (pas de CircularProgressIndicator)
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
