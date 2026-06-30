import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/db.dart';
import '../domain/investment_scenario.dart';

final _log = Logger('InvestmentScenarioRepository');

/// Contrat public du repository scénarios d'investissement (FEAT-018).
///
/// Les providers et widgets consomment cette interface, jamais l'implémentation
/// directe — facilite les mocks dans les tests.
abstract interface class InvestmentScenarioRepository {
  /// Liste les scénarios du landlord courant, triés `created_at DESC`.
  ///
  /// Exclut les soft-deleted (`deleted_at IS NULL`).
  /// Limité à 200 lignes (garde-fou).
  Future<List<InvestmentScenario>> list();

  /// Retourne un scénario par son [id].
  ///
  /// Lance [InvestmentScenarioNotFoundException] si la RLS renvoie 0 ligne.
  Future<InvestmentScenario> getById(String id);

  /// Crée un nouveau scénario.
  ///
  /// Ne pas inclure `landlord_id` : DEFAULT auth.uid() géré côté serveur.
  Future<InvestmentScenario> create({
    required String name,
    required int purchasePriceCents,
    int notaryFeesCents,
    int worksInitialCents,
    bool isNewProperty,
    int downPaymentCents,
    int loanPrincipalCents,
    int loanRateBps,
    int loanDurationMonths,
    required int monthlyRentHcCents,
    int propertyTaxAnnualCents,
    int insurancePnoAnnualCents,
    int condoFeesNonRecoverableCents,
    String? notes,
  });

  /// Met à jour tous les champs métier d'un scénario existant.
  Future<InvestmentScenario> update(InvestmentScenario scenario);

  /// Soft-delete : positionne `deleted_at = now()` sur le scénario [id].
  Future<void> softDelete(String id);
}

/// Implémentation Supabase du [InvestmentScenarioRepository].
class SupabaseInvestmentScenarioRepository
    implements InvestmentScenarioRepository {
  const SupabaseInvestmentScenarioRepository();

  @override
  Future<List<InvestmentScenario>> list() async {
    _log.info('list()');
    final rows = await Db.from('investment_scenarios')
        .select()
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: false)
        .limit(200);
    return rows.map((r) => InvestmentScenario.fromJson(r)).toList();
  }

  @override
  Future<InvestmentScenario> getById(String id) async {
    _log.info('getById($id)');
    final rows = await Db.from(
      'investment_scenarios',
    ).select().eq('id', id).filter('deleted_at', 'is', null).limit(1);
    if (rows.isEmpty) {
      throw InvestmentScenarioNotFoundException(id);
    }
    return InvestmentScenario.fromJson(rows.first);
  }

  @override
  Future<InvestmentScenario> create({
    required String name,
    required int purchasePriceCents,
    int notaryFeesCents = 0,
    int worksInitialCents = 0,
    bool isNewProperty = false,
    int downPaymentCents = 0,
    int loanPrincipalCents = 0,
    int loanRateBps = 0,
    int loanDurationMonths = 240,
    required int monthlyRentHcCents,
    int propertyTaxAnnualCents = 0,
    int insurancePnoAnnualCents = 0,
    int condoFeesNonRecoverableCents = 0,
    String? notes,
  }) async {
    _log.info('create(name=$name)');
    final payload = <String, dynamic>{
      'name': name.trim(),
      'purchase_price_cents': purchasePriceCents,
      'notary_fees_cents': notaryFeesCents,
      'works_initial_cents': worksInitialCents,
      'is_new_property': isNewProperty,
      'down_payment_cents': downPaymentCents,
      'loan_principal_cents': loanPrincipalCents,
      'loan_rate_bps': loanRateBps,
      'loan_duration_months': loanDurationMonths,
      'monthly_rent_hc_cents': monthlyRentHcCents,
      'property_tax_annual_cents': propertyTaxAnnualCents,
      'insurance_pno_annual_cents': insurancePnoAnnualCents,
      'condo_fees_non_recoverable_cents': condoFeesNonRecoverableCents,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };
    final rows = await Db.from('investment_scenarios').insert(payload).select();
    return InvestmentScenario.fromJson(rows.first);
  }

  @override
  Future<InvestmentScenario> update(InvestmentScenario scenario) async {
    _log.info('update(id=${scenario.id})');
    final payload = <String, dynamic>{
      'name': scenario.name.trim(),
      'purchase_price_cents': scenario.purchasePriceCents,
      'notary_fees_cents': scenario.notaryFeesCents,
      'works_initial_cents': scenario.worksInitialCents,
      'is_new_property': scenario.isNewProperty,
      'down_payment_cents': scenario.downPaymentCents,
      'loan_principal_cents': scenario.loanPrincipalCents,
      'loan_rate_bps': scenario.loanRateBps,
      'loan_duration_months': scenario.loanDurationMonths,
      'monthly_rent_hc_cents': scenario.monthlyRentHcCents,
      'property_tax_annual_cents': scenario.propertyTaxAnnualCents,
      'insurance_pno_annual_cents': scenario.insurancePnoAnnualCents,
      'condo_fees_non_recoverable_cents': scenario.condoFeesNonRecoverableCents,
      'notes': scenario.notes,
    };
    final rows = await Db.from(
      'investment_scenarios',
    ).update(payload).eq('id', scenario.id).select();
    if (rows.isEmpty) {
      throw InvestmentScenarioNotFoundException(scenario.id);
    }
    return InvestmentScenario.fromJson(rows.first);
  }

  @override
  Future<void> softDelete(String id) async {
    _log.info('softDelete($id)');
    await Db.from(
      'investment_scenarios',
    ).update({'deleted_at': DateTime.now().toIso8601String()}).eq('id', id);
  }
}

/// Exception levée quand un scénario est introuvable (RLS ou soft-deleted).
class InvestmentScenarioNotFoundException implements Exception {
  const InvestmentScenarioNotFoundException(this.id);

  final String id;

  @override
  String toString() =>
      'InvestmentScenarioNotFoundException: scénario $id introuvable';
}

/// Provider exposant le repository scénarios d'investissement.
final investmentScenarioRepositoryProvider =
    Provider<InvestmentScenarioRepository>(
      (ref) => const SupabaseInvestmentScenarioRepository(),
    );

/// AsyncNotifier gérant la liste des scénarios du landlord courant.
///
/// Expose `investmentScenariosListProvider` via [AsyncNotifierProvider].
class InvestmentScenariosListNotifier
    extends AsyncNotifier<List<InvestmentScenario>> {
  @override
  Future<List<InvestmentScenario>> build() =>
      ref.read(investmentScenarioRepositoryProvider).list();

  /// Recharge la liste depuis Supabase.
  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(investmentScenarioRepositoryProvider).list(),
    );
  }

  /// Supprime un scénario et recharge la liste.
  Future<void> delete(String id) async {
    await ref.read(investmentScenarioRepositoryProvider).softDelete(id);
    await reload();
  }
}

/// Provider de la liste des scénarios d'investissement.
final investmentScenariosListProvider =
    AsyncNotifierProvider<
      InvestmentScenariosListNotifier,
      List<InvestmentScenario>
    >(InvestmentScenariosListNotifier.new);
