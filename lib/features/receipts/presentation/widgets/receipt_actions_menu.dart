import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/ui/breakpoints.dart';
import '../../application/share_receipt_controller.dart';
import '../../application/void_receipt_controller.dart';
import '../../data/receipts_repository.dart';
import '../../domain/receipt.dart';
import 'share_receipt_button.dart';
import 'void_receipt_dialog.dart';

final _log = Logger('ReceiptActionsMenu');

/// Modèle interne d'une action disponible pour une quittance.
enum _ReceiptActionKind { openPdf, share, cancel }

/// Menu d'actions pour une quittance.
///
/// - Mobile / tablette (< 1024px) : [PopupMenuButton] compact ⋮.
/// - Desktop (>= 1024px) : [Row] d'actions inline.
///
/// Actions disponibles :
/// - "Ouvrir PDF" (toujours).
/// - "Partager" (si `!isVoided && !isStale && tenantEmail != null`).
/// - "Annuler" (si `!isVoided`, couleur danger).
class ReceiptActionsMenu extends ConsumerWidget {
  const ReceiptActionsMenu({
    super.key,
    required this.receipt,
    required this.leaseId,
    this.tenantEmail,
    this.tenantFirstName = '',
    this.propertyAddress = '',
    this.landlordFullName = '',
  });

  final Receipt receipt;
  final String leaseId;
  final String? tenantEmail;
  final String tenantFirstName;
  final String propertyAddress;
  final String landlordFullName;

