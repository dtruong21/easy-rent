/// Bornes absolues acceptées pour les dates métier (bail, paiement, etc.).
///
/// Strictement alignées sur les contraintes Postgres `CHECK BETWEEN
/// '1900-01-01' AND '2100-12-31'` posées sur les tables `leases` (FEAT-005
/// migration `20260529120000_lease_date_bounds.sql`) et `payments` (FEAT-006
/// migration `20260531102202_feat006_payments.sql`).
///
/// Toute date en dehors de cette plage sera rejetée par la DB — on filtre
/// côté client pour offrir un feedback immédiat (defense in depth).
class DateBounds {
  const DateBounds._();

  /// Date minimum acceptée.
  static final DateTime min = DateTime(1900);

  /// Date maximum acceptée.
  static final DateTime max = DateTime(2100, 12, 31);

  /// `true` si [date] est dans la plage `[min, max]`.
  static bool contains(DateTime date) =>
      !date.isBefore(min) && !date.isAfter(max);
}
