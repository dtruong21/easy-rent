import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../application/charge_statement_finalize_controller.dart';
import '../../data/charge_statement_repository.dart';
import '../../domain/charge_regularization_share_error_reason.dart';
import '../../domain/charge_regularization_share_state.dart';
import '../../domain/charge_statement.dart';
import 'charge_regularization_share_error_reason_l10n.dart';

final _log = Logger('ChargeStatementHistorySection');

/// Section "Décomptes figés" de [LeaseDetailPage] (FEAT-033 Task 9).
///
/// Liste les décomptes de régularisation de charges finalisés (snapshots
/// immuables, art. 23 loi du 6 juillet 1989) pour un bail donné, avec
/// actions de re-partage et d'annulation.
///
/// Volontairement **pas gatée** par les mêmes conditions que
/// [ChargeRegularizationSection] (mode de charges légal, palier PRO) : un
/// décompte déjà figé reste consultable même si le bail passe ensuite au
/// forfait, ou si le palier de l'abonnement change — c'est une preuve légale
/// passée, pas une action produit en cours. La section ne s'affiche que s'il
/// existe au moins un décompte (ou pendant le chargement, pour éviter un
/// flash "rien à voir" qui disparaîtrait aussitôt après).
class ChargeStatementHistorySection extends ConsumerWidget {
  const ChargeStatementHistorySection({super.key, required this.leaseId});

  final String leaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final asyncStatements = ref.watch(
      chargeStatementsForLeaseProvider(leaseId),
    );

    // Re-partage : écoute l'état du contrôleur partagé avec le dialog de
    // finalisation (même provider) pour afficher succès/erreur en snackbar.
    ref.listen<ChargeRegularizationShareState>(
      chargeStatementFinalizeControllerProvider,
      (_, next) => _handleShareStateChange(context, ref, next),
    );

    // N'affiche la section que s'il existe (ou pourrait exister, le temps du
    // chargement) au moins un décompte — pas de gate PRO/légal ici, cf.
    // doc de classe.
    final hasContent = switch (asyncStatements) {
      AsyncData(:final value) => value.isNotEmpty,
      AsyncLoading() => true,
      _ => true,
    };
    if (!hasContent) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.chargeStatementHistoryTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            asyncStatements.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) {
                _log.warning('Erreur chargement décomptes figés', e);
                return Text(
                  l10n.commonErrorGeneric,
                  style: TextStyle(color: theme.colorScheme.error),
                );
              },
              data: (statements) {
                if (statements.isEmpty) {
                  return Text(
                    l10n.chargeStatementHistoryEmpty,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final statement in statements)
                      _ChargeStatementTile(
                        leaseId: leaseId,
                        statement: statement,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleShareStateChange(
    BuildContext context,
    WidgetRef ref,
    ChargeRegularizationShareState state,
  ) {
    final theme = Theme.of(context);
    final notifier = ref.read(
      chargeStatementFinalizeControllerProvider.notifier,
    );
    switch (state) {
      case ChargeRegularizationShareShared(:final usedNativeShare):
        final message = usedNativeShare
            ? context.l10n.chargeRegularizationShareSuccessNative
            : context.l10n.chargeRegularizationShareSuccessFallback;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
          );
        }
        notifier.reset();
      case ChargeRegularizationShareError():
        if (context.mounted) {
          final reason = ChargeRegularizationShareErrorReason.fromCode(
            state.message,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(reason.message(context)),
              backgroundColor: theme.colorScheme.errorContainer,
            ),
          );
        }
        notifier.reset();
      case ChargeRegularizationShareIdle():
      case ChargeRegularizationSharePreparing():
        break;
    }
  }
}

/// Tuile d'un décompte figé — période, solde, badges, actions.
class _ChargeStatementTile extends ConsumerWidget {
  const _ChargeStatementTile({required this.leaseId, required this.statement});

  final String leaseId;
  final ChargeStatement statement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spacing =
        Theme.of(context).extension<AppSpacing>() ?? const AppSpacing();
    final l10n = context.l10n;
    final s = statement;

    final periodLabel =
        '${FrenchDate.format(s.periodStart)} – ${FrenchDate.format(s.periodEnd)}';
    final balanceLabel =
        '${MoneyFormat.formatEurosFromCents(s.balanceAbsCents)} · ${s.labelFr}';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.sm),
      child: Column(
        key: Key('tile_charge_statement_${s.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(periodLabel, style: theme.textTheme.bodyMedium),
              ),
              if (s.isSent)
                Padding(
                  padding: EdgeInsets.only(left: spacing.xs),
                  child: StatusPill(
                    label: l10n.chargeStatementBadgeSent,
                    tone: StatusPillTone.info,
                    icon: Icons.task_alt_outlined,
                  ),
                ),
              if (s.isVoided)
                Padding(
                  padding: EdgeInsets.only(left: spacing.xs),
                  child: StatusPill(
                    label: l10n.chargeStatementBadgeVoided,
                    tone: StatusPillTone.neutral,
                    icon: Icons.cancel_outlined,
                  ),
                ),
            ],
          ),
          SizedBox(height: spacing.xs),
          Text(
            balanceLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: spacing.sm),
          Wrap(
            spacing: spacing.sm,
            children: [
              OutlinedButton.icon(
                key: Key('btn_charge_statement_reshare_${s.id}'),
                icon: const Icon(Icons.ios_share_outlined, size: 16),
                label: Text(l10n.chargeStatementActionReshare),
                onPressed: () => ref
                    .read(chargeStatementFinalizeControllerProvider.notifier)
                    .shareExisting(s),
              ),
              if (!s.isVoided)
                OutlinedButton.icon(
                  key: Key('btn_charge_statement_void_${s.id}'),
                  icon: Icon(
                    Icons.block_outlined,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                  label: Text(l10n.chargeStatementActionVoid),
                  onPressed: () => _confirmVoid(context, ref),
                ),
            ],
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirmVoid(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _VoidStatementDialog(),
    );
    if (reason == null || !context.mounted) return;

    try {
      await ref
          .read(chargeStatementRepositoryProvider)
          .voidStatement(statement.id, reason);
      ref.invalidate(chargeStatementsForLeaseProvider(leaseId));
    } catch (e) {
      _log.warning('Erreur annulation décompte ${statement.id}', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.commonErrorGeneric)),
        );
      }
    }
  }
}

/// Dialog de saisie du motif d'annulation — retourne le motif (non vide,
/// espaces exclus) via [Navigator.pop], ou `null` si annulé.
class _VoidStatementDialog extends StatefulWidget {
  @override
  State<_VoidStatementDialog> createState() => _VoidStatementDialogState();
}

class _VoidStatementDialogState extends State<_VoidStatementDialog> {
  final _reasonCtrl = TextEditingController();
  bool _canSubmit = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      key: const Key('dialog_void_charge_statement'),
      title: Text(l10n.chargeStatementActionVoid),
      content: TextField(
        key: const Key('field_void_charge_statement_reason'),
        controller: _reasonCtrl,
        maxLines: 3,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.chargeStatementVoidReasonHint,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) =>
            setState(() => _canSubmit = value.trim().isNotEmpty),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('btn_void_charge_statement_confirm'),
          onPressed: _canSubmit
              ? () => Navigator.of(context).pop(_reasonCtrl.text.trim())
              : null,
          child: Text(l10n.chargeStatementActionVoid),
        ),
      ],
    );
  }
}
