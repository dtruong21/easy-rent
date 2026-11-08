import 'package:easyrent/features/simulator/domain/lmnp_tax_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Chaque valeur est figée : la modifier doit être un choix explicite
  // (nouvelle loi de finances), pas un effet de bord.
  test('règles 2026 — valeurs de la loi en vigueur', () {
    const r = lmnpRules2026;
    expect(r.label, 'Règles 2026');
    expect(r.microAbatementPercent, 50);
    expect(r.microMinAbatementCents, 30500);
    expect(r.microCeilingCents, 8360000);
    expect(r.socialRatePermille, 186);
    expect(r.buildingYears, 30);
    expect(r.worksYears, 15);
    expect(r.furnitureYears, 7);
    expect(r.lmpAlertCents, 2300000);
    expect(r.deficitCarryYears, 10);
  });

  test('tranches proposées', () {
    expect(kTmiChoices, [0, 11, 30, 41, 45]);
  });
}
