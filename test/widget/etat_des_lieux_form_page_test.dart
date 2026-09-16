/// Tests widget de [EtatDesLieuxFormPage] (FEAT-037).
///
/// Couvre : template par défaut (5 pièces), ajout/suppression pièce+élément,
/// changement de condition via le dropdown, soumission → appel du repo
/// (mocké) avec les bons paramètres, erreur → SnackBar.
///
/// Le rendu PDF réel (polices embarquées, `package:pdf`) et l'ouverture
/// (`url_launcher`) sont volontairement contournés : le renderer est injecté
/// via [etatDesLieuxPdfRendererProvider] (patron
/// `chargeRegularizationPdfRendererProvider`), et [webShareServiceProvider]
/// est overridé par un faux [WebShareService] dont `openPdfBytes` répond
/// `true` pour ne jamais atteindre `launchUrl`.
library;

import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/etat_des_lieux/data/etat_des_lieux_repository.dart';
import 'package:easyrent/features/etat_des_lieux/domain/edl_enums.dart';
import 'package:easyrent/features/etat_des_lieux/domain/etat_des_lieux.dart';
import 'package:easyrent/features/etat_des_lieux/presentation/etat_des_lieux_form_page.dart';
import 'package:easyrent/features/receipts/data/web_share_service_bridge.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeEtatDesLieuxRepository implements EtatDesLieuxRepository {
  _FakeEtatDesLieuxRepository({this.result, this.exception});

  final EtatDesLieux? result;
  final Exception? exception;

  // Arguments capturés du dernier appel à create().
  String? capturedLeaseId;
  EtatDesLieuxType? capturedType;
  DateTime? capturedDate;
  List<EdlRoom>? capturedRooms;
  EdlMeterReadings? capturedMeterReadings;
  int? capturedKeysCount;
  String? capturedGeneralComment;

  @override
  Future<EtatDesLieux> create({
    required String leaseId,
    required EtatDesLieuxType type,
    required DateTime date,
    required List<EdlRoom> rooms,
    required EdlMeterReadings meterReadings,
    required int keysCount,
    String? generalComment,
  }) async {
    capturedLeaseId = leaseId;
    capturedType = type;
    capturedDate = date;
    capturedRooms = rooms;
    capturedMeterReadings = meterReadings;
    capturedKeysCount = keysCount;
    capturedGeneralComment = generalComment;
    if (exception != null) throw exception!;
    if (result != null) return result!;
    throw StateError('no result configured');
  }

  @override
  Future<List<EtatDesLieux>> listForLease(String leaseId) async => [];

  @override
  Future<EtatDesLieux> getById(String id) async => throw UnimplementedError();
}

/// Toujours no-op, sûr en test — [openPdfBytes] répond `true` pour que le
/// flow succès ne tente jamais `launchUrl` (indisponible hors app réelle).
class _FakeWebShareService implements WebShareService {
  @override
  bool canShareFiles() => false;

  @override
  Future<void> sharePdf({
    required String title,
    required String text,
    required List<int> pdfBytes,
    required String filename,
  }) async {}

  @override
  Future<bool> copyToClipboard(String text) async => false;

  @override
  Future<List<int>> fetchBytes(String url) async => const [];

  @override
  Future<bool> openPdfBytes({
    required List<int> pdfBytes,
    required String filename,
  }) async => true;

  @override
  Future<void> deliverFile({
    required String filename,
    required String mimeType,
    required List<int> bytes,
    String? shareTitle,
  }) async {}
}

/// Renderer factice — le vrai [renderEtatDesLieuxPdf] embarque des polices et
/// est coûteux/inutile à exécuter dans ce test (déjà couvert indépendamment
/// par `etat_des_lieux_pdf_renderer_test.dart`).
Future<Uint8List> _fakeRenderer(EtatDesLieux edl) async =>
    Uint8List.fromList(const [1, 2, 3]);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

EtatDesLieux _makeEdl() => EtatDesLieux(
  id: 'edl-1',
  landlordId: 'landlord-1',
  leaseId: 'lease-1',
  type: EtatDesLieuxType.entree,
  date: DateTime(2026, 9, 16),
  propertyAddress: '1 rue du Test, 75000 Paris',
  landlordFullName: 'Jean Bailleur',
  landlordAddress: '2 rue du Bailleur, 75000 Paris',
  tenantFullName: 'Marie Locataire',
  rooms: const [],
  meterReadings: EdlMeterReadings(),
  keysCount: 2,
  createdAt: DateTime(2026, 9, 16),
);

