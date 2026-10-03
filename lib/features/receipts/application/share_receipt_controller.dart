import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/receipts_repository.dart';
import '../data/share_payload_builder.dart';
import '../data/web_share_service_bridge.dart';
import '../domain/receipt.dart';
import '../domain/receipt_action_error.dart';
import '../domain/share_receipt_state.dart';
import 'lease_receipts_provider.dart';

final _log = Logger('ShareReceiptController');

/// Contrôle le flow de partage d'une quittance via Web Share API ou
/// fallback download + mailto:.
///
/// Transitions d'état :
/// - idle → tenantNoEmail (email vide)
/// - idle → confirmingResend (déjà partagée)
/// - idle → preparing → shared(usedNativeShare=true) (Web Share API)
/// - idle → preparing → shared(usedNativeShare=false) (fallback)
/// - idle → preparing → idle (annulation utilisateur, AbortError)
/// - idle → preparing → error (erreur réseau ou autre)
///
/// Le marquage `sent_at` est effectué APRÈS que le partage a réussi
/// (sur promise resolved), jamais avant.
///
/// Sur succès : invalide [leaseReceiptsProvider(leaseId)] pour rafraîchir
/// la liste.
class ShareReceiptController extends StateNotifier<ShareReceiptState> {
  ShareReceiptController(this._ref) : super(const ShareReceiptState.idle());

  final Ref _ref;

  /// Initie le partage de la quittance.
  ///
  /// Si [tenantEmail] est vide → état [tenantNoEmail], return immédiat.
  /// Si [receipt.hasBeenShared] → état [confirmingResend], attend confirmation.
  /// Sinon → déclenche directement [_doShare].
  Future<void> initiate({
    required Receipt receipt,
    required String leaseId,
    required String tenantEmail,
    required String tenantFirstName,
    required String propertyAddress,
    required String landlordFullName,
  }) async {
    if (tenantEmail.isEmpty) {
      _log.info('partage impossible : locataire sans email');
      state = const ShareReceiptState.tenantNoEmail();
      return;
    }

    if (receipt.hasBeenShared) {
      _log.info('receipt ${receipt.id} déjà partagé — demande confirmation');
      state = ShareReceiptState.confirmingResend(
        previousSharedAt: receipt.sentAt!,
        previousMaskedEmail: receipt.maskedSentToEmail ?? '***',
      );
      return;
    }

    await _doShare(
      receipt: receipt,
      leaseId: leaseId,
      tenantEmail: tenantEmail,
      tenantFirstName: tenantFirstName,
      propertyAddress: propertyAddress,
      landlordFullName: landlordFullName,
    );
  }

  /// Confirme le repartage après dialog de confirmation.
  ///
  /// Appelé lorsque l'utilisateur accepte dans [ConfirmResendDialog].
  Future<void> confirmResend({
    required Receipt receipt,
    required String leaseId,
    required String tenantEmail,
    required String tenantFirstName,
    required String propertyAddress,
    required String landlordFullName,
  }) async {
    await _doShare(
      receipt: receipt,
      leaseId: leaseId,
      tenantEmail: tenantEmail,
      tenantFirstName: tenantFirstName,
      propertyAddress: propertyAddress,
      landlordFullName: landlordFullName,
    );
  }

  /// Remet le controller à l'état idle.
  void reset() => state = const ShareReceiptState.idle();

  // ---------------------------------------------------------------------------
  // Implémentation interne
  // ---------------------------------------------------------------------------

  Future<void> _doShare({
    required Receipt receipt,
    required String leaseId,
    required String tenantEmail,
    required String tenantFirstName,
    required String propertyAddress,
    required String landlordFullName,
  }) async {
    state = const ShareReceiptState.preparing();

    try {
      final repo = _ref.read(receiptsRepositoryProvider);
      final webShare = _ref.read(webShareServiceProvider);

      // Construction du payload (sujet, corps, nom de fichier).
      final payload = SharePayloadBuilder.build(
        receipt: receipt,
        tenantFirstName: tenantFirstName,
        propertyAddress: propertyAddress,
        landlordFullName: landlordFullName,
      );

      bool usedNativeShare;

      if (webShare.canShareFiles()) {
        // --- Branche Web Share API ---
        // Récupère les bytes du PDF depuis l'URL signée.
        final signedUrl = await repo.signedUrl(receipt.id);
        final pdfBytes = await webShare.fetchBytes(signedUrl);

        // Partage via Web Share API. Lance ShareAbortedException si annulé.
        await webShare.sharePdf(
          title: payload.subject,
          text: payload.body,
          pdfBytes: pdfBytes,
          filename: payload.filename,
        );

        // Copie l'adresse du locataire dans le presse-papier (best-effort).
        await webShare.copyToClipboard(tenantEmail);

        usedNativeShare = true;
      } else {
        // --- Branche fallback download + mailto: ---
        // 1. Téléchargement du PDF (ouvre dans un nouvel onglet / déclenche DL).
        final signedUrl = await repo.signedUrl(receipt.id);
        final downloadUri = Uri.parse(signedUrl);
        await launchUrl(downloadUri, mode: LaunchMode.externalApplication);

        // 2. Ouvre un mailto: pré-rempli (sans pièce jointe — limitation Web).
        final mailtoUri = Uri(
          scheme: 'mailto',
          path: tenantEmail,
          queryParameters: {'subject': payload.subject, 'body': payload.body},
        );
        await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);

        usedNativeShare = false;
      }

      // --- Marquage APRÈS que le partage a réussi ---
      final updated = await repo.markReceiptAsShared(
        receiptId: receipt.id,
        tenantEmail: tenantEmail,
      );

      // Invalide le cache pour rafraîchir la liste.
      _ref.invalidate(leaseReceiptsProvider(leaseId));

      _log.info(
        'receipt ${receipt.id} partagé '
        '(native=$usedNativeShare)',
      );

      state = ShareReceiptState.shared(
        sharedAt: updated.sentAt ?? DateTime.now(),
        sharedToEmail: updated.sentToEmail ?? tenantEmail,
        usedNativeShare: usedNativeShare,
      );
    } on ShareAbortedException {
      // L'utilisateur a annulé le dialog natif → retour silencieux à idle.
      _log.info('partage annulé par l\'utilisateur (AbortError)');
      state = const ShareReceiptState.idle();
    } on ShareReceiptException catch (e, st) {
      _log.warning('ShareReceiptException lors du partage', e, st);
      // FEAT-043 : le message technique de [e] (parfois un DOMException brut,
      // non traduit / non FR) n'est plus affiché tel quel — seul le code
      // stable [ReceiptActionError.shareFailed] est stocké ; le détail reste
      // consultable dans les logs ci-dessus.
      state = ShareReceiptState.error(
        message: ReceiptActionError.shareFailed.name,
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue lors du partage', e, st);
      state = ShareReceiptState.error(message: ReceiptActionError.unknown.name);
    }
  }
}

/// Provider autoDispose du contrôleur de partage de quittance, **keyé par
/// `receiptId`**.
///
/// [autoDispose] garantit un state propre entre deux utilisations du bouton.
/// La clé `family` isole l'état par quittance : sans elle, un provider global
/// unique était partagé par tous les `ShareReceiptButton` de la liste (un par
/// quittance), si bien qu'un partage allumait le spinner sur TOUS les boutons
/// et déclenchait le feedback du `ref.listen` sur chaque bouton monté.
final shareReceiptControllerProvider = StateNotifierProvider.autoDispose
    .family<ShareReceiptController, ShareReceiptState, String>(
      (ref, _) => ShareReceiptController(ref),
    );
