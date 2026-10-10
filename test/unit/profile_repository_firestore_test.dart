/// Tests du dépôt CONCRET [FirestoreProfileRepository] — celui qui parle
/// réellement à Firestore.
///
/// `profile_repository_test.dart` teste le CONTRAT via un faux dépôt : il ne
/// touche jamais cette classe. C'est précisément cet angle mort qui a laissé
/// passer le bug du 2026-08-11 (sauvegarde du profil en échec apparent alors
/// que l'écriture réussissait).
library;

import 'package:easyrent/features/profile/data/profile_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'uid-profile-1';

/// Doc landlord complet, tel que le porte un compte réel après upgrade.
Map<String, dynamic> _seedDoc({DateTime? updatedAt}) => <String, dynamic>{
  'id': _uid,
  'email': 'qa@example.com',
  'fullName': 'QA Profil',
  'phone': null,
  'address': null,
  'isAnonymous': false,
  'subscriptionTier': 'free',
  'createdAt': DateTime.utc(2026, 1, 1),
  'updatedAt': updatedAt ?? DateTime.utc(2026, 1, 1),
  'rgpdConsentAt': DateTime.utc(2026, 1, 1),
  'rgpdConsentVersion': 'v3-2026-07',
  'deletedAt': null,
};

Future<FirestoreProfileRepository> _repo(FakeFirebaseFirestore db) async {
  await db.doc('landlords/$_uid').set(_seedDoc());
  return FirestoreProfileRepository(
    db,
    MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid)),
  );
}

void main() {
  group('FirestoreProfileRepository — update()', () {
    test('enregistre les champs et retourne le profil, sans lever', () async {
      // Le symptôme utilisateur : « Impossible de mettre à jour le profil »
      // alors que l'écriture passait. Ce test échouerait si `update()`
      // relançait sur la relecture.
      final db = FakeFirebaseFirestore();
      final repo = await _repo(db);

      final result = await repo.update(
        fullName: 'Thi Kim Chi Le',
        phone: '06 12 34 56 78',
        address: '12 rue de la Paix\n75001 Paris',
      );

      expect(result.fullName, 'Thi Kim Chi Le');
      expect(result.phone, '06 12 34 56 78');
      expect(result.address, '12 rue de la Paix\n75001 Paris');

      final saved = (await db.doc('landlords/$_uid').get()).data()!;
      expect(saved['address'], '12 rue de la Paix\n75001 Paris');
    });

    test(
      'n\'écrit PAS updatedAt — c\'est le trigger serveur qui le fait',
      () async {
        // GARDE-FOU. Le client écrivait `FieldValue.serverTimestamp()` sur
        // `updatedAt`. En compensation de latence, ce champ vaut `null` tant que
        // le serveur n'a pas confirmé : la relecture qui suit rendait alors un
        // doc dont `updatedAt` était nul, or `LandlordProfile` le déclare
        // `required DateTime` → `fromJson` levait, et l'utilisateur voyait une
        // erreur alors que ses données étaient bien enregistrées.
        //
        // `setUpdatedAtLandlords` (Cloud Function, déployée) est la source de
        // vérité de ce champ. Ce test échoue si quelqu'un le réécrit côté client.
        final db = FakeFirebaseFirestore();
        final repo = await _repo(db);
        final before = (await db.doc('landlords/$_uid').get())
            .data()!['updatedAt'];

        await repo.update(fullName: 'Nouveau Nom', phone: null, address: null);

        final after = (await db.doc('landlords/$_uid').get())
            .data()!['updatedAt'];
        expect(
          after,
          before,
          reason: 'le client ne doit pas toucher updatedAt (trigger serveur)',
        );
      },
    );

    test('trim et normalise les chaînes vides en null', () async {
      final db = FakeFirebaseFirestore();
      final repo = await _repo(db);

      await repo.update(fullName: '  Marie  ', phone: '   ', address: null);

      final saved = (await db.doc('landlords/$_uid').get()).data()!;
      expect(saved['fullName'], 'Marie');
      expect(saved['phone'], isNull);
    });
  });
}
