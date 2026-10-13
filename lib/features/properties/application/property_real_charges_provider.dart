import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/finance/real_expense_charges.dart';
import '../../expenses/application/real_charges_grouping.dart';
import '../../expenses/data/expenses_repository.dart';

final _log = Logger('PropertyRealChargesProvider');

/// Dépenses réelles non récupérables d'un bien, regroupées par nature de
/// charge prévisionnelle (taxe foncière, assurance PNO, charges copro non
/// récupérables) — alimente le cash flow réel de
/// `computeSnapshotForProperty` sur la fiche d'un bien
/// (`PropertyProfitabilityCard`).
///
/// Une seule requête Firestore par bien (`listForProperty`, déjà utilisée
/// par la page dépenses). En cas d'échec (ex. environnement de test sans
/// Firebase initialisé), l'appelant se replie gracieusement sur
/// [PropertyRealCharges.empty] — le cash flow reste alors purement
/// prévisionnel plutôt que de faire échouer toute la carte rentabilité.
final propertyRealChargesProvider = FutureProvider.autoDispose
    .family<PropertyRealCharges, String>((ref, propertyId) async {
      _log.info('propertyRealChargesProvider($propertyId)');
      final expenses = await ref
          .watch(expensesRepositoryProvider)
          .listForProperty(propertyId);
      return groupRealCharges(expenses);
    });
