import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/money_format.dart';
import '../../../expenses/application/expenses_provider.dart';
import '../../../expenses/domain/expense.dart';
import '../../../payments/application/lease_payments_provider.dart';
import '../../application/charge_statement_finalize_controller.dart';
import '../../application/recoverable_expenses_calculator.dart';
import '../../domain/charge_regularization_share_error_reason.dart';
import '../../domain/charge_regularization_share_state.dart';
import 'charge_regularization_form.dart';
import 'charge_regularization_share_error_reason_l10n.dart';

/// Dialog de régularisation annuelle des charges (FEAT-029 V1.2).
///
/// Ouvert depuis [LeaseDetailPage] via l'action dédiée, uniquement pour les
/// baux en mode provisions (`canRegularizeCharges` — gate appliqué par
/// l'appelant, ce dialog ne revérifie pas le mode de charges, FEAT-042).
///
/// Flux :
/// 1. Période de référence pré-remplie sur les 12 derniers mois glissants
///    (aujourd'hui − 1 an + 1 jour → aujourd'hui), modifiable.
/// 2. Provisions encaissées calculées automatiquement (lecture seule) dès
///    que les paiements du bail sont chargés — [sumChargeProvisionsForPeriod].
/// 3. Dépenses réelles **pré-remplies** (FEAT-041c) depuis la somme des
///    dépenses récupérables du bien/bail sur la période —
///    [filterRecoverableExpensesForPeriod] (dépenses sans bail incluses,
///    dépenses d'un AUTRE bail exclues — correctif review finding 2) — mais
///    restent **modifiables** : dès que le bailleur édite le champ à la
///    main, le pré-remplissage automatique ne l'écrase plus (garde
///    [_userEditedExpenses]).
/// 4. Solde recalculé en direct à chaque changement — voir
///    [ChargeRegularizationForm].
/// 5. Bouton "Finaliser & figer le décompte" → confirmation puis
///    [ChargeStatementFinalizeController.finalizeAndShare] (FEAT-033) :
///    persiste un [ChargeStatement] immuable côté serveur (snapshot légal,
///    art. 23 loi du 6 juillet 1989), régénère le PDF depuis CE snapshot puis
///    partage. Remplace l'ancien flux volatile (V1.2, FEAT-029) — voir doc de
///    fichier du controller.
class ChargeRegularizationDialog extends ConsumerStatefulWidget {
  const ChargeRegularizationDialog({
    super.key,
    required this.leaseId,
    required this.propertyId,
    required this.landlordFullName,
    required this.landlordAddress,
    required this.tenantFullName,
    required this.tenantFirstName,
    required this.propertyAddress,
    this.tenantEmail,
  });

  final String leaseId;

  /// Bien rattaché au bail — nécessaire pour charger les dépenses
  /// récupérables du bien (FEAT-041c, [recoverableExpensesProvider]).
  final String propertyId;
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

  /// Vrai dès que le bailleur a modifié manuellement le champ "Dépenses
  /// réelles" — à partir de là, le pré-remplissage automatique
  /// (FEAT-041c, [filterRecoverableExpensesForPeriod]) ne doit **plus** écraser
  /// sa saisie, y compris si la période de référence change ensuite ou si le
  /// stream de dépenses recharge une valeur différente. Reste `false` tant
  /// que l'utilisateur n'a fait qu'observer le pré-remplissage automatique —
  /// **non-régression V1** : avec 0 dépense récupérable, la somme
  /// pré-remplie vaut 0, exactement le comportement par défaut d'avant
  /// FEAT-041c (`_actualExpensesCents` initialisé à 0 ci-dessus).
  bool _userEditedExpenses = false;

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

