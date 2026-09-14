import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../receipts/data/web_share_service_bridge.dart';
import '../data/charge_statement_repository.dart';
import '../domain/charge_regularization_balance.dart';
import '../domain/charge_regularization_pdf_renderer.dart';
import '../domain/charge_regularization_share_error_reason.dart';
import '../domain/charge_regularization_share_payload_builder.dart';
import '../domain/charge_regularization_share_state.dart';
import '../domain/charge_statement.dart';

final _log = Logger('ChargeStatementFinalizeController');

/// Signature de [renderChargeRegularizationPdf] — indirection Riverpod pour
/// permettre aux tests d'injecter un renderer factice (le rendu réel
/// embarque des polices et est coûteux à exécuter dans une suite unitaire,
/// cf. FEAT-033 task-7 brief : "ne pas rendre un vrai PDF dans le test").
typedef ChargeRegularizationPdfRenderer =
    Future<Uint8List> Function(ChargeRegularizationPdfData data);

final chargeRegularizationPdfRendererProvider =
    Provider<ChargeRegularizationPdfRenderer>(
      (ref) => renderChargeRegularizationPdf,
    );

/// Orchestration finalisation + génération PDF (depuis snapshot figé) +
/// partage + marquage "envoyé" de l'avis de régularisation des charges
/// (FEAT-033).
///
/// Contrairement à [ChargeRegularizationShareController] (V1.2, FEAT-029),
/// ce contrôleur :
/// - appelle `finalize` AVANT de rendre le PDF — un décompte `ChargeStatement`
///   immuable est créé côté serveur (callable `finalizeChargeRegularization`,
///   Task 6/7) ;
/// - re-rend le PDF exclusivement à partir de ce snapshot figé
///   ([ChargeRegularizationPdfData.fromStatement]), jamais depuis les valeurs
///   de formulaire en direct ;
/// - marque le décompte comme envoyé (`markAsSent`) après un partage réussi.
///
/// Réutilise la mécanique de partage de `charge_regularization_share_controller.dart`
/// (Web Share API + fallback téléchargement + mailto:, mêmes exceptions).
class ChargeStatementFinalizeController
    extends StateNotifier<ChargeRegularizationShareState> {
  ChargeStatementFinalizeController(this._ref)
    : super(const ChargeRegularizationShareState.idle());

  final Ref _ref;

  /// Finalise le décompte (snapshot serveur immuable), rend le PDF depuis ce
  /// snapshot, puis partage et marque le décompte comme envoyé.
  ///
  /// [landlordFullName], [landlordAddress], [tenantFullName] et
  /// [propertyAddress] correspondent aux valeurs du formulaire au moment de
  /// l'appel — elles ne sont PAS utilisées pour rendre le PDF ni construire
  /// le message de partage : une fois le décompte finalisé, le snapshot
  /// serveur (`statement`, relu via `getById`) devient l'unique source de
  /// vérité pour ces champs (constraint FEAT-033 : "PDF rendered client-side
  /// from frozen fields only"). Elles ne sont conservées dans la signature
  /// que pour la symétrie d'appel avec le formulaire (Task 8/9 UI) et un
  /// éventuel usage de validation ultérieur.
  Future<void> finalizeAndShare({
    required String leaseId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int actualExpensesCents,
    required String actualExpensesSource,
    required List<Map<String, dynamic>> lineItems,
    required String landlordFullName,
    required String landlordAddress,
    required String tenantFullName,
    required String tenantFirstName,
    required String propertyAddress,
    String? tenantEmail,
  }) async {
    state = const ChargeRegularizationShareState.preparing();

    try {
      final repo = _ref.read(chargeStatementRepositoryProvider);

      final result = await repo.finalize(
        leaseId: leaseId,
        periodStart: periodStart,
        periodEnd: periodEnd,
        actualExpensesCents: actualExpensesCents,
        actualExpensesSource: actualExpensesSource,
        lineItems: lineItems,
      );
      final statement = await repo.getById(result.statementId);

      await _renderShareAndMarkSent(
        statement: statement,
        // Le décompte figé porte déjà tenantFirstName/landlordFullName —
        // on privilégie ces valeurs de formulaire tant qu'elles sont
        // fournies, avec repli sur le snapshot sinon (mêmes valeurs en
        // pratique juste après finalize()).
        tenantFirstName: tenantFirstName,
        landlordFullName: landlordFullName,
        tenantEmail: tenantEmail,
      );
    } on ShareAbortedException {
      _log.info('partage annulé par l\'utilisateur (AbortError)');
      state = const ChargeRegularizationShareState.idle();
    } on ShareReceiptException catch (e, st) {
      _log.warning('erreur de partage', e, st);
      state = ChargeRegularizationShareState.error(
        message: ChargeRegularizationShareErrorReason.shareFailed.name,
      );
    } catch (e, st) {
      _log.severe('erreur inattendue finalisation/génération/partage', e, st);
      state = ChargeRegularizationShareState.error(
        message: ChargeRegularizationShareErrorReason.unknown.name,
      );
    }
  }

  /// Re-partage un décompte déjà finalisé, sans re-finaliser — utilisé par
  /// l'historique (re-partage d'un décompte existant, Task 9). Le PDF est
  /// re-rendu à l'identique depuis le snapshot figé [s].
  Future<void> shareExisting(
    ChargeStatement s, {
    String? tenantEmail,
    String? tenantFirstName,
    String? landlordFullName,
  }) async {
    state = const ChargeRegularizationShareState.preparing();

    try {
      await _renderShareAndMarkSent(
        statement: s,
        tenantFirstName: tenantFirstName ?? s.tenantFirstName,
        landlordFullName: landlordFullName ?? s.landlordFullName,
        tenantEmail: tenantEmail,
      );
    } on ShareAbortedException {
      _log.info('re-partage annulé par l\'utilisateur (AbortError)');
      state = const ChargeRegularizationShareState.idle();
    } on ShareReceiptException catch (e, st) {
      _log.warning('erreur de re-partage', e, st);
      state = ChargeRegularizationShareState.error(
        message: ChargeRegularizationShareErrorReason.shareFailed.name,
      );
    } catch (e, st) {
      _log.severe('erreur inattendue re-partage', e, st);
      state = ChargeRegularizationShareState.error(
        message: ChargeRegularizationShareErrorReason.unknown.name,
      );
    }
  }

  /// Rend le PDF depuis [statement] (snapshot figé), le partage, puis marque
  /// le décompte comme envoyé une fois le partage réussi. Laisse les
  /// exceptions se propager — chaque appelant public gère ses propres
  /// transitions d'état (idle/error).
  Future<void> _renderShareAndMarkSent({
    required ChargeStatement statement,
    required String tenantFirstName,
    required String landlordFullName,
    String? tenantEmail,
  }) async {
    final webShare = _ref.read(webShareServiceProvider);
    final pdfRenderer = _ref.read(chargeRegularizationPdfRendererProvider);

    final pdfBytes = await pdfRenderer(
      ChargeRegularizationPdfData.fromStatement(statement),
    );

    final payload = ChargeRegularizationSharePayloadBuilder.build(
      balance: ChargeRegularizationBalance(
        periodStart: statement.periodStart,
        periodEnd: statement.periodEnd,
        provisionsCollectedCents: statement.provisionsCollectedCents,
        actualExpensesCents: statement.actualExpensesCents,
      ),
      tenantFirstName: tenantFirstName,
      propertyAddress: statement.propertyAddress,
      landlordFullName: landlordFullName,
    );

    bool usedNativeShare;

    if (webShare.canShareFiles()) {
      await webShare.sharePdf(
        title: payload.subject,
        text: payload.body,
        pdfBytes: pdfBytes,
        filename: payload.filename,
      );
      if (tenantEmail != null && tenantEmail.isNotEmpty) {
        await webShare.copyToClipboard(tenantEmail);
      }
      usedNativeShare = true;
    } else {
      // Fallback : data URL + téléchargement, puis mailto: si un email
      // locataire est disponible (même mécanisme que
      // ChargeRegularizationShareController).
      final base64 = base64Encode(pdfBytes);
      final dataUrl = 'data:application/pdf;base64,$base64';
      await launchUrl(Uri.parse(dataUrl), mode: LaunchMode.externalApplication);

      if (tenantEmail != null && tenantEmail.isNotEmpty) {
        final mailtoUri = Uri(
          scheme: 'mailto',
          path: tenantEmail,
          queryParameters: {'subject': payload.subject, 'body': payload.body},
        );
        await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
      }
      usedNativeShare = false;
    }

    await _ref
        .read(chargeStatementRepositoryProvider)
        .markAsSent(id: statement.id, email: tenantEmail);

    _log.info(
      'décompte de régularisation partagé et marqué envoyé '
      '(id=${statement.id}, native=$usedNativeShare)',
    );
    state = ChargeRegularizationShareState.shared(
      usedNativeShare: usedNativeShare,
    );
  }

  /// Remet le controller à l'état idle.
  void reset() => state = const ChargeRegularizationShareState.idle();
}

/// Provider autoDispose du contrôleur de finalisation — [autoDispose]
/// garantit un state propre entre deux ouvertures du dialog.
final chargeStatementFinalizeControllerProvider =
    StateNotifierProvider.autoDispose<
      ChargeStatementFinalizeController,
      ChargeRegularizationShareState
    >((ref) => ChargeStatementFinalizeController(ref));
