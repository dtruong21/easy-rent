import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/firestore_provider.dart';
import '../../../core/firestore_helpers.dart';
import '../../../core/utils/money_format.dart';
import '../domain/heating_type.dart';
import '../domain/property.dart';
import '../domain/property_list_item.dart';
import '../domain/property_type.dart';

final _log = Logger('PropertyRepository');

/// Contrat public du repository biens immobiliers.
///
/// Les providers et widgets consomment cette interface, jamais l'implémentation
/// directe — facilite les mocks dans les tests.
abstract interface class PropertyRepository {
  /// Liste tous les biens du landlord courant, triés `createdAt DESC`.
  ///
  /// Limité à 200 docs (garde-fou — cible utilisateur : 1-20 biens).
  /// Filtré par `landlordId == uid AND deletedAt == null` côté query +
  /// Firestore Rules.
  Future<List<Property>> list();

  /// Liste les biens enrichis avec le bail actif courant (locataire, loyer).
  ///
  /// Implémentation : 2 queries parallèles (properties + leases actifs),
  /// jointure côté client. Les leases ont déjà les denorms tenantFirstName/
  /// tenantLastName, donc pas de 3e query nécessaire.
  Future<List<PropertyListItem>> listWithLeases();

  /// Retourne un bien par son [id].
  ///
  /// Lance [PropertyNotFoundException] si le doc n'existe pas ou est
  /// soft-deleted ou appartient à un autre landlord (Rules bloquent).
  Future<Property> getById(String id);

  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
    String? postalCode,
    String? city,
    int? rooms,
    int? bedrooms,
    int? floor,
    bool hasElevator,
    bool furnished,
    HeatingType? heatingType,
    String? dpeLetter,
    int? dpeValueKwhM2Year,
    String? gesLetter,
    int? constructionYear,
    int? purchasePriceCents,
    DateTime? purchaseDate,
    int? notaryFeesCents,
    bool isNewProperty,
    int? propertyTaxAnnualCents,
    int? insurancePnoAnnualCents,
    int? condoFeesNonRecoverableCents,
    int? loanPrincipalCents,
    int? loanRateBps,
    int? loanInsuranceBps,
    int? loanDurationMonths,
    DateTime? loanStartDate,
    int? loanMonthlyPaymentOverrideCents,
  });

  /// Met à jour les champs métier d'un bien existant.
  ///
  /// Les Rules Firestore garantissent que `landlordId`, `createdAt`,
  /// `deletedAt`, `activeLeaseCount` ne sont pas modifiés.
  /// Le trigger `setUpdatedAtProperties` pose `updatedAt = serverTimestamp()`.
  Future<Property> update(Property property);

  /// Compte les baux actifs liés au bien [propertyId].
  ///
  /// Lit le champ denormalisé `activeLeaseCount` sur le doc property —
  /// 1 read au lieu d'une query sur leases.
  Future<int> countActiveLeases(String propertyId);

  /// Archive (soft-delete) le bien [id] via la Callable `softDeleteEntity`.
  ///
  /// La Callable refuse si `activeLeaseCount > 0` (RESTRICT) et écrit
  /// `deletedAt = serverTimestamp()` (les Rules interdisent l'écriture
  /// directe de `deletedAt` côté client).
  Future<void> archive(String id);
}