  /// Applique le pré-remplissage des "Dépenses réelles" calculé depuis les
  /// dépenses récupérables (FEAT-041c) — appelé à chaque `build()` tant que
  /// l'utilisateur n'a pas repris la main manuellement
  /// ([_userEditedExpenses]). Se réévalue aussi quand la période de
  /// référence change (le montant pré-rempli doit suivre la période tant que
  /// l'utilisateur ne l'a pas ajustée à la main).
  ///
  /// N'appelle jamais `setState` pendant `build()` — la valeur est appliquée
  /// après la frame courante (`addPostFrameCallback`), pattern déjà utilisé
  /// ailleurs dans ce fichier (raccourci `?action=regularize` de
  /// `LeaseDetailPage`).
  void _applyPrefill(int prefilledCents) {
    if (_userEditedExpenses) return;
    if (_actualExpensesCents == prefilledCents) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userEditedExpenses) return;
      setState(() {
        _actualExpensesCents = prefilledCents;
        _actualExpensesController.text = MoneyFormat.centsToInput(
          prefilledCents,
        );
      });
    });
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
    final asyncRecoverableExpenses = ref.watch(
      recoverableExpensesProvider((
        propertyId: widget.propertyId,
        leaseId: widget.leaseId,
      )),
    );

    ref.listen<ChargeRegularizationShareState>(
      chargeStatementFinalizeControllerProvider,
      (_, next) => _handleStateChange(context, ref, next),
    );

    // FEAT-041c : dès que les dépenses récupérables sont chargées, applique
    // (ou réapplique si la période a changé) le pré-remplissage — sans effet
    // si l'utilisateur a déjà édité le champ ([_applyPrefill] court-circuite
    // via [_userEditedExpenses]). En l'absence de dépense (liste vide ou
    // encore en chargement), la somme vaut 0 → comportement V1 strictement
    // préservé (non-régression).
    //
    // Correctif review FEAT-041 (findings 1 & 7, MAJOR) : la liste passée au
    // form (compteur « N dépenses » + détail dépliable) est désormais filtrée
    // par [filterRecoverableExpensesForPeriod] — EXACTEMENT le même
    // recouvrement de période (et la même sémantique de rattachement bail,
    // finding 2) que la somme pré-remplie. Avant ce correctif, la liste
    // complète (non filtrée par période) était passée telle quelle, ce qui
    // faisait diverger le compteur/détail affiché du total réellement
    // sommé.
    final recoverableExpenses =
        asyncRecoverableExpenses.valueOrNull ?? const [];
    final expensesForPeriod = filterRecoverableExpensesForPeriod(
      expenses: recoverableExpenses,
      referenceStart: _periodStart,
      referenceEnd: _periodEnd,
      leaseId: widget.leaseId,
    );
    final prefilledExpensesCents = expensesForPeriod.fold<int>(
      0,
      (sum, e) => sum + e.amountCents,
    );
    _applyPrefill(prefilledExpensesCents);

    final shareState = ref.watch(chargeStatementFinalizeControllerProvider);
    final isPreparing = shareState is ChargeRegularizationSharePreparing;
    // Correctif review FEAT-029 (points 1 et 2) : le bouton "Finaliser &
    // figer" doit rester désactivé tant que (a) les paiements ne sont pas
    // chargés — finaliser avant `asyncPayments.hasValue` afficherait un solde
    // encore à 0 le temps de l'appel serveur — ou (b) la période de référence
    // est invalide (fin <= début), ce qui rendrait le décompte légal
    // incohérent.
    final canGenerate =
        !isPreparing && asyncPayments.hasValue && !_isPeriodInvalid;

    return AlertDialog(
      title: Text(context.l10n.chargeRegularizationDialogTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: asyncPayments.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(
              context.l10n.chargeRegularizationPaymentsLoadError,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            data: (payments) => ChargeRegularizationForm(
              periodStart: _periodStart,
              periodEnd: _periodEnd,
              payments: payments,
              actualExpensesController: _actualExpensesController,
              actualExpensesCents: _actualExpensesCents,
              recoverableExpenses: expensesForPeriod,
              onPeriodStartChanged: (d) => setState(() => _periodStart = d),
              onPeriodEndChanged: (d) => setState(() => _periodEnd = d),
              onActualExpensesChanged: (cents) => setState(() {
                _userEditedExpenses = true;
                _actualExpensesCents = cents;
              }),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('btn_charge_regularization_cancel'),
          onPressed: isPreparing ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton.icon(
          key: const Key('btn_charge_regularization_generate'),
          onPressed: canGenerate ? () => _submit(expensesForPeriod) : null,
          icon: isPreparing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text(context.l10n.chargeStatementFinalizeAction),
        ),
      ],
    );
  }

  /// Demande confirmation (le décompte figé devient immuable — voir
  /// `chargeStatementFinalizeConfirmBody`) puis appelle
  /// [ChargeStatementFinalizeController.finalizeAndShare].
  ///
  /// [expensesForPeriod] est la liste **déjà filtrée** par
  /// [filterRecoverableExpensesForPeriod] (même liste que celle affichée dans
  /// [ChargeRegularizationForm], cf. `build()`) — sert à décider la source du
  /// montant des dépenses réelles :
  /// - si `_actualExpensesCents` == la somme de [expensesForPeriod] (le
  ///   bailleur n'a pas modifié le pré-remplissage, ou a saisi exactement la
  ///   même valeur), `actualExpensesSource` = `'expenses'` et les
  ///   `lineItems` détaillent chaque dépense (le serveur revérifie que leur
  ///   somme == `actualExpensesCents`) ;
  /// - sinon (saisie manuelle divergente), `actualExpensesSource` =
  ///   `'manual'` et `lineItems` = `[]` — seul choix cohérent : un `'expenses'`
  ///   dont la somme des `lineItems` ne colle pas au total serait rejeté par
  ///   le serveur (Task 6/7).
  Future<void> _submit(List<Expense> expensesForPeriod) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.chargeStatementFinalizeConfirmTitle),
        content: Text(context.l10n.chargeStatementFinalizeConfirmBody),
        actions: [
          TextButton(
            key: const Key('btn_charge_statement_finalize_confirm_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('btn_charge_statement_finalize_confirm_ok'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.chargeStatementFinalizeAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final prefilledExpensesCents = expensesForPeriod.fold<int>(
      0,
      (sum, e) => sum + e.amountCents,
    );
    final isFromExpenses = _actualExpensesCents == prefilledExpensesCents;
    final lineItems = isFromExpenses
        ? expensesForPeriod
              .map(
                (e) => <String, dynamic>{
                  'expenseId': e.id,
                  'nature': e.nature.sqlValue,
                  'notes': e.notes ?? '',
                  'amountCents': e.amountCents,
                  'expenseDate': e.expenseDate.toUtc().toIso8601String(),
                },
              )
              .toList()
        : <Map<String, dynamic>>[];

    ref
        .read(chargeStatementFinalizeControllerProvider.notifier)
        .finalizeAndShare(
          leaseId: widget.leaseId,
          periodStart: _periodStart,
          periodEnd: _periodEnd,
          actualExpensesCents: _actualExpensesCents,
          actualExpensesSource: isFromExpenses ? 'expenses' : 'manual',
          lineItems: lineItems,
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
      chargeStatementFinalizeControllerProvider.notifier,
    );
    switch (state) {
      case ChargeRegularizationShareShared(:final usedNativeShare):
        if (context.mounted) Navigator.of(context).pop();
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
