import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../payments/application/lease_payments_provider.dart';
import '../../../payments/domain/payment.dart';
import '../../application/charge_provisions_calculator.dart';
import '../../application/charge_regularization_share_controller.dart';
import '../../domain/charge_regularization_balance.dart';
import '../../domain/charge_regularization_share_state.dart';
import 'charge_regularization_form.dart';

/// Dialog de régularisation annuelle des charges (FEAT-029 V1.2).
///
/// Ouvert depuis [LeaseDetailPage] via l'action dédiée, uniquement pour les
/// baux nus (`leaseType == unfurnished` — gate appliqué par l'appelant, ce
/// dialog ne revérifie pas le type de bail).
///
/// Flux :
/// 1. Période de référence pré-remplie sur les 12 derniers mois glissants
///    (aujourd'hui − 1 an + 1 jour → aujourd'hui), modifiable.
/// 2. Provisions encaissées calculées automatiquement (lecture seule) dès
///    que les paiements du bail sont chargés — [sumChargeProvisionsForPeriod].
/// 3. Dépenses réelles saisies manuellement par le bailleur.
/// 4. Solde recalculé en direct à chaque changement — voir
///    [ChargeRegularizationForm].
/// 5. Bouton "Générer et partager" → PDF + Web Share (pas de persistance
///    Firestore en V1, cf. doc de fichier du controller).
class ChargeRegularizationDialog extends ConsumerStatefulWidget {
  const ChargeRegularizationDialog({
    super.key,
    required this.leaseId,
    required this.landlordFullName,
    required this.landlordAddress,
    required this.tenantFullName,
    required this.tenantFirstName,
    required this.propertyAddress,
    this.tenantEmail,
  });

  final String leaseId;
  final String landlordFullName;
  final String landlordAddress;
  final String tenantFullName;
  final String tenantFirstName;
  final String propertyAddress;
  final String? tenantEmail;

  @override
  ConsumerState<ChargeRegularizationDialog> createState() =>
      _ChargeRegularizationDialogState();
}

class _ChargeRegularizationDialogState
    extends ConsumerState<ChargeRegularizationDialog> {
  late DateTime _periodStart;
  late DateTime _periodEnd;
  final TextEditingController _actualExpensesController =
      TextEditingController();
  int _actualExpensesCents = 0;

  @override
  void initState() {
    super.initState();
    // Période de référence par défaut : les 12 derniers mois glissants.
    // Choix documenté (cahier des charges laissait le choix entre "12
    // derniers mois" et "dernière année civile complète") — le glissant est
    // toujours défini quel que soit le jour d'ouverture du dialog (pas de
    // dépendance à la date d'anniversaire du bail), donc plus simple à
    // pré-remplir sans logique supplémentaire.
    final today = DateTime.now();
    final now = DateTime(today.year, today.month, today.day);
    _periodEnd = now;
    _periodStart = DateTime(now.year - 1, now.month, now.day + 1);
  }

  @override
  void dispose() {
    _actualExpensesController.dispose();
    super.dispose();
  }

  /// Vrai si la période de référence est inversée ou nulle (fin <= début) —
  /// même règle que [ChargeRegularizationForm.isPeriodInvalid], dupliquée
  /// volontairement ici (garde triviale à une ligne) car ce state n'a pas
  /// d'accès direct à une instance du widget de formulaire pour la
  /// réutiliser sans complexifier l'API. Bloque la génération du PDF —
  /// correctif review FEAT-029 : une période inversée produirait un avis
  /// légal incohérent et un calcul de provisions faux.
  bool get _isPeriodInvalid => !_periodEnd.isAfter(_periodStart);

  @override
  Widget build(BuildContext context) {
    final asyncPayments = ref.watch(leasePaymentsProvider(widget.leaseId));

    ref.listen<ChargeRegularizationShareState>(
      chargeRegularizationShareControllerProvider,
      (_, next) => _handleStateChange(context, ref, next),
    );

    final shareState = ref.watch(chargeRegularizationShareControllerProvider);
    final isPreparing = shareState is ChargeRegularizationSharePreparing;
    // Correctif review FEAT-029 (points 1 et 2) : le bouton "Générer et
    // partager" doit rester désactivé tant que (a) les paiements ne sont pas
    // chargés — générer avant `asyncPayments.hasValue` produirait un avis
    // avec provisions=0 — ou (b) la période de référence est invalide
    // (fin <= début), ce qui fausserait le calcul des provisions ET rendrait
    // le document légal incohérent.
    final canGenerate =
        !isPreparing && asyncPayments.hasValue && !_isPeriodInvalid;

    return AlertDialog(
      title: const Text('Régularisation annuelle des charges'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: asyncPayments.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(
              'Erreur lors du chargement des paiements.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            data: (payments) => ChargeRegularizationForm(
              periodStart: _periodStart,
              periodEnd: _periodEnd,
              payments: payments,
              actualExpensesController: _actualExpensesController,
              actualExpensesCents: _actualExpensesCents,
              onPeriodStartChanged: (d) => setState(() => _periodStart = d),
              onPeriodEndChanged: (d) => setState(() => _periodEnd = d),
              onActualExpensesChanged: (cents) =>
                  setState(() => _actualExpensesCents = cents),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('btn_charge_regularization_cancel'),
          onPressed: isPreparing ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          key: const Key('btn_charge_regularization_generate'),
          onPressed: canGenerate
              ? () => _submit(asyncPayments.valueOrNull ?? const <Payment>[])
              : null,
          icon: isPreparing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('Générer et partager'),
        ),
      ],
    );
  }

  void _submit(List<Payment> payments) {
    final provisionsCents = sumChargeProvisionsForPeriod(
      payments: payments,
      referenceStart: _periodStart,
      referenceEnd: _periodEnd,
    );
    final balance = ChargeRegularizationBalance(
      periodStart: _periodStart,
      periodEnd: _periodEnd,
      provisionsCollectedCents: provisionsCents,
      actualExpensesCents: _actualExpensesCents,
    );
    ref
        .read(chargeRegularizationShareControllerProvider.notifier)
        .generateAndShare(
          balance: balance,
          landlordFullName: widget.landlordFullName,
          landlordAddress: widget.landlordAddress,
          tenantFullName: widget.tenantFullName,
          tenantFirstName: widget.tenantFirstName,
          propertyAddress: widget.propertyAddress,
          tenantEmail: widget.tenantEmail,
        );
  }

  void _handleStateChange(
    BuildContext context,
    WidgetRef ref,
    ChargeRegularizationShareState state,
  ) {
    final theme = Theme.of(context);
    final notifier = ref.read(
      chargeRegularizationShareControllerProvider.notifier,
    );
    switch (state) {
      case ChargeRegularizationShareShared(:final usedNativeShare):
        if (context.mounted) Navigator.of(context).pop();
        final message = usedNativeShare
            ? 'Avis de régularisation partagé.'
            : 'PDF téléchargé. Pensez à l\'attacher manuellement à votre email.';
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
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
