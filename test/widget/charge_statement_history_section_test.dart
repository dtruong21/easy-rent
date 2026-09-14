/// Tests widget de [ChargeStatementHistorySection] (FEAT-033 Task 9).
///
/// Vérifie que la section affiche, pour chaque décompte figé retourné par
/// [chargeStatementRepositoryProvider] :
/// - la période + le solde formaté + le libellé de sens (`labelFr`) ;
/// - le badge "Envoyé" pour un décompte envoyé ;
/// - le badge "Annulé" pour un décompte annulé ;
/// - le bouton "Re-partager", toujours présent (même sur un décompte
///   annulé — seule l'action "Annuler" est masquée dans ce cas).
library;

import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/charge_regularization/data/charge_statement_repository.dart';
import 'package:easyrent/features/charge_regularization/domain/charge_statement.dart';
import 'package:easyrent/features/charge_regularization/presentation/widgets/charge_statement_history_section.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake ChargeStatementRepository — retourne une liste fixe, les autres
// méthodes ne sont pas exercées par ces tests (bouton "Annuler" non tapé).
// ---------------------------------------------------------------------------

class _FakeChargeStatementRepository implements ChargeStatementRepository {
  _FakeChargeStatementRepository(this.statements);

  final List<ChargeStatement> statements;

  @override
  Future<List<ChargeStatement>> listForLease(String leaseId) async =>
      statements;

  @override
  Future<ChargeStatement> getById(String id) async =>
      throw UnimplementedError();

  @override
  Future<ChargeStatementFinalizeResult> finalize({
    required String leaseId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int actualExpensesCents,
    required String actualExpensesSource,
    required List<Map<String, dynamic>> lineItems,
  }) async => throw UnimplementedError();

  @override
  Future<void> voidStatement(String id, String reason) async =>
      throw UnimplementedError();

  @override
  Future<void> markAsSent({required String id, String? email}) async =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _baseJson({required String id}) => {
  'id': id,
  'landlord_id': 'lord1',
  'lease_id': 'lease-1',
  'property_id': 'p1',
  'landlord_full_name': 'Marie Martin',
  'landlord_address': '1 rue de Paris, 75001 Paris',
  'tenant_full_name': 'Jean Dupont',
  'tenant_first_name': 'Jean',
  'property_name': 'Studio',
  'property_address': '2 rue de Lyon, 69001 Lyon',
  'period_start': '2025-01-01T00:00:00.000Z',
  'period_end': '2025-12-31T00:00:00.000Z',
  'provisions_collected_cents': 12000,
  'actual_expenses_cents': 15000,
  'actual_expenses_source': 'manual',
  'balance_cents': 3000,
  'line_items': <dynamic>[],
  'created_at': '2026-01-05T10:00:00.000Z',
  'is_voided': false,
  'voided_at': null,
  'voided_reason': null,
  'sent_at': null,
  'sent_to_email': null,
  'schema_version': 1,
};

ChargeStatement _sentStatement() => ChargeStatement.fromJson({
  ..._baseJson(id: 'cs-sent'),
  'sent_at': '2026-01-06T09:00:00.000Z',
  'sent_to_email': 'loc@example.com',
});

ChargeStatement _voidedStatement() => ChargeStatement.fromJson({
  ..._baseJson(id: 'cs-voided'),
  'balance_cents': -2500,
  'is_voided': true,
  'voided_at': '2026-01-07T09:00:00.000Z',
  'voided_reason': 'Erreur de saisie',
});

Widget _buildSection(List<ChargeStatement> statements) {
  return ProviderScope(
    overrides: [
      chargeStatementRepositoryProvider.overrideWithValue(
        _FakeChargeStatementRepository(statements),
      ),
    ],
    child: MaterialApp(
      // AppTheme.light requis : StatusPill (badges Envoyé/Annulé) lit
      // l'extension AppColors — absente du ThemeData par défaut de
      // MaterialApp.
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
      home: const Scaffold(
        body: ChargeStatementHistorySection(leaseId: 'lease-1'),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChargeStatementHistorySection', () {
    testWidgets(
      'affiche solde + libellé, badges Envoyé/Annulé, bouton Re-partager',
      (tester) async {
        await tester.pumpWidget(
          _buildSection([_sentStatement(), _voidedStatement()]),
        );
        await tester.pumpAndSettle();

        // Titre de section.
        expect(find.text('Décomptes figés'), findsOneWidget);

        // Solde + libellé de sens (balanceAbsCents formaté + labelFr) pour
        // chacun des deux décomptes. Espace insécable entre le montant et
        // "€" en fr_FR (cf. money_format_test.dart) : on ne teste donc pas
        // une sous-chaîne combinée avec un espace classique.
        expect(find.textContaining('30,00'), findsOneWidget); // cs-sent
        expect(find.textContaining('25,00'), findsOneWidget); // cs-voided

        // Badges.
        expect(find.text('Envoyé'), findsOneWidget);
        expect(find.text('Annulé'), findsOneWidget);

        // Bouton "Re-partager" présent pour les deux tuiles (même la tuile
        // annulée conserve l'action de re-partage — seule "Annuler" est
        // masquée sur un décompte déjà annulé).
        expect(
          find.byKey(const Key('btn_charge_statement_reshare_cs-sent')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('btn_charge_statement_reshare_cs-voided')),
          findsOneWidget,
        );
        expect(find.text('Re-partager'), findsNWidgets(2));

        // L'action "Annuler" est disponible sur le décompte envoyé...
        expect(
          find.byKey(const Key('btn_charge_statement_void_cs-sent')),
          findsOneWidget,
        );
        // ... mais masquée sur le décompte déjà annulé.
        expect(
          find.byKey(const Key('btn_charge_statement_void_cs-voided')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'liste vide → section entière masquée (pas de gate PRO/légal, mais '
      'pas d\'historique à montrer non plus)',
      (tester) async {
        await tester.pumpWidget(_buildSection(const []));
        await tester.pumpAndSettle();

        expect(find.text('Décomptes figés'), findsNothing);
        expect(find.textContaining('Re-partager'), findsNothing);
      },
    );
  });
}