/// Implémentation Firestore du [PropertyRepository].
class FirestorePropertyRepository implements PropertyRepository {
  FirestorePropertyRepository(this._firestore, this._auth, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not authenticated — property operations require auth');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('properties');

  @override
  Future<List<Property>> list() async {
    _log.info('list()');
    final qs = await _col
        .where('landlordId', isEqualTo: _uid)
        .where('deletedAt', isNull: true)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get();
    return qs.docs
        .map(
          (d) =>
              Property.fromJson(firestoreDocToSnakeJson(d.data(), docId: d.id)),
        )
        .toList();
  }

  @override
  Future<List<PropertyListItem>> listWithLeases() async {
    _log.info('listWithLeases()');
    final uid = _uid;
    final propertiesQs = _col
        .where('landlordId', isEqualTo: uid)
        .where('deletedAt', isNull: true)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get();
    final leasesQs = _firestore
        .collection('leases')
        .where('landlordId', isEqualTo: uid)
        .where('deletedAt', isNull: true)
        .where('status', isEqualTo: 'active')
        .get();

    final results = await Future.wait([propertiesQs, leasesQs]);
    final propDocs = results[0].docs;
    final leaseDocs = results[1].docs;

    // Index des baux actifs par propertyId (1 actif max attendu).
    final activeByPropId = <String, Map<String, dynamic>>{};
    for (final lease in leaseDocs) {
      final data = lease.data();
      final propId = data['propertyId'] as String?;
      if (propId == null) continue;
      activeByPropId.putIfAbsent(propId, () => {...data, 'id': lease.id});
    }

    return propDocs.map((doc) {
      final property = Property.fromJson(
        firestoreDocToSnakeJson(doc.data(), docId: doc.id),
      );
      final lease = activeByPropId[doc.id];
      if (lease == null) {
        return PropertyListItem(property: property);
      }
      final firstName = lease['tenantFirstName'] as String? ?? '';
      final lastName = lease['tenantLastName'] as String? ?? '';
      final tenantName = '$firstName $lastName'.trim();
      final rentHcCents = lease['rentAmountCents'] as int?;
      final rent = rentHcCents ?? 0;
      final charges = lease['chargesAmountCents'] as int? ?? 0;
      return PropertyListItem(
        property: property,
        activeLeaseId: lease['id'] as String?,
        currentTenantName: tenantName.isEmpty ? null : tenantName,
        currentRentLabel:
            '${MoneyFormat.formatEurosFromCents(rent + charges)} CC / mois',
        currentRentHcCents: rentHcCents,
      );
    }).toList();
  }

  @override
  Future<Property> getById(String id) async {
    _log.info('getById($id)');
    final snap = await _col.doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null || data['deletedAt'] != null) {
      throw PropertyNotFoundException(id);
    }
    if (data['landlordId'] != _uid) {
      throw PropertyNotFoundException(id);
    }
    return Property.fromJson(firestoreDocToSnakeJson(data, docId: snap.id));
  }

