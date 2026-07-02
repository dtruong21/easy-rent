import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/ui/theme/app_spacing.dart';
import '../../../core/utils/money_format.dart';
import '../../auth/application/anon_expiry_renewer.dart';
import '../../auth/application/auth_session_provider.dart';
import '../../auth/application/login_controller.dart';
import '../../auth/data/landlord_tier_repository.dart';
import '../../auth/domain/session_state.dart';
import '../../auth/domain/subscription_tier.dart';
import '../../auth/presentation/widgets/anon_demo_banner.dart';
import '../../auth/presentation/widgets/quit_demo_dialog.dart';
import '../application/scenario_limit_controller.dart';
import '../data/investment_scenario_repository.dart';
import '../domain/investment_scenario.dart';
import '../domain/scenario_results.dart';
import 'widgets/coming_soon_paid_plan_section.dart';
import 'widgets/save_scenario_dialog.dart';
import 'widgets/saved_scenarios_row.dart';
import 'widgets/scenario_form_validators.dart';
import 'widgets/scenario_limit_reached_modal.dart';
import 'widgets/scenario_results_card.dart';
import 'widgets/tier_chip.dart';

final _log = Logger('SimulatorPage');

/// Page simulateur d'investissement (FEAT-018).
///
/// Route `/simulator` (nouveau scénario) et `/simulator/:id` (édition).
///
/// Structure :
/// - Disclaimer permanent (estimation indicative)
/// - Mes scénarios (liste horizontale si des scénarios existent)
/// - Formulaire 12 champs en 4 sections [ExpansionTile]
/// - Résultats 8 KPI live (debounce 250 ms)
/// - Bouton "Sauvegarder ce scénario"
class SimulatorPage extends ConsumerStatefulWidget {
  const SimulatorPage({super.key, this.scenarioId});

  /// Si non null → mode édition : hydrate le formulaire depuis le scénario.
  final String? scenarioId;

  @override
  ConsumerState<SimulatorPage> createState() => _SimulatorPageState();
}

class _SimulatorPageState extends ConsumerState<SimulatorPage> {
  final _formKey = GlobalKey<FormState>();

  // ── Controllers — Acquisition ────────────────────────────────────────────
  final _purchasePriceCtrl = TextEditingController();
  final _notaryFeesCtrl = TextEditingController();
  final _worksCtrl = TextEditingController();
  bool _isNewProperty = false;

  // ── Pré-remplissage auto des frais de notaire ────────────────────────────
  // prix × 8 % (ancien) / 2 % (neuf). Actif tant que l'utilisateur n'a pas
  // saisi une valeur à la main ; vider le champ le ré-arme, et basculer le
  // toggle « Bien neuf » force un re-calcul (geste explicite de demande du
  // taux standard, même après une saisie manuelle).
  static const double _notaryRateOld = 0.08;
  static const double _notaryRateNew = 0.02;
  bool _notaryAutoFill = true;
  bool _notarySetProgrammatically = false;

  // ── Controllers — Financement ────────────────────────────────────────────
  final _downPaymentCtrl = TextEditingController();
  final _loanPrincipalCtrl = TextEditingController();
  final _loanRateCtrl = TextEditingController();
  final _loanDurationCtrl = TextEditingController();

  // ── Controllers — Revenus ────────────────────────────────────────────────
  final _monthlyRentCtrl = TextEditingController();

  // ── Controllers — Charges ────────────────────────────────────────────────
  final _propertyTaxCtrl = TextEditingController();
  final _insurancePnoCtrl = TextEditingController();
  final _condoFeesCtrl = TextEditingController();

  // ── Notes ────────────────────────────────────────────────────────────────
  final _notesCtrl = TextEditingController();

  // ── État UI ──────────────────────────────────────────────────────────────
  ScenarioResults? _results;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  Timer? _debounce;

  // Scénario chargé en mode édition.
  InvestmentScenario? _loadedScenario;

