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
/// Depuis FEAT-056 (PR-2b), `create()` passe par la Callable `createScenario`
/// (la rule `investment_scenarios/create` vaut `if false`) — exactement comme
/// `createProperty`/`createTenant`. `fake_cloud_firestore` n'exécute aucune
/// Cloud Function : [_RecordingFunctions] simule donc, pour `createScenario`
/// uniquement, l'écriture serveur (`buildScenarioDocument` dans
/// `functions/src/callable/scenarios.ts`) afin que la suite puisse continuer
/// d'exercer list()/getById()/update() sur des scénarios réellement présents
/// dans le fake. Les autres callables (`softDeleteEntity`) restent de purs
/// enregistrements, sans effet — ces tests-là ne vérifient que le transport.
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
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un appel de callable enregistré.
typedef _CallableInvocation = ({String name, Object? params});

/// Clés financières du document `investment_scenarios` — miroir de
/// `financials` dans `buildScenarioDocument` (functions/src/callable/scenarios.ts).
const _scenarioFinancialKeys = <String>[
  'purchasePriceCents',
  'notaryFeesCents',
  'worksInitialCents',
  'isNewProperty',
  'downPaymentCents',
  'loanPrincipalCents',
  'loanRateBps',
  'loanDurationMonths',
  'monthlyRentHcCents',
  'propertyTaxAnnualCents',
  'insurancePnoAnnualCents',
  'condoFeesNonRecoverableCents',
];

/// [FirebaseFunctions] qui enregistre les callables invoquées — et simule,
/// pour `createScenario` seulement, l'écriture serveur réelle.
class _RecordingFunctions implements FirebaseFunctions {
  _RecordingFunctions(this._firestore, this._auth);

  final FakeFirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final List<_CallableInvocation> invocations = <_CallableInvocation>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _RecordingCallable(name, invocations, _firestore, _auth);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'FirebaseFunctions.${invocation.memberName} non stubbé dans ce test',
  );
}

class _RecordingCallable implements HttpsCallable {
  _RecordingCallable(
    this._name,
    this._invocations,
    this._firestore,
    this._auth,
  );

  final String _name;
  final List<_CallableInvocation> _invocations;
  final FakeFirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    _invocations.add((name: _name, params: parameters));

    if (_name != 'createScenario') {
      // softDeleteEntity et consorts : pur enregistrement, ces tests ne
      // vérifient que le choix du transport, jamais l'effet.
      return _FakeCallableResult<T>(null as T);
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      // Simule le rejet de `requireAuthUid()` côté Cloud Function : en prod
      // le client recevrait un `FirebaseFunctionsException(code:
      // 'unauthenticated')`, mais son constructeur est `@protected`
      // (inutilisable hors du package `cloud_functions_platform_interface`).
      // StateError garde l'intention testée — create() échoue sans
      // authentification — sans compromettre `flutter analyze`.
      throw StateError('Not authenticated — cannot invoke createScenario');
    }

    final data = Map<String, dynamic>.from(parameters! as Map);
    final financials = <String, dynamic>{
      for (final key in _scenarioFinancialKeys) key: data[key],
    };
    final ref = _firestore.collection('investment_scenarios').doc();
    await ref.set(<String, dynamic>{
      'id': ref.id,
      'landlordId': uid,
      'name': data['name'],
      'notes': data['notes'],
      'schemaVersion': 1,
      'scenarioJson': financials,
      ...financials,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': null,
    });
    return _FakeCallableResult<T>({'scenarioId': ref.id} as T);
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
  late MockFirebaseAuth auth;
  late _RecordingFunctions functions;
  late FirestoreInvestmentScenarioRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _uid, isAnonymous: false, isEmailVerified: true),
    );
    functions = _RecordingFunctions(firestore, auth);
    repo = FirestoreInvestmentScenarioRepository(firestore, auth, functions);
  });

  /// Dépôt + Functions enregistreuses pour un utilisateur authentifié
  /// différent de celui de [setUp].
  ///
  /// Même Firestore fake (le « serveur » partagé entre acteurs simulés),
  /// mais sa propre paire auth/Functions : une app cliente réelle n'a jamais
  /// qu'un seul utilisateur signé à la fois, donc chaque acteur a la sienne
  /// plutôt que de partager celle de [setUp] — sinon `createScenario`
  /// écrirait toujours `landlordId: _uid`, quel que soit l'appelant.
  FirestoreInvestmentScenarioRepository repoFor(String uid) {
    final otherAuth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid),
    );
    return FirestoreInvestmentScenarioRepository(
      firestore,
      otherAuth,
      _RecordingFunctions(firestore, otherAuth),
    );
  }

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
      final anonAuth = MockFirebaseAuth(signedIn: false);
      final anonRepo = FirestoreInvestmentScenarioRepository(
        firestore,
        anonAuth,
        _RecordingFunctions(firestore, anonAuth),
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

      final otherRepo = repoFor('autre-landlord');
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
      final otherRepo = repoFor('autre-landlord');
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

    test('create() invoque la callable createScenario ; update() reste une '
        'écriture directe (pas de callable)', () async {
      final created = await createSample();

      expect(
        functions.invocations,
        hasLength(1),
        reason:
            'la règle `investment_scenarios/create` vaut `if false` '
            'depuis FEAT-056 (PR-2b) : la création doit passer par la '
            'Cloud Function createScenario, pas par un docRef.set direct. '
            'Si ce test casse parce que create() n\'appelle plus aucune '
            'callable, le transport est redevenu une écriture directe : '
            'mettre à jour la matrice de '
            'firestore_write_path_conformance_test.dart ET firestore.rules '
            '— ou, plus probablement, c\'est une régression à corriger.',
      );
      expect(functions.invocations.single.name, 'createScenario');

      functions.invocations.clear();
      await repo.update(created.copyWith(name: 'Renommé'));

      expect(
        functions.invocations,
        isEmpty,
        reason:
            'Si ce test casse côté update(), le transport a changé : '
            'mettre à jour la matrice de '
            'firestore_write_path_conformance_test.dart ET firestore.rules.',
      );
    });
  });
}
