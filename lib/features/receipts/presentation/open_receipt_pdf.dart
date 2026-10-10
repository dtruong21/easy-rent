import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../data/receipts_repository.dart';
import '../data/web_share_service_bridge.dart';

final _log = Logger('OpenReceiptPdf');

/// Ouvre la quittance [receiptId] dans la visionneuse PDF de la plateforme.
///
/// **Le bug que ça corrige** (recette staging, 2026-08-11) : le chemin unique
/// passait par une URL `data:application/pdf;base64,…` confiée à `launchUrl`.
/// Les navigateurs **bloquent la navigation de premier niveau vers une URL
/// `data:`** (protection anti-hameçonnage) — l'onglet s'ouvrait et restait
/// BLANC. Une quittance étant un document à valeur légale (loi du 6 juillet
/// 1989), l'utilisateur ne pouvait ni la lire ni la remettre à son locataire.
///
/// Stratégie, dans cet ordre :
/// 1. **Web** — URL `blob:` via [WebShareService.openPdfBytes]. Acceptée en
///    navigation, rendue par la visionneuse intégrée, et sans la limite de
///    taille des URLs `data:` (~2 Mo sur Chrome).
/// 2. **Mobile** — feuille de partage système via [WebShareService.openPdfBytes]
///    (aperçu natif). Le repli `data:` n'ouvre rien sur iOS (recette
///    2026-09-28).
/// 3. **Desktop** — repli sur l'URL `data:`, que `launchUrl` sait ouvrir.
///
/// Extrait en fonction partagée parce que trois écrans ouvrent une quittance
/// (menu d'actions compact, menu étendu, dialogue d'aperçu) et divergeaient
/// déjà.
Future<void> openReceiptPdf(
  BuildContext context,
  WidgetRef ref,
  String receiptId,
) async {
  try {
    final bytes = await ref
        .read(receiptsRepositoryProvider)
        .renderPdfBytes(receiptId);

    final opened = await ref
        .read(webShareServiceProvider)
        .openPdfBytes(pdfBytes: bytes, filename: 'quittance-$receiptId.pdf');
    if (opened) return;

    final uri = Uri.parse('data:application/pdf;base64,${base64Encode(bytes)}');
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.receiptsErrorOpenPdfBrowser)),
      );
    }
  } catch (e, st) {
    _log.warning('Erreur ouverture PDF quittance', e, st);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.receiptsErrorGeneratePdfLink),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    }
  }
}
