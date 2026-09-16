// Page liste des états des lieux d'un bail (FEAT-037, tâche 7).
//
// Patron `LeaseReceiptsPage` (`lib/features/receipts/presentation/`) : même
// AppAppBar avec `fallbackRoute`, mêmes états loading/error/empty/data. Le
// bouton PDF par ligne réutilise le renderer injectable
// (`etatDesLieuxPdfRendererProvider`) et le `WebShareService` posés par le
// formulaire (`etat_des_lieux_form_page.dart`, tâche 6) — même flow
// blob:/data: qu'`_openGeneratedPdf`.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/ui/cards/card_empty_state.dart';
import '../../../core/utils/french_date.dart';
import '../../receipts/data/web_share_service_bridge.dart';
import '../data/etat_des_lieux_repository.dart';
import '../domain/edl_enums.dart';
import '../domain/etat_des_lieux.dart';
import 'etat_des_lieux_form_page.dart' show etatDesLieuxPdfRendererProvider;

final _log = Logger('EtatDesLieuxListPage');

/// Liste des états des lieux d'un bail — patron `leaseReceiptsProvider`.
final etatDesLieuxListProvider =
    FutureProvider.family<List<EtatDesLieux>, String>((ref, leaseId) {
      return ref.watch(etatDesLieuxRepositoryProvider).listForLease(leaseId);
    });

/// Page `/leases/:id/etat-des-lieux` — liste des états des lieux d'un bail.
class EtatDesLieuxListPage extends ConsumerWidget {
  const EtatDesLieuxListPage({super.key, required this.leaseId});

  final String leaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final asyncEdl = ref.watch(etatDesLieuxListProvider(leaseId));

    return Scaffold(
      appBar: AppAppBar(
        title: l10n.edlListTitle,
        fallbackRoute: '/leases/$leaseId',
      ),
      body: asyncEdl.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          _log.warning('Erreur chargement états des lieux', e);
          return _ErrorView(
            onRetry: () => ref.invalidate(etatDesLieuxListProvider(leaseId)),
          );
        },
        data: (items) {
          if (items.isEmpty) {
            return CardEmptyState(
              icon: Icons.fact_check_outlined,
              title: l10n.edlListEmptyTitle,
              message: l10n.edlListEmptyMessage,
              action: FilledButton.icon(
                key: const Key('btn_new_edl_empty'),
                onPressed: () =>
                    context.push('/leases/$leaseId/etat-des-lieux/new'),
                icon: const Icon(Icons.add),
                label: Text(l10n.edlNewButton),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: const Key('btn_new_edl'),
                    onPressed: () =>
                        context.push('/leases/$leaseId/etat-des-lieux/new'),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.edlNewButton),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _EdlTile(edl: items[index]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ligne (type + date + bouton PDF)
// ---------------------------------------------------------------------------

class _EdlTile extends ConsumerWidget {
  const _EdlTile({required this.edl});

  final EtatDesLieux edl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final typeLabel = edl.type == EtatDesLieuxType.entree
        ? l10n.edlTypeEntree
        : l10n.edlTypeSortie;

    return Card(
      key: Key('edl_tile_${edl.id}'),
      child: ListTile(
        leading: Icon(
          edl.type == EtatDesLieuxType.entree
              ? Icons.login_outlined
              : Icons.logout_outlined,
        ),
        title: Text(typeLabel),
        subtitle: Text(FrenchDate.format(edl.date)),
        trailing: OutlinedButton.icon(
          key: Key('edl_pdf_button_${edl.id}'),
          onPressed: () => _openPdf(context, ref),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text(l10n.edlPdfButton),
        ),
      ),
    );
  }

  /// Rend puis ouvre le PDF de l'état des lieux (patron
  /// `EtatDesLieuxFormPage._openGeneratedPdf`) : `blob:` sur web via
  /// [WebShareService], repli sur une URL `data:` ailleurs.
  Future<void> _openPdf(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(etatDesLieuxPdfRendererProvider)(edl);

      final opened = await ref
          .read(webShareServiceProvider)
          .openPdfBytes(
            pdfBytes: bytes,
            filename: 'etat-des-lieux-${edl.id}.pdf',
          );
      if (opened) return;

      final uri = Uri.parse(
        'data:application/pdf;base64,${base64Encode(bytes)}',
      );
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.edlErrorOpenPdf)));
      }
    } catch (e, st) {
      _log.warning('Erreur ouverture PDF état des lieux (liste)', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.edlErrorOpenPdf),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Error view (patron `LeaseReceiptsPage._ErrorView`)
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              l10n.edlListErrorTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