  @override
  void initState() {
    super.initState();
    // Écoute chaque changement de champ pour recalculer live.
    for (final ctrl in _allControllers) {
      ctrl.addListener(_onFieldChanged);
    }
    _purchasePriceCtrl.addListener(_onPurchasePriceChangedForNotary);
    _notaryFeesCtrl.addListener(_onNotaryFieldChanged);
    if (widget.scenarioId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadScenario());
    }
  }

  List<TextEditingController> get _allControllers => [
    _purchasePriceCtrl,
    _notaryFeesCtrl,
    _worksCtrl,
    _downPaymentCtrl,
    _loanPrincipalCtrl,
    _loanRateCtrl,
    _loanDurationCtrl,
    _monthlyRentCtrl,
    _propertyTaxCtrl,
    _insurancePnoCtrl,
    _condoFeesCtrl,
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _purchasePriceCtrl.removeListener(_onPurchasePriceChangedForNotary);
    _notaryFeesCtrl.removeListener(_onNotaryFieldChanged);
    for (final ctrl in _allControllers) {
      ctrl.removeListener(_onFieldChanged);
      ctrl.dispose();
    }
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Auto-fill frais de notaire ───────────────────────────────────────────

  void _onNotaryFieldChanged() {
    if (_notarySetProgrammatically) return;
    // Saisie manuelle → on fige. Champ vidé → on ré-arme l'auto-fill.
    _notaryAutoFill = _notaryFeesCtrl.text.trim().isEmpty;
  }

  void _onPurchasePriceChangedForNotary() {
    if (_notaryAutoFill) _applyNotaryPrefill();
  }

  void _applyNotaryPrefill() {
    final price = MoneyFormat.eurosToCents(_purchasePriceCtrl.text);
    final String text;
    if (price == null || price <= 0) {
      text = '';
    } else {
      final rate = _isNewProperty ? _notaryRateNew : _notaryRateOld;
      // Arrondi à l'euro : montant indicatif, pas de centimes.
      final cents = ((price * rate) / 100).round() * 100;
      text = MoneyFormat.centsToInput(cents);
    }
    if (_notaryFeesCtrl.text == text) return;
    _notarySetProgrammatically = true;
    _notaryFeesCtrl.text = text;
    _notarySetProgrammatically = false;
  }

  // ── Chargement scénario en mode édition ──────────────────────────────────

  Future<void> _loadScenario() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final scenario = await ref
          .read(investmentScenarioRepositoryProvider)
          .getById(widget.scenarioId!);
      _hydrateForm(scenario);
      setState(() {
        _loadedScenario = scenario;
        _isLoading = false;
      });
      _recompute();
    } catch (e) {
      _log.warning('Erreur chargement scénario ${widget.scenarioId}: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossible de charger le scénario.';
      });
    }
  }

  void _hydrateForm(InvestmentScenario s) {
    _purchasePriceCtrl.text = MoneyFormat.centsToInput(s.purchasePriceCents);
    _notaryFeesCtrl.text = s.notaryFeesCents > 0
        ? MoneyFormat.centsToInput(s.notaryFeesCents)
        : '';
    _worksCtrl.text = s.worksInitialCents > 0
        ? MoneyFormat.centsToInput(s.worksInitialCents)
        : '';
    _isNewProperty = s.isNewProperty;
    _downPaymentCtrl.text = s.downPaymentCents > 0
        ? MoneyFormat.centsToInput(s.downPaymentCents)
        : '';
    _loanPrincipalCtrl.text = s.loanPrincipalCents > 0
        ? MoneyFormat.centsToInput(s.loanPrincipalCents)
        : '';
    _loanRateCtrl.text = s.loanRateBps > 0
        ? (s.loanRateBps / 100.0).toStringAsFixed(2).replaceAll('.', ',')
        : '';
    _loanDurationCtrl.text = s.loanDurationMonths != 240
        ? s.loanDurationMonths.toString()
        : '240';
    _monthlyRentCtrl.text = MoneyFormat.centsToInput(s.monthlyRentHcCents);
    _propertyTaxCtrl.text = s.propertyTaxAnnualCents > 0
        ? MoneyFormat.centsToInput(s.propertyTaxAnnualCents)
        : '';
    _insurancePnoCtrl.text = s.insurancePnoAnnualCents > 0
        ? MoneyFormat.centsToInput(s.insurancePnoAnnualCents)
        : '';
    _condoFeesCtrl.text = s.condoFeesNonRecoverableCents > 0
        ? MoneyFormat.centsToInput(s.condoFeesNonRecoverableCents)
        : '';
    _notesCtrl.text = s.notes ?? '';
  }

  // ── Calcul live debounce 250 ms ──────────────────────────────────────────

  void _onFieldChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _recompute);
  }

  void _recompute() {
    final scenario = _buildScenarioFromForm();
    if (scenario == null) {
      setState(() => _results = null);
      return;
    }
    setState(() => _results = computeScenarioResults(scenario));
  }

  /// Construit un scénario virtuel depuis le formulaire (sans persistance).
  ///
  /// Retourne null si le prix d'achat ou le loyer sont invalides.
  InvestmentScenario? _buildScenarioFromForm() {
    final purchasePrice = MoneyFormat.eurosToCents(_purchasePriceCtrl.text);
    final monthlyRent = MoneyFormat.eurosToCents(_monthlyRentCtrl.text);
    if (purchasePrice == null || purchasePrice <= 0) return null;
    if (monthlyRent == null || monthlyRent <= 0) return null;

    // Taux : saisie en % (ex. "3.5") → bps (350).
    final rateInput = _loanRateCtrl.text.trim().replaceAll(',', '.');
    final rateParsed = double.tryParse(rateInput) ?? 0.0;
    final rateBps = (rateParsed * 100).round().clamp(0, 3000);

    final duration = int.tryParse(_loanDurationCtrl.text.trim()) ?? 240;
    final durationClamped = duration.clamp(12, 360);

    return InvestmentScenario(
      id: _loadedScenario?.id ?? 'preview',
      landlordId: _loadedScenario?.landlordId ?? '',
      name: _loadedScenario?.name ?? 'Aperçu',
      purchasePriceCents: purchasePrice,
      notaryFeesCents: MoneyFormat.eurosToCents(_notaryFeesCtrl.text) ?? 0,
      worksInitialCents: MoneyFormat.eurosToCents(_worksCtrl.text) ?? 0,
      isNewProperty: _isNewProperty,
      downPaymentCents: MoneyFormat.eurosToCents(_downPaymentCtrl.text) ?? 0,
      loanPrincipalCents:
          MoneyFormat.eurosToCents(_loanPrincipalCtrl.text) ?? 0,
      loanRateBps: rateBps,
      loanDurationMonths: durationClamped,
      monthlyRentHcCents: monthlyRent,
      propertyTaxAnnualCents:
          MoneyFormat.eurosToCents(_propertyTaxCtrl.text) ?? 0,
      insurancePnoAnnualCents:
          MoneyFormat.eurosToCents(_insurancePnoCtrl.text) ?? 0,
      condoFeesNonRecoverableCents:
          MoneyFormat.eurosToCents(_condoFeesCtrl.text) ?? 0,
      createdAt: _loadedScenario?.createdAt ?? DateTime.now(),
      updatedAt: _loadedScenario?.updatedAt ?? DateTime.now(),
    );
  }

  // ── Sauvegarde ───────────────────────────────────────────────────────────

  Future<void> _saveScenario() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // L'enforcement de la limite ne s'applique qu'à la CRÉATION (un update
    // ne change pas le nombre total de scénarios sauvegardés). Relecture
    // synchrone au clic (pas seulement `onPressed: disabled`) pour couvrir
    // le cas où le compte a évolué depuis le dernier rebuild.
    final isCreating = _loadedScenario == null;
    if (isCreating && !ref.read(canSaveAnotherScenarioProvider)) {
      final tier =
          ref.read(landlordTierProvider).valueOrNull?.tier ??
          SubscriptionTier.anonymous;
      await showScenarioLimitReachedModal(context, tier: tier);
      return;
    }

    final preview = _buildScenarioFromForm();
    if (preview == null) return;

    final name = await showSaveScenarioDialog(
      context,
      initial: _loadedScenario?.name,
    );
    if (name == null || !mounted) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(investmentScenarioRepositoryProvider);

      if (_loadedScenario != null) {
        // Mode édition : update.
        final updated = _loadedScenario!.copyWith(
          name: name,
          purchasePriceCents: preview.purchasePriceCents,
          notaryFeesCents: preview.notaryFeesCents,
          worksInitialCents: preview.worksInitialCents,
          isNewProperty: preview.isNewProperty,
          downPaymentCents: preview.downPaymentCents,
          loanPrincipalCents: preview.loanPrincipalCents,
          loanRateBps: preview.loanRateBps,
          loanDurationMonths: preview.loanDurationMonths,
          monthlyRentHcCents: preview.monthlyRentHcCents,
          propertyTaxAnnualCents: preview.propertyTaxAnnualCents,
          insurancePnoAnnualCents: preview.insurancePnoAnnualCents,
          condoFeesNonRecoverableCents: preview.condoFeesNonRecoverableCents,
          notes: _notesCtrl.text.trim().isNotEmpty
              ? _notesCtrl.text.trim()
              : null,
        );
        await repo.update(updated);
      } else {
        // Nouveau scénario : create.
        await repo.create(
          name: name,
          purchasePriceCents: preview.purchasePriceCents,
          notaryFeesCents: preview.notaryFeesCents,
          worksInitialCents: preview.worksInitialCents,
          isNewProperty: preview.isNewProperty,
          downPaymentCents: preview.downPaymentCents,
          loanPrincipalCents: preview.loanPrincipalCents,
          loanRateBps: preview.loanRateBps,
          loanDurationMonths: preview.loanDurationMonths,
          monthlyRentHcCents: preview.monthlyRentHcCents,
          propertyTaxAnnualCents: preview.propertyTaxAnnualCents,
          insurancePnoAnnualCents: preview.insurancePnoAnnualCents,
          condoFeesNonRecoverableCents: preview.condoFeesNonRecoverableCents,
          notes: _notesCtrl.text.trim().isNotEmpty
              ? _notesCtrl.text.trim()
              : null,
        );
      }

      // Recharge la liste des scénarios.
      await ref.read(investmentScenariosListProvider.notifier).reload();

      // BAILLAN-M1 : sauvegarder un scénario est un signal d'activité
      // meaningful — renouvelle anonExpiresAt si la session est anonyme
      // (no-op silencieux sinon, throttlé côté renewer).
      unawaited(ref.read(anonExpiryRenewerProvider.notifier).renewIfNeeded());

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Scénario sauvegardé')));
        // Redirige vers /simulator (liste) si on était sur un nouveau scénario.
        if (widget.scenarioId == null) {
          context.go('/simulator');
        }
      }
    } catch (e) {
      _log.warning('Erreur sauvegarde scénario: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erreur lors de la sauvegarde. Veuillez réessayer.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Sortie explicite du mode démo (session anonyme) — remplace le bouton
  /// back masqué pour les anonymes. Confirme d'abord (le scénario démo est
  /// perdu au signOut), et propose la conversion en compte comme alternative.
  Future<void> _onQuitDemoPressed() async {
    final choice = await showQuitDemoDialog(context);
    if (!mounted || choice == null) return;
    switch (choice) {
      case QuitDemoChoice.signup:
        context.go('/signup');
      case QuitDemoChoice.quit:
        await ref.read(loginControllerProvider.notifier).signOut();
        // Retour à la page de garde. La garde router redirige déjà la
        // session devenue unauthenticated hors de /simulator (vers /login) ;
        // on vise la landing explicitement si la page est encore montée.
        if (mounted) context.go('/');
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final spacing =
        Theme.of(context).extension<AppSpacing>() ?? const AppSpacing();
    final sessionState = ref.watch(sessionStateProvider);
    final tier =
        ref.watch(landlordTierProvider).valueOrNull?.tier ??
        SubscriptionTier.anonymous;

    final isAnon = sessionState == SessionState.anonymous;

    return Scaffold(
      appBar: AppAppBar(
        title: "Simulateur d'investissement",
        // Un anonyme n'a nulle part où « revenir » : la garde router
        // réécrit `/` en `/simulator` pour lui (boucle no-op) — le
        // simulateur est sa racine. On masque le back et on lui donne à la
        // place une sortie explicite du mode démo (action ci-dessous).
        showBackButton: !isAnon,
        fallbackRoute: '/',
        actions: [
          if (isAnon)
            IconButton(
              key: const Key('simulator_quit_demo'),
              icon: const Icon(Icons.logout),
              tooltip: 'Quitter le mode démo',
              onPressed: _onQuitDemoPressed,
            ),
        ],
      ),
      body: Column(
        children: [
          const AnonDemoBanner(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: EdgeInsets.all(spacing.lg),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Signalétique tier — persistant en haut de page.
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: TierChip(),
                            ),
                            SizedBox(height: spacing.md),

                            // Disclaimer permanent.
                            _DisclaimerBanner(),
                            SizedBox(height: spacing.lg),

                            // Mes scénarios sauvegardés.
                            const SavedScenariosRow(),

                            // Formulaire.
                            _ScenarioForm(
                              formKey: _formKey,
                              purchasePriceCtrl: _purchasePriceCtrl,
                              notaryFeesCtrl: _notaryFeesCtrl,
                              worksCtrl: _worksCtrl,
                              isNewProperty: _isNewProperty,
                              onIsNewPropertyChanged: (v) {
                                setState(() => _isNewProperty = v);
                                // Toggle = demande explicite du taux standard
                                // → ré-arme l'auto-fill même après une saisie
                                // manuelle.
                                _notaryAutoFill = true;
                                _applyNotaryPrefill();
                                _onFieldChanged();
                              },
                              downPaymentCtrl: _downPaymentCtrl,
                              loanPrincipalCtrl: _loanPrincipalCtrl,
                              loanRateCtrl: _loanRateCtrl,
                              loanDurationCtrl: _loanDurationCtrl,
                              monthlyRentCtrl: _monthlyRentCtrl,
                              propertyTaxCtrl: _propertyTaxCtrl,
                              insurancePnoCtrl: _insurancePnoCtrl,
                              condoFeesCtrl: _condoFeesCtrl,
                              notesCtrl: _notesCtrl,
                            ),
                            SizedBox(height: spacing.lg),

                            // Résultats KPI.
                            if (_results != null)
                              ScenarioResultsCard(results: _results!),
                            if (_results == null) _EmptyResultsHint(),

                            SizedBox(height: spacing.lg),

                            // Message d'erreur.
                            if (_errorMessage != null)
                              Padding(
                                padding: EdgeInsets.only(bottom: spacing.sm),
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),

                            // Bouton sauvegarder.
                            FilledButton.icon(
                              key: const Key('save_scenario_button'),
                              onPressed: _isSaving ? null : _saveScenario,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                widget.scenarioId != null
                                    ? 'Mettre à jour le scénario'
                                    : 'Sauvegarder ce scénario',
                              ),
                            ),
                            SizedBox(height: spacing.xxl),

                            // Pied de page « Prochainement — Plan Pro » :
                            // uniquement pour les comptes FREE (les anons
                            // voient un CTA les invitant à créer un compte
                            // gratuit d'abord — trop tôt pour leur vendre un
                            // futur plan payant).
                            if (tier == SubscriptionTier.free)
                              const ComingSoonPaidPlanSection()
                            else if (sessionState == SessionState.anonymous)
                              _CreateFreeAccountFirstHint(),

                            SizedBox(height: spacing.xxl),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Hint anonyme (remplace la section Plan Pro) ─────────────────────────────

class _CreateFreeAccountFirstHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('create_free_account_first_hint'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        'Créez un compte gratuit d\'abord pour découvrir toutes les '
        'fonctionnalités à venir de Baillan.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Disclaimer banner ────────────────────────────────────────────────────────

class _DisclaimerBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Estimation indicative basée sur les données saisies. '
                'Ne constitue pas un conseil en investissement. '
                'Consultez un professionnel.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty results hint ───────────────────────────────────────────────────────

class _EmptyResultsHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        'Saisissez le prix d\'achat et le loyer mensuel pour voir les résultats.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Formulaire 4 sections ────────────────────────────────────────────────────

class _ScenarioForm extends StatelessWidget {
  const _ScenarioForm({
    required this.formKey,
    required this.purchasePriceCtrl,
    required this.notaryFeesCtrl,
    required this.worksCtrl,
    required this.isNewProperty,
    required this.onIsNewPropertyChanged,
    required this.downPaymentCtrl,
    required this.loanPrincipalCtrl,
    required this.loanRateCtrl,
    required this.loanDurationCtrl,
    required this.monthlyRentCtrl,
    required this.propertyTaxCtrl,
    required this.insurancePnoCtrl,
    required this.condoFeesCtrl,
    required this.notesCtrl,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController purchasePriceCtrl;
  final TextEditingController notaryFeesCtrl;
  final TextEditingController worksCtrl;
  final bool isNewProperty;
  final ValueChanged<bool> onIsNewPropertyChanged;
  final TextEditingController downPaymentCtrl;
  final TextEditingController loanPrincipalCtrl;
  final TextEditingController loanRateCtrl;
  final TextEditingController loanDurationCtrl;
  final TextEditingController monthlyRentCtrl;
  final TextEditingController propertyTaxCtrl;
  final TextEditingController insurancePnoCtrl;
  final TextEditingController condoFeesCtrl;
  final TextEditingController notesCtrl;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        children: [
          // Section 1 — Acquisition
          _AcquisitionSection(
            purchasePriceCtrl: purchasePriceCtrl,
            notaryFeesCtrl: notaryFeesCtrl,
            worksCtrl: worksCtrl,
            isNewProperty: isNewProperty,
            onIsNewPropertyChanged: onIsNewPropertyChanged,
          ),
          const SizedBox(height: 8),

          // Section 2 — Financement
          _FinancementSection(
            downPaymentCtrl: downPaymentCtrl,
            loanPrincipalCtrl: loanPrincipalCtrl,
            loanRateCtrl: loanRateCtrl,
            loanDurationCtrl: loanDurationCtrl,
          ),
          const SizedBox(height: 8),

          // Section 3 — Revenus locatifs
          _RevenusSection(monthlyRentCtrl: monthlyRentCtrl),
          const SizedBox(height: 8),

          // Section 4 — Charges annuelles
          _ChargesSection(
            propertyTaxCtrl: propertyTaxCtrl,
            insurancePnoCtrl: insurancePnoCtrl,
            condoFeesCtrl: condoFeesCtrl,
          ),
          const SizedBox(height: 8),

          // Notes optionnelles.
          _NotesSection(notesCtrl: notesCtrl),
        ],
      ),
    );
  }
}

// ── Section helpers ──────────────────────────────────────────────────────────

class _AcquisitionSection extends StatelessWidget {
  const _AcquisitionSection({
    required this.purchasePriceCtrl,
    required this.notaryFeesCtrl,
    required this.worksCtrl,
    required this.isNewProperty,
    required this.onIsNewPropertyChanged,
  });

  final TextEditingController purchasePriceCtrl;
  final TextEditingController notaryFeesCtrl;
  final TextEditingController worksCtrl;
  final bool isNewProperty;
  final ValueChanged<bool> onIsNewPropertyChanged;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const Key('section_acquisition'),
      initiallyExpanded: true,
      title: const Text('Acquisition'),
      leading: const Icon(Icons.home_work_outlined),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              _EuroField(
                key: const Key('field_purchase_price'),
                controller: purchasePriceCtrl,
                label: "Prix d'achat *",
                validator: ScenarioFormValidators.validatePurchasePrice,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                key: const Key('field_is_new_property'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Bien neuf'),
                subtitle: const Text('Frais notaire ~2 % (vs 8 % ancien)'),
                value: isNewProperty,
                onChanged: onIsNewPropertyChanged,
              ),
              const SizedBox(height: 12),
              _EuroField(
                key: const Key('field_notary_fees'),
                controller: notaryFeesCtrl,
                label: 'Frais de notaire',
                helperText: 'Pré-rempli : 8 % ancien / 2 % neuf — modifiable',
                validator: (v) =>
                    ScenarioFormValidators.validateOptionalPositiveAmount(
                      v,
                      label: 'Les frais de notaire',
                    ),
              ),
              const SizedBox(height: 12),
              _EuroField(
                key: const Key('field_works_initial'),
                controller: worksCtrl,
                label: 'Travaux initiaux',
                validator: (v) =>
                    ScenarioFormValidators.validateOptionalPositiveAmount(
                      v,
                      label: 'Les travaux',
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FinancementSection extends StatelessWidget {
  const _FinancementSection({
    required this.downPaymentCtrl,
    required this.loanPrincipalCtrl,
    required this.loanRateCtrl,
    required this.loanDurationCtrl,
  });

  final TextEditingController downPaymentCtrl;
  final TextEditingController loanPrincipalCtrl;
  final TextEditingController loanRateCtrl;
  final TextEditingController loanDurationCtrl;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const Key('section_financement'),
      initiallyExpanded: true,
      title: const Text('Financement'),
      leading: const Icon(Icons.account_balance_outlined),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              _EuroField(
                key: const Key('field_down_payment'),
                controller: downPaymentCtrl,
                label: 'Apport personnel',
                validator: (v) =>
                    ScenarioFormValidators.validateOptionalPositiveAmount(
                      v,
                      label: "L'apport",
                    ),
              ),
              const SizedBox(height: 12),
              _EuroField(
                key: const Key('field_loan_principal'),
                controller: loanPrincipalCtrl,
                label: 'Capital emprunté',
                helperText: 'Prix achat + notaire + travaux − apport',
                validator: (v) =>
                    ScenarioFormValidators.validateOptionalPositiveAmount(
                      v,
                      label: 'Le capital emprunté',
                    ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('field_loan_rate'),
                controller: loanRateCtrl,
                decoration: const InputDecoration(
                  labelText: 'Taux nominal (%)',
                  hintText: 'Ex. : 3,50',
                  suffixText: '%',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: ScenarioFormValidators.validateLoanRate,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('field_loan_duration'),
                controller: loanDurationCtrl,
                decoration: const InputDecoration(
                  labelText: 'Durée (mois)',
                  hintText: '240',
                  suffixText: 'mois',
                ),
                keyboardType: TextInputType.number,
                validator: ScenarioFormValidators.validateLoanDuration,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RevenusSection extends StatelessWidget {
  const _RevenusSection({required this.monthlyRentCtrl});

  final TextEditingController monthlyRentCtrl;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const Key('section_revenus'),
      initiallyExpanded: true,
      title: const Text('Revenus locatifs'),
      leading: const Icon(Icons.payments_outlined),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _EuroField(
            key: const Key('field_monthly_rent'),
            controller: monthlyRentCtrl,
            label: 'Loyer mensuel HC *',
            helperText: 'Hors charges récupérables',
            validator: ScenarioFormValidators.validateMonthlyRent,
          ),
        ),
      ],
    );
  }
}

class _ChargesSection extends StatelessWidget {
  const _ChargesSection({
    required this.propertyTaxCtrl,
    required this.insurancePnoCtrl,
    required this.condoFeesCtrl,
  });

  final TextEditingController propertyTaxCtrl;
  final TextEditingController insurancePnoCtrl;
  final TextEditingController condoFeesCtrl;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const Key('section_charges'),
      initiallyExpanded: false,
      title: const Text('Charges annuelles'),
      leading: const Icon(Icons.receipt_long_outlined),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              _EuroField(
                key: const Key('field_property_tax'),
                controller: propertyTaxCtrl,
                label: 'Taxe foncière',
                helperText: 'Net de TEOM récupérable',
                validator: (v) =>
                    ScenarioFormValidators.validateOptionalPositiveAmount(
                      v,
                      label: 'La taxe foncière',
                    ),
              ),
              const SizedBox(height: 12),
              _EuroField(
                key: const Key('field_insurance_pno'),
                controller: insurancePnoCtrl,
                label: 'Assurance PNO',
                validator: (v) =>
                    ScenarioFormValidators.validateOptionalPositiveAmount(
                      v,
                      label: "L'assurance PNO",
                    ),
              ),
              const SizedBox(height: 12),
              _EuroField(
                key: const Key('field_condo_fees'),
                controller: condoFeesCtrl,
                label: 'Charges copropriété non récupérables',
                helperText: 'Gros travaux, syndic, ALUR',
                validator: (v) =>
                    ScenarioFormValidators.validateOptionalPositiveAmount(
                      v,
                      label: 'Les charges de copropriété',
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotesSection extends StatelessWidget {
  const _NotesSection({required this.notesCtrl});

  final TextEditingController notesCtrl;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const Key('section_notes'),
      initiallyExpanded: false,
      title: const Text('Notes'),
      leading: const Icon(Icons.notes_outlined),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: TextFormField(
            key: const Key('field_notes'),
            controller: notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notes libres',
              hintText: 'Remarques, hypothèses particulières…',
            ),
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            validator: ScenarioFormValidators.validateNotes,
          ),
        ),
      ],
    );
  }
}

// ── Champ montant en euros ───────────────────────────────────────────────────

class _EuroField extends StatelessWidget {
  const _EuroField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        suffixText: '€',
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: validator,
    );
  }
}
