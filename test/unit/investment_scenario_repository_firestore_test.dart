/// Tests de la VRAIE implémentation [FirestoreInvestmentScenarioRepository]
/// contre fake_cloud_firestore + un [FirebaseFunctions] enregistreur.
///
/// ## Pourquoi ce fichier existe
///
/// Tous les autres tests liés aux scénarios (`scenario_limit_controller_test`,
/// `saved_scenarios_row*`, `simulator_page_test`) passent par l'interface
/// abstraite [InvestmentScenarioRepository] avec des faux in-memory :
/// l'implémentation concrète — la seule qui parle réellement à Firestore et
/// aux callables — n'était instanciée par AUCUN test. Une suite entière
/// (2606 tests) pouvait donc rester verte alors que `create()` était cassé en
/// prod.
///
/// ## Ce que ces tests verrouillent (et ce qu'ils NE peuvent pas verrouiller)
///
/// Ils couvrent le **chemin d'écriture** : forme du payload envoyé à
/// Firestore, hydratation du modèle en retour, et surtout le **choix du
/// transport** (écriture directe vs callable) pour chaque opération.
///
/// Ils ne peuvent PAS attraper un refus des règles de sécurité :
/// fake_cloud_firestore n'évalue pas `firestore.rules`. C'est exactement
/// l'angle mort qui laisse passer une dérive « la règle passe à
/// `allow create: if false` mais le dépôt continue d'écrire en direct » →
/// ce verrou-là vit dans `firestore_write_path_conformance_test.dart`
/// (règles ↔ dépôts) et, pour l'évaluation réelle des règles, dans
/// `functions/rules-tests/` (émulateur).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:easyrent/features/simulator/data/investment_scenario_repository.dart';
import 'package:easyrent/features/simulator/domain/investment_scenario.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un appel de callable enregistré.
typedef _CallableInvocation = ({String name, Object? params});

/// [FirebaseFunctions] qui enregistre les callables invoquées au lieu de les
/// exécuter — permet d'asserter QUEL transport le dépôt a choisi.
class _RecordingFunctions implements FirebaseFunctions {
  final List<_CallableInvocation> invocations = <_CallableInvocation>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _RecordingCallable(name, invocations);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'FirebaseFunctions.${invocation.memberName} non stubbé dans ce test',
  );
}

class _RecordingCallable implements HttpsCallable {
  _RecordingCallable(this._name, this._invocations);

  final String _name;
  final List<_CallableInvocation> _invocations;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    _invocations.add((name: _name, params: parameters));
    return _FakeCallableResult<T>(null as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'HttpsCallable.${invocation.memberName} non stubbé dans ce test',
  );
}

class _FakeCallableResult<T> implements HttpsCallableResult<T> {
  _FakeCallableResult(this.data);

  @override
  final T data;
}

const _uid = 'lld-scenario-1';

