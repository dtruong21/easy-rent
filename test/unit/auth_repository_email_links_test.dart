import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

// Régression FEAT-024 : en VM (`flutter test`) comme sur mobile, `Uri.base`
// n'est pas http(s) — `Uri.base.origin` lève StateError. Les méthodes qui
// construisent des liens email doivent passer par le fallback
// `Env.publicAppUrl` au lieu de crasher (l'ancien code de
// sendPasswordResetEmail lisait `Uri.base.origin` directement).
void main() {
  test(
    'sendPasswordResetEmail hors contexte http(s) → complète sans StateError',
    () async {
      final repo = FirebaseAuthRepository(
        MockFirebaseAuth(),
        FakeFirebaseFirestore(),
      );

      await expectLater(
        repo.sendPasswordResetEmail('jean@exemple.fr'),
        completes,
      );
    },
  );
}
