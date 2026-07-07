import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../receipts/data/web_share_service_bridge.dart';
import '../domain/charge_regularization_balance.dart';
import '../domain/charge_regularization_pdf_renderer.dart';
import '../domain/charge_regularization_share_error_reason.dart';
import '../domain/charge_regularization_share_payload_builder.dart';
import '../domain/charge_regularization_share_state.dart';

final _log = Logger('ChargeRegularizationShareController');

/// Orchestration génération PDF + partage de l'avis de régularisation des
/// charges (FEAT-029 V1.2).
///
/// Contrairement à [ShareReceiptController] (receipts), il n'y a ici NI doc
/// Firestore à créer, NI marquage "envoyé" après coup — le PDF est un
/// artefact ponctuel généré à la volée (V1, cf. backlog § « Out of scope » :
/// « pas d'archivage » assumé, dépend de la remise en état de `functions/`
/// pour une future catégorie `charge_statement` sur `documents`, V2).
///
/// Réutilise [WebShareService] (Web Share API + fallback téléchargement +
/// mailto:), exactement le mécanisme des quittances.
class ChargeRegularizationShareController
    extends StateNotifier<ChargeRegularizationShareState> {
  ChargeRegularizationShareController(this._ref)
    : super(const ChargeRegularizationShareState.idle());

  final Ref _ref;

  /// Génère le PDF et déclenche le partage.
  ///
  /// [tenantEmail] est optionnel : si absent, le fallback mailto: est
  /// simplement sauté (pas de blocage — contrairement aux quittances, la
  /// régularisation n'a pas de contrainte "email obligatoire", elle reste
  /// utile même seulement téléchargée par le bailleur).
  Future<void> generateAndShare({
    required ChargeRegularizationBalance balance,
    required String landlordFullName,
    required String landlordAddress,
    required String tenantFullName,
    required String tenantFirstName,
    required String propertyAddress,
    String? tenantEmail,
  }) async {
    state = const ChargeRegularizationShareState.preparing();

    try {
      final webShare = _ref.read(webShareServiceProvider);

      final pdfBytes = await renderChargeRegularizationPdf(
        ChargeRegularizationPdfData(
          landlordFullName: landlordFullName,
          landlordAddress: landlordAddress,
          tenantFullName: tenantFullName,
          propertyAddress: propertyAddress,
          balance: balance,
          generatedAt: DateTime.now(),
        ),
      );

      final payload = ChargeRegularizationSharePayloadBuilder.build(
        balance: balance,
        tenantFirstName: tenantFirstName,
        propertyAddress: propertyAddress,
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
        // locataire est disponible.
        final base64 = base64Encode(pdfBytes);
        final dataUrl = 'data:application/pdf;base64,$base64';
        await launchUrl(
          Uri.parse(dataUrl),
          mode: LaunchMode.externalApplication,
        );

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

      _log.info(
        'avis de régularisation partagé (native=$usedNativeShare, '
        'solde=${balance.balanceCents})',
      );
      state = ChargeRegularizationShareState.shared(
        usedNativeShare: usedNativeShare,
      );
    } on ShareAbortedException {
      _log.info('partage annulé par l\'utilisateur (AbortError)');
      state = const ChargeRegularizationShareState.idle();
    } on ShareReceiptException catch (e, st) {
      _log.warning('erreur de partage', e, st);
      // FEAT-043 : le message technique de [e] (parfois un DOMException brut,
      // non traduit / non FR) n'est plus stocké tel quel — seul le code
      // stable [ChargeRegularizationShareErrorReason.shareFailed] est
      // conservé ; le détail reste consultable dans les logs ci-dessus (même
      // pattern que `ShareReceiptController`, receipts, FEAT-043).
      state = ChargeRegularizationShareState.error(
        message: ChargeRegularizationShareErrorReason.shareFailed.name,
      );
    } catch (e, st) {
      _log.severe('erreur inattendue génération/partage', e, st);
      state = ChargeRegularizationShareState.error(
        message: ChargeRegularizationShareErrorReason.unknown.name,
      );
    }
  }

  /// Remet le controller à l'état idle.
  void reset() => state = const ChargeRegularizationShareState.idle();
}

/// Provider autoDispose du contrôleur de partage de régularisation —
/// [autoDispose] garantit un state propre entre deux ouvertures du dialog.
final chargeRegularizationShareControllerProvider =
    StateNotifierProvider.autoDispose<
      ChargeRegularizationShareController,
      ChargeRegularizationShareState
    >((ref) => ChargeRegularizationShareController(ref));