  bool get _canShare =>
      !receipt.isVoided &&
      !receipt.isStale &&
      tenantEmail != null &&
      tenantEmail!.isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context.isDesktop) {
      return _DesktopActionsRow(
        receipt: receipt,
        leaseId: leaseId,
        tenantEmail: tenantEmail,
        tenantFirstName: tenantFirstName,
        propertyAddress: propertyAddress,
        landlordFullName: landlordFullName,
        canShare: _canShare,
      );
    }

    return _MobileActionsMenu(
      receipt: receipt,
      leaseId: leaseId,
      tenantEmail: tenantEmail,
      tenantFirstName: tenantFirstName,
      propertyAddress: propertyAddress,
      landlordFullName: landlordFullName,
      canShare: _canShare,
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop : Row inline
// ---------------------------------------------------------------------------

class _DesktopActionsRow extends ConsumerWidget {
  const _DesktopActionsRow({
    required this.receipt,
    required this.leaseId,
    this.tenantEmail,
    this.tenantFirstName = '',
    this.propertyAddress = '',
    this.landlordFullName = '',
    required this.canShare,
  });

  final Receipt receipt;
  final String leaseId;
  final String? tenantEmail;
  final String tenantFirstName;
  final String propertyAddress;
  final String landlordFullName;
  final bool canShare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final voidState = ref.watch(voidReceiptControllerProvider);
    final isVoiding = voidState is VoidReceiptSubmitting;

    _listenVoidState(context, ref, theme);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key('btn_pdf_${receipt.id}'),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          tooltip: 'Ouvrir le PDF',
          onPressed: () => _openPdf(context, ref),
        ),
        if (canShare)
          ShareReceiptButton(
            receipt: receipt,
            leaseId: leaseId,
            tenantEmail: tenantEmail,
            tenantFirstName: tenantFirstName,
            propertyAddress: propertyAddress,
            landlordFullName: landlordFullName,
          ),
        if (!receipt.isVoided)
          IconButton(
            key: Key('btn_void_${receipt.id}'),
            icon: const Icon(Icons.cancel_outlined),
            tooltip: 'Annuler la quittance',
            color: theme.colorScheme.error,
            onPressed: isVoiding ? null : () => _showVoidDialog(context, ref),
          ),
      ],
    );
  }

  void _listenVoidState(BuildContext context, WidgetRef ref, ThemeData theme) {
    ref.listen<VoidReceiptState>(voidReceiptControllerProvider, (_, next) {
      if (!context.mounted) return;
      if (next is VoidReceiptSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Quittance annulée'),
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider.notifier).reset();
      } else if (next is VoidReceiptError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider.notifier).reset();
      }
    });
  }

  Future<void> _openPdf(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(receiptsRepositoryProvider);
      final url = await repo.signedUrl(receipt.pdfPath);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Impossible d'ouvrir le PDF. Vérifiez votre navigateur.",
              ),
            ),
          );
        }
      }
    } catch (e, st) {
      _log.warning('Erreur téléchargement PDF', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Impossible de générer le lien de téléchargement.',
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
      }
    }
  }

  Future<void> _showVoidDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Consumer(
        builder: (context, ref, _) {
          final isVoiding =
              ref.watch(voidReceiptControllerProvider) is VoidReceiptSubmitting;
          return VoidReceiptDialog(
            isSubmitting: isVoiding,
            onConfirm: (reason) {
              Navigator.of(dialogCtx).pop();
              ref
                  .read(voidReceiptControllerProvider.notifier)
                  .voidReceipt(
                    receiptId: receipt.id,
                    reason: reason,
                    leaseId: leaseId,
                  );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile / tablette : PopupMenuButton
// ---------------------------------------------------------------------------

class _MobileActionsMenu extends ConsumerWidget {
  const _MobileActionsMenu({
    required this.receipt,
    required this.leaseId,
    this.tenantEmail,
    this.tenantFirstName = '',
    this.propertyAddress = '',
    this.landlordFullName = '',
    required this.canShare,
  });

  final Receipt receipt;
  final String leaseId;
  final String? tenantEmail;
  final String tenantFirstName;
  final String propertyAddress;
  final String landlordFullName;
  final bool canShare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    ref.listen<VoidReceiptState>(voidReceiptControllerProvider, (_, next) {
      if (!context.mounted) return;
      if (next is VoidReceiptSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Quittance annulée'),
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider.notifier).reset();
      } else if (next is VoidReceiptError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider.notifier).reset();
      }
    });

    return PopupMenuButton<_ReceiptActionKind>(
      key: Key('popup_menu_${receipt.id}'),
      icon: const Icon(Icons.more_vert),
      tooltip: 'Actions',
      onSelected: (action) => _onAction(context, ref, action, theme),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _ReceiptActionKind.openPdf,
          child: ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text('Ouvrir PDF'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (canShare)
          const PopupMenuItem(
            value: _ReceiptActionKind.share,
            child: ListTile(
              leading: Icon(Icons.share_outlined),
              title: Text('Partager'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (!receipt.isVoided)
          PopupMenuItem(
            value: _ReceiptActionKind.cancel,
            child: ListTile(
              leading: Icon(
                Icons.cancel_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Annuler',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _ReceiptActionKind action,
    ThemeData theme,
  ) async {
    switch (action) {
      case _ReceiptActionKind.openPdf:
        await _openPdf(context, ref, theme);
      case _ReceiptActionKind.share:
        ref
            .read(shareReceiptControllerProvider.notifier)
            .initiate(
              receipt: receipt,
              leaseId: leaseId,
              tenantEmail: tenantEmail!,
              tenantFirstName: tenantFirstName,
              propertyAddress: propertyAddress,
              landlordFullName: landlordFullName,
            );
      case _ReceiptActionKind.cancel:
        await _showVoidDialog(context, ref);
    }
  }

  Future<void> _openPdf(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
  ) async {
    try {
      final repo = ref.read(receiptsRepositoryProvider);
      final url = await repo.signedUrl(receipt.pdfPath);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Impossible d'ouvrir le PDF. Vérifiez votre navigateur.",
              ),
            ),
          );
        }
      }
    } catch (e, st) {
      _log.warning('Erreur téléchargement PDF', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Impossible de générer le lien de téléchargement.',
            ),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
      }
    }
  }

  Future<void> _showVoidDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Consumer(
        builder: (context, ref, _) {
          final isVoiding =
              ref.watch(voidReceiptControllerProvider) is VoidReceiptSubmitting;
          return VoidReceiptDialog(
            isSubmitting: isVoiding,
            onConfirm: (reason) {
              Navigator.of(dialogCtx).pop();
              ref
                  .read(voidReceiptControllerProvider.notifier)
                  .voidReceipt(
                    receiptId: receipt.id,
                    reason: reason,
                    leaseId: leaseId,
                  );
            },
          );
        },
      ),
    );
  }
}
