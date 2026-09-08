import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/breakpoints.dart';
import '../../application/share_receipt_controller.dart';
import '../../application/void_receipt_controller.dart';
import '../open_receipt_pdf.dart';
import '../../domain/receipt.dart';
import '../../domain/receipt_action_error.dart';
import 'receipt_action_error_l10n.dart';
import 'share_receipt_button.dart';
import 'void_receipt_dialog.dart';

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
    final l10n = context.l10n;
    final voidState = ref.watch(voidReceiptControllerProvider(receipt.id));
    final isVoiding = voidState is VoidReceiptSubmitting;

    _listenVoidState(context, ref, theme);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key('btn_pdf_${receipt.id}'),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          tooltip: l10n.receiptsOpenPdfLabel,
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
            tooltip: l10n.receiptsVoidTooltip,
            color: theme.colorScheme.error,
            onPressed: isVoiding ? null : () => _showVoidDialog(context, ref),
          ),
      ],
    );
  }

  void _listenVoidState(BuildContext context, WidgetRef ref, ThemeData theme) {
    ref.listen<VoidReceiptState>(voidReceiptControllerProvider(receipt.id), (
      _,
      next,
    ) {
      if (!context.mounted) return;
      if (next is VoidReceiptSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.receiptsVoidSuccessSnackbar),
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider(receipt.id).notifier).reset();
      } else if (next is VoidReceiptError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ReceiptActionError.fromCode(next.message).message(context),
            ),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider(receipt.id).notifier).reset();
      }
    });
  }

  Future<void> _openPdf(BuildContext context, WidgetRef ref) =>
      openReceiptPdf(context, ref, receipt.id);

  Future<void> _showVoidDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Consumer(
        builder: (context, ref, _) {
          final isVoiding =
              ref.watch(voidReceiptControllerProvider(receipt.id))
                  is VoidReceiptSubmitting;
          return VoidReceiptDialog(
            isSubmitting: isVoiding,
            onConfirm: (reason) {
              Navigator.of(dialogCtx).pop();
              ref
                  .read(voidReceiptControllerProvider(receipt.id).notifier)
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
    final l10n = context.l10n;

    ref.listen<VoidReceiptState>(voidReceiptControllerProvider(receipt.id), (
      _,
      next,
    ) {
      if (!context.mounted) return;
      if (next is VoidReceiptSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.receiptsVoidSuccessSnackbar),
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider(receipt.id).notifier).reset();
      } else if (next is VoidReceiptError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ReceiptActionError.fromCode(next.message).message(context),
            ),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider(receipt.id).notifier).reset();
      }
    });

    return PopupMenuButton<_ReceiptActionKind>(
      key: Key('popup_menu_${receipt.id}'),
      icon: const Icon(Icons.more_vert),
      tooltip: l10n.receiptsActionsMenuTooltip,
      onSelected: (action) => _onAction(context, ref, action, theme),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _ReceiptActionKind.openPdf,
          child: ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(l10n.receiptsOpenPdfMenuItem),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (canShare)
          PopupMenuItem(
            value: _ReceiptActionKind.share,
            child: ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(l10n.receiptsShareMenuItem),
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
                l10n.receiptsVoidMenuItem,
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
            .read(shareReceiptControllerProvider(receipt.id).notifier)
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

  Future<void> _openPdf(BuildContext context, WidgetRef ref, ThemeData theme) =>
      openReceiptPdf(context, ref, receipt.id);

  Future<void> _showVoidDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Consumer(
        builder: (context, ref, _) {
          final isVoiding =
              ref.watch(voidReceiptControllerProvider(receipt.id))
                  is VoidReceiptSubmitting;
          return VoidReceiptDialog(
            isSubmitting: isVoiding,
            onConfirm: (reason) {
              Navigator.of(dialogCtx).pop();
              ref
                  .read(voidReceiptControllerProvider(receipt.id).notifier)
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