Widget _buildPage({
  required EtatDesLieuxRepository repo,
  WebShareService? webShare,
}) {
  return ProviderScope(
    overrides: [
      etatDesLieuxRepositoryProvider.overrideWithValue(repo),
      webShareServiceProvider.overrideWithValue(
        webShare ?? _FakeWebShareService(),
      ),
      etatDesLieuxPdfRendererProvider.overrideWithValue(_fakeRenderer),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
      home: const EtatDesLieuxFormPage(leaseId: 'lease-1'),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EtatDesLieuxFormPage', () {
    testWidgets('template par défaut : 5 pièces rendues', (tester) async {
      await tester.pumpWidget(_buildPage(repo: _FakeEtatDesLieuxRepository()));
      await tester.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('edl_room_card_$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('edl_room_card_5')), findsNothing);

      expect(find.text('Séjour'), findsOneWidget);
      expect(find.text('Chambre'), findsOneWidget);
      expect(find.text('Cuisine'), findsOneWidget);
      expect(find.text('Salle de bain'), findsOneWidget);
      expect(find.text('WC'), findsOneWidget);
    });

    testWidgets('ajout puis suppression d\'une pièce', (tester) async {
      await tester.pumpWidget(_buildPage(repo: _FakeEtatDesLieuxRepository()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('edl_add_room_button')));
      await tester.tap(find.byKey(const Key('edl_add_room_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edl_room_card_5')), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('edl_remove_room_button_5')),
      );
      await tester.tap(find.byKey(const Key('edl_remove_room_button_5')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edl_room_card_5')), findsNothing);
    });

    testWidgets('ajout puis suppression d\'un élément dans une pièce', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage(repo: _FakeEtatDesLieuxRepository()));
      await tester.pumpAndSettle();

      // Séjour (pièce 0) a 3 éléments par défaut (Sol, Murs, Plafond) →
      // l'ajout crée l'index 3.
      await tester.ensureVisible(
        find.byKey(const Key('edl_add_element_button_0')),
      );
      await tester.tap(find.byKey(const Key('edl_add_element_button_0')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('edl_element_name_field_0_3')),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('edl_remove_element_button_0_3')),
      );
      await tester.tap(find.byKey(const Key('edl_remove_element_button_0_3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edl_element_name_field_0_3')), findsNothing);
    });

    testWidgets('changement de condition via le dropdown', (tester) async {
      await tester.pumpWidget(_buildPage(repo: _FakeEtatDesLieuxRepository()));
      await tester.pumpAndSettle();

      const dropdownKey = Key('edl_element_condition_dropdown_0_0');
      expect(
        find.descendant(
          of: find.byKey(dropdownKey),
          matching: find.text('Bon'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(dropdownKey));
      await tester.tap(find.byKey(dropdownKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mauvais').last);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(dropdownKey),
          matching: find.text('Mauvais'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'Générer appelle repository.create avec les paramètres attendus',
      (tester) async {
        final repo = _FakeEtatDesLieuxRepository(result: _makeEdl());
        await tester.pumpWidget(_buildPage(repo: repo));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('edl_generate_button')),
        );
        await tester.tap(find.byKey(const Key('edl_generate_button')));
        await tester.pumpAndSettle();

        expect(repo.capturedLeaseId, 'lease-1');
        expect(repo.capturedType, EtatDesLieuxType.entree);
        expect(repo.capturedRooms, isNotNull);
        expect(repo.capturedRooms!.length, 5);
        expect(repo.capturedKeysCount, 2);
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );

    testWidgets('erreur du repo → SnackBar affiché', (tester) async {
      final repo = _FakeEtatDesLieuxRepository(
        exception: FirebaseFunctionsException(
          message: 'internal',
          code: 'internal',
        ),
      );
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('edl_generate_button')));
      await tester.tap(find.byKey(const Key('edl_generate_button')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text('Une erreur est survenue. Veuillez réessayer.'),
        findsOneWidget,
      );
    });

    testWidgets('erreur profil incomplet → SnackBar dédié', (tester) async {
      final repo = _FakeEtatDesLieuxRepository(
        exception: FirebaseFunctionsException(
          message: 'profile_incomplete',
          code: 'failed-precondition',
        ),
      );
      await tester.pumpWidget(_buildPage(repo: repo));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('edl_generate_button')));
      await tester.tap(find.byKey(const Key('edl_generate_button')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Complétez votre profil bailleur (nom, adresse) avant de générer '
          'un état des lieux.',
        ),
        findsOneWidget,
      );
    });
  });
}