  @override
  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
    String? postalCode,
    String? city,
    int? rooms,
    int? bedrooms,
    int? floor,
    bool hasElevator = false,
    bool furnished = false,
    HeatingType? heatingType,
    String? dpeLetter,
    int? dpeValueKwhM2Year,
    String? gesLetter,
    int? constructionYear,
    int? purchasePriceCents,
    DateTime? purchaseDate,
    int? notaryFeesCents,
    bool isNewProperty = false,
    int? propertyTaxAnnualCents,
    int? insurancePnoAnnualCents,
    int? condoFeesNonRecoverableCents,
    int? loanPrincipalCents,
    int? loanRateBps,
    int? loanInsuranceBps,
    int? loanDurationMonths,
    DateTime? loanStartDate,
    int? loanMonthlyPaymentOverrideCents,
  }) async {
    _log.info('create(type=${type.sqlValue})');
    // FEAT-044 : la création passe par la Callable `createProperty` (au lieu
    // d'un `docRef.set` direct) — elle impose le plafond free-tier côté serveur
    // et maintient le compteur `landlords.activePropertiesCount`. La rule
    // `properties/create` est passée à `if false` (CF-exclusif). Un dépassement
    // de plafond remonte en `FirebaseFunctionsException(code: 'resource-exhausted')`.
    // Dates envoyées en ISO-8601 (les Timestamp ne transitent pas par le
    // protocole Callable) ; le serveur reconvertit via `optionalTimestamp`.
    final callable = _functions.httpsCallable(
      'createProperty',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    final res = await callable.call(<String, dynamic>{
      'name': name.trim(),
      'address': address.trim(),
      'type': type.sqlValue,
      'surfaceM2': surfaceM2,
      'postalCode': postalCode?.trim(),
      'city': city?.trim(),
      'rooms': rooms,
      'bedrooms': bedrooms,
      'floor': floor,
      'hasElevator': hasElevator,
      'furnished': furnished,
      'heatingType': heatingType?.sqlValue,
      'dpeLetter': dpeLetter,
      'dpeValueKwhM2Year': dpeValueKwhM2Year,
      'gesLetter': gesLetter,
      'constructionYear': constructionYear,
      'purchasePriceCents': purchasePriceCents,
      'purchaseDate': purchaseDate?.toUtc().toIso8601String(),
      'notaryFeesCents': notaryFeesCents,
      'isNewProperty': isNewProperty,
      'propertyTaxAnnualCents': propertyTaxAnnualCents,
      'insurancePnoAnnualCents': insurancePnoAnnualCents,
      'condoFeesNonRecoverableCents': condoFeesNonRecoverableCents,
      'loanPrincipalCents': loanPrincipalCents,
      'loanRateBps': loanRateBps,
      'loanInsuranceBps': loanInsuranceBps,
      'loanDurationMonths': loanDurationMonths,
      'loanStartDate': loanStartDate?.toUtc().toIso8601String(),
      'loanMonthlyPaymentOverrideCents': loanMonthlyPaymentOverrideCents,
    });
    final propertyId = (res.data as Map?)?['propertyId'] as String?;
    if (propertyId == null) {
      throw StateError('createProperty did not return a propertyId');
    }
    return getById(propertyId);
  }

  @override
  Future<Property> update(Property property) async {
    _log.info('update(id=${property.id})');
    // Rules interdisent landlordId, createdAt, deletedAt, activeLeaseCount.
    final purchaseDate = property.purchaseDate;
    final loanStartDate = property.loanStartDate;
    final payload = <String, dynamic>{
      'name': property.name.trim(),
      'address': property.address.trim(),
      'type': property.type.sqlValue,
      'surfaceM2': property.surfaceM2,
      'postalCode': property.postalCode,
      'city': property.city,
      'rooms': property.rooms,
      'bedrooms': property.bedrooms,
      'floor': property.floor,
      'hasElevator': property.hasElevator,
      'furnished': property.furnished,
      'heatingType': property.heatingType?.sqlValue,
      'dpeLetter': property.dpeLetter,
      'dpeValueKwhM2Year': property.dpeValueKwhM2Year,
      'gesLetter': property.gesLetter,
      'constructionYear': property.constructionYear,
      'purchasePriceCents': property.purchasePriceCents,
      'purchaseDate': purchaseDate == null
          ? null
          : Timestamp.fromDate(purchaseDate.toUtc()),
      'notaryFeesCents': property.notaryFeesCents,
      'isNewProperty': property.isNewProperty,
      'propertyTaxAnnualCents': property.propertyTaxAnnualCents,
      'insurancePnoAnnualCents': property.insurancePnoAnnualCents,
      'condoFeesNonRecoverableCents': property.condoFeesNonRecoverableCents,
      'loanPrincipalCents': property.loanPrincipalCents,
      'loanRateBps': property.loanRateBps,
      'loanInsuranceBps': property.loanInsuranceBps,
      'loanDurationMonths': property.loanDurationMonths,
      'loanStartDate': loanStartDate == null
          ? null
          : Timestamp.fromDate(loanStartDate.toUtc()),
      'loanMonthlyPaymentOverrideCents':
          property.loanMonthlyPaymentOverrideCents,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final ref = _col.doc(property.id);
    await ref.update(payload);
    final saved = await ref.get();
    if (!saved.exists) {
      throw PropertyNotFoundException(property.id);
    }
    return Property.fromJson(
      firestoreDocToSnakeJson(saved.data()!, docId: saved.id),
    );
  }

  @override
  Future<int> countActiveLeases(String propertyId) async {
    _log.info('countActiveLeases($propertyId)');
    final snap = await _col.doc(propertyId).get();
    if (!snap.exists) return 0;
    final count = snap.data()?['activeLeaseCount'];
    return count is int ? count : 0;
  }

  @override
  Future<void> archive(String id) async {
    _log.info('archive($id)');
    final callable = _functions.httpsCallable(
      'softDeleteEntity',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    await callable.call(<String, dynamic>{
      'collection': 'properties',
      'id': id,
    });
  }
}

/// Exception levée quand un bien est introuvable (Rules ou archivage).
class PropertyNotFoundException implements Exception {
  const PropertyNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'PropertyNotFoundException: bien $id introuvable';
}

/// Provider exposant le repository biens immobiliers.
final propertyRepositoryProvider = Provider<PropertyRepository>((ref) {
  return FirestorePropertyRepository(
    ref.watch(firestoreProvider),
    FirebaseAuth.instance,
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});
