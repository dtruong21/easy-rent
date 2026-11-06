import 'package:easyrent/features/simulator/domain/investment_scenario.dart';
import 'package:easyrent/features/simulator/domain/lmnp_tax_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

InvestmentScenario _s({
  int price = 10000000,
  int notary = 0,
  int works = 0,
  int furniture = 0,
  int land = 15,
  int rent = 60000,
  int tf = 0,
  int pno = 0,
  int copro = 0,
  int loan = 0,
  int bps = 0,
  int months = 240,
  int tmi = 30,
}) => InvestmentScenario(
  id: 't',
  landlordId: 'l',
  name: 't',
  purchasePriceCents: price,
  notaryFeesCents: notary,
  worksInitialCents: works,
  furnitureCents: furniture,
  landSharePercent: land,
  monthlyRentHcCents: rent,
  propertyTaxAnnualCents: tf,
  insurancePnoAnnualCents: pno,
  condoFeesNonRecoverableCents: copro,
  loanPrincipalCents: loan,
  loanRateBps: bps,
  loanDurationMonths: months,
  tmiPercent: tmi,
  isFurnished: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  test('cas A sans prêt', () {
    final r = simulateLmnpTax(
      _s(notary: 800000, furniture: 700000, land: 20, tf: 80000, pno: 15000),
    );
    final m = r.micro.years[0];
    expect(m.taxableCents, 360000);
    expect(m.incomeTaxCents, 108000);
    expect(m.socialCents, 66960);
    expect(m.cashflowAfterTaxCents, 450040);
    expect(r.micro.totalTaxCents, 1749600);
    expect(r.micro.totalCashflowAfterTaxCents, 4500400);
    final y = r.reel.years;
    for (var i = 0; i < 3; i++) {
      expect(y[i].taxableCents, 0);
      expect(y[i].cashflowAfterTaxCents, 625000);
    }
    expect(y[3].taxableCents, 233332);
    expect(y[3].incomeTaxCents, 70000);
    expect(y[3].socialCents, 43400);
    for (var i = 4; i < 7; i++) {
      expect(y[i].taxableCents, 258333);
    }
    for (var i = 7; i < 10; i++) {
      expect(y[i].taxableCents, 358333);
    }
    expect(r.reel.totalTaxCents, 1012500);
    expect(r.reel.totalCashflowAfterTaxCents, 5237500);
    expect(r.best, LmnpRegime.reel);
  });

  test('cas B avec prêt', () {
    final r = simulateLmnpTax(
      _s(
        price: 20000000,
        notary: 1500000,
        works: 1000000,
        furniture: 500000,
        rent: 90000,
        tf: 120000,
        pno: 20000,
        copro: 30000,
        loan: 18000000,
        bps: 350,
      ),
    );
    final m = r.micro.years[0];
    expect(m.taxableCents, 540000);
    expect(m.incomeTaxCents, 162000);
    expect(m.socialCents, 100440);
    expect(m.cashflowAfterTaxCents, -659156);
    expect(r.micro.totalTaxCents, 2624400);
    expect(r.reel.years.length, 10);
    for (final y in r.reel.years) {
      expect(y.taxableCents, 0);
      expect(y.cashflowAfterTaxCents, -396716);
    }
    expect(r.reel.totalTaxCents, 0);
    expect(r.best, LmnpRegime.reel);
  });

  test('plancher 305 euros', () {
    final m = simulateLmnpTax(_s(rent: 5000)).micro.years[0];
    expect(m.taxableCents, 29500);
    expect(m.incomeTaxCents, 8850);
    expect(m.socialCents, 5487);
  });

  test('plafond micro', () {
    final r = simulateLmnpTax(_s(rent: 700000));
    expect(r.micro.available, false);
    expect(r.best, LmnpRegime.reel);
    expect(r.lmpAlert, true);
  });

  test('alerte LMP seule', () {
    final a = simulateLmnpTax(_s(rent: 200000));
    expect(a.lmpAlert, true);
    expect(a.micro.available, true);
    expect(simulateLmnpTax(_s(rent: 190000)).lmpAlert, false);
  });

  test('déficit périmé après 10 ans', () {
    final r = simulateLmnpTax(
      _s(price: 30000, notary: 10000000, land: 50),
      years: 12,
    );
    for (var i = 0; i < 11; i++) {
      expect(r.reel.years[i].taxableCents, 0);
    }
    final y = r.reel.years[11];
    expect(y.taxableCents, 714000);
    expect(y.incomeTaxCents, 214200);
    expect(y.socialCents, 132804);
    expect(y.cashflowAfterTaxCents, 372996);
  });

  test('égalité => micro', () {
    expect(simulateLmnpTax(_s(rent: 0)).best, LmnpRegime.micro);
  });
}