void main() {
  late FakeFirebaseFirestore firestore;
  late _RecordingFunctions functions;
  late FirestoreInvestmentScenarioRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    functions = _RecordingFunctions();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _uid, isAnonymous: false, isEmailVerified: true),
    );
    repo = FirestoreInvestmentScenarioRepository(firestore, auth, functions);
  });

  Future<InvestmentScenario> createSample({String name = 'Studio Lyon 3'}) =>
      repo.create(
        name: name,
        purchasePriceCents: 15000000,
        notaryFeesCents: 1200000,
        monthlyRentHcCents: 65000,
        loanPrincipalCents: 13500000,
        loanRateBps: 350,
        loanDurationMonths: 240,
        propertyTaxAnnualCents: 90000,
        notes: '  à revoir  ',
      );

  group('FirestoreInvestmentScenarioRepository — create()', () {
    test('persiste le scénario et hydrate le modèle retourné', () async {
      final created = await createSample();

      expect(created.id, isNotEmpty);
      expect(created.landlordId, _uid);
      expect(created.name, 'Studio Lyon 3');
      expect(created.purchasePriceCents, 15000000);
      expect(created.monthlyRentHcCents, 65000);
      expect(created.loanRateBps, 350);
      expect(created.notes, 'à revoir', reason: 'notes doit être trimmé');
      expect(created.deletedAt, isNull);

      final stored = await firestore
          .collection('investment_scenarios')
          .doc(created.id)
          .get();
      expect(stored.exists, isTrue);
      expect(stored.data()!['landlordId'], _uid);
      expect(
        stored.data()!['id'],
        created.id,
        reason: 'la règle exige request.resource.data.id == id',
      );
      expect(
        stored.data()!['schemaVersion'],
        1,
        reason: 'la règle exige schemaVersion int > 0',
      );
      expect(
        stored.data()!['scenarioJson'],
        isA<Map<String, dynamic>>(),
        reason: 'la règle exige scenarioJson is map',
      );
      expect(stored.data()!['deletedAt'], isNull);
    });

    test('scenarioJson embarque tous les paramètres financiers', () async {
      final created = await createSample();
      final stored = await firestore
          .collection('investment_scenarios')
          .doc(created.id)
          .get();

      final json = stored.data()!['scenarioJson'] as Map<String, dynamic>;
      expect(json['purchasePriceCents'], 15000000);
      expect(json['notaryFeesCents'], 1200000);
      expect(json['monthlyRentHcCents'], 65000);
      expect(json['loanPrincipalCents'], 13500000);
      expect(json['loanDurationMonths'], 240);
      expect(json['propertyTaxAnnualCents'], 90000);
    });

    test('trim le nom avant écriture', () async {
      final created = await repo.create(
        name: '   Duplex Nantes   ',
        purchasePriceCents: 20000000,
        monthlyRentHcCents: 80000,
      );
      expect(created.name, 'Duplex Nantes');
    });

    test('échoue si non authentifié', () async {
      final anonRepo = FirestoreInvestmentScenarioRepository(
        firestore,
        MockFirebaseAuth(signedIn: false),
        functions,
      );
      expect(
        () => anonRepo.create(
          name: 'X',
          purchasePriceCents: 1,
          monthlyRentHcCents: 1,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('FirestoreInvestmentScenarioRepository — list() / getById()', () {
    test('list() exclut les soft-deleted et les autres landlords', () async {
      final mine = await createSample(name: 'À moi');
      final deleted = await createSample(name: 'Archivé');
      await firestore.collection('investment_scenarios').doc(deleted.id).update(
        {'deletedAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1))},
      );

      final otherRepo = FirestoreInvestmentScenarioRepository(
        firestore,
        MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'autre-landlord'),
        ),
        functions,
      );
      await otherRepo.create(
        name: 'À autrui',
        purchasePriceCents: 1000,
        monthlyRentHcCents: 100,
      );

      final result = await repo.list();

      expect(result, hasLength(1));
      expect(result.single.id, mine.id);
      expect(result.single.name, 'À moi');
    });

    test('getById() rejette un scénario appartenant à autrui', () async {
      final otherRepo = FirestoreInvestmentScenarioRepository(
        firestore,
        MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'autre-landlord'),
        ),
        functions,
      );
      final foreign = await otherRepo.create(
        name: 'À autrui',
        purchasePriceCents: 1000,
        monthlyRentHcCents: 100,
      );

      expect(
        () => repo.getById(foreign.id),
        throwsA(isA<InvestmentScenarioNotFoundException>()),
      );
    });

    test('getById() rejette un scénario soft-deleted', () async {
      final s = await createSample();
      await firestore.collection('investment_scenarios').doc(s.id).update({
        'deletedAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
      });

      expect(
        () => repo.getById(s.id),
        throwsA(isA<InvestmentScenarioNotFoundException>()),
      );
    });
  });

  group('FirestoreInvestmentScenarioRepository — update()', () {
    test('met à jour le doc et re-hydrate le modèle', () async {
      final created = await createSample();

      final updated = await repo.update(
        created.copyWith(name: 'Studio Lyon 3 — révisé', loanRateBps: 410),
      );

      expect(updated.name, 'Studio Lyon 3 — révisé');
      expect(updated.loanRateBps, 410);

      final stored = await firestore
          .collection('investment_scenarios')
          .doc(created.id)
          .get();
      expect(stored.data()!['loanRateBps'], 410);
      expect(
        (stored.data()!['scenarioJson'] as Map<String, dynamic>)['loanRateBps'],
        410,
        reason: 'scenarioJson doit rester synchro avec les champs root',
      );
      expect(
        stored.data()!['landlordId'],
        _uid,
        reason: 'landlordId est immuable (preservesImmutables)',
      );
    });
  });

  group('FirestoreInvestmentScenarioRepository — transport des écritures', () {
    test('softDelete() passe par la callable softDeleteEntity, pas par une '
        'écriture directe', () async {
      final created = await createSample();
      functions.invocations.clear();

      await repo.softDelete(created.id);

      expect(
        functions.invocations,
        hasLength(1),
        reason:
            'la règle `allow delete: if false` impose de passer par la '
            'Cloud Function softDeleteEntity',
      );
      expect(functions.invocations.single.name, 'softDeleteEntity');
      expect(functions.invocations.single.params, <String, dynamic>{
        'collection': 'investment_scenarios',
        'id': created.id,
      });
    });

    test('create() et update() n\'invoquent aucune callable (écriture directe '
        'autorisée par les règles — cf. conformance test)', () async {
      final created = await createSample();
      await repo.update(created.copyWith(name: 'Renommé'));

      expect(
        functions.invocations,
        isEmpty,
        reason:
            'Si ce test casse, le transport de create/update a changé : '
            'mettre à jour la matrice de '
            'firestore_write_path_conformance_test.dart ET firestore.rules.',
      );
    });
  });
}
