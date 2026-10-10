# FEAT-060 — Avis in-app et notation sur les stores — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un formulaire « Donner mon avis » (web + mobile, stocké dans `support_requests`), la demande de note native des stores dans les apps après 15 jours d'usage, un bouton « Noter l'app » et, sur le web, une carte « Votre avis compte ».

**Architecture:** Spec : [`docs/superpowers/specs/2026-10-09-feedback-store-reviews-design.md`](../specs/2026-10-09-feedback-store-reviews-design.md). Les avis réutilisent `support_requests` (`kind: 'feedback'`, `rating`, `platform`) : règles Firestore étendues, aucune Cloud Function touchée. La sollicitation repose sur une fonction pure d'éligibilité, un stockage local de la dernière sollicitation et une interface `StoreReviewService` qui isole `in_app_review`. Un widget unique `AppReviewPrompt`, placé dans la vue « données » de l'Accueil, déclenche la fenêtre native (apps) ou affiche la carte (web).

**Tech Stack:** Flutter 3 / Dart ≥ 3.11, Riverpod 2.6, `cloud_firestore` (+ `fake_cloud_firestore` en test), `shared_preferences`, `in_app_review` 2.0.12 (pas de plugin web), règles Firestore testées sur l'émulateur (`@firebase/rules-unit-testing`, vitest).

## Global Constraints

- Les **demandes de support** (`support_requests` sans `kind`) gardent exactement leur comportement : mêmes champs, mêmes bornes (sujet 1-120, message 1-2000), `status == 'new'`, `createdAt == request.time`, lecture/modification/suppression refusées.
- Un **avis** = `support_requests` avec `kind: 'feedback'`, `rating` **entier 1 à 5**, `platform` ∈ `'web' | 'ios' | 'android'`, `subject` = `Avis — {note}/5` (texte fixe, non traduit), `message` = commentaire **0 à 2000** caractères. Comptes complets uniquement (`isFullyAuthed()`), `landlordId == request.auth.uid`.
- Éligibilité à la sollicitation : session `fullyAuthenticated` **et** `LandlordProfile.createdAt` ≤ maintenant − **15 jours** **et** au moins **un bien** **et** dernière sollicitation sur l'appareil il y a plus de **120 jours** (ou jamais).
- **Conformité stores** : la fenêtre native n'est jamais précédée d'une question ; aucune note du formulaire ne renvoie vers le store. Les deux canaux restent indépendants.
- Apps (`isStoreApp`) : fenêtre native via `in_app_review`, jamais la carte. Web : la carte, jamais la fenêtre native ni « Noter l'app ».
- « Noter l'app » : Android toujours ; iOS seulement si le dart-define `APP_STORE_ID` est non vide.
- Le prompt vit dans la vue « données » de l'Accueil (après la checklist de démarrage) : un bailleur encore dans la checklist n'est pas sollicité — conséquence voulue.
- Textes FR et EN (`lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb` = gabarit avec `@`descriptions) ; `flutter gen-l10n` après modification.
- Outillage : `export PATH=/opt/homebrew/bin:$PATH` ; `flutter analyze` sans aucun problème ; `dart format` sur les fichiers modifiés (jamais `dart format .` : `build/` contient des fichiers en lecture seule) ; ne jamais committer `*.g.dart`, `*.freezed.dart`, `build/`, `firebase.altports.local.json` ; ne jamais `git add -A`. Un build Android local réécrit `android/gradle.properties` : `git checkout -- android/gradle.properties`.
- Tests de règles : `npx -y firebase-tools@13 emulators:exec --config firebase.altports.local.json --only firestore,storage --project demo-easyrent "npm --prefix functions run test:rules:inner"` depuis la racine (ports par défaut occupés par un autre projet).
- Branche `feat/060-feedback-reviews` (déjà créée, spec commitée). Commits en français, suffixés de `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

## File Structure

| Fichier | Rôle |
|---|---|
| `firestore.rules` (modif) | branche « avis » de `support_requests` |
| `functions/rules-tests/firestore_rules.test.ts` (modif) | tests support + avis |
| `lib/features/support/domain/support_submit_error.dart` (modif) | `ratingRequired` |
| `lib/features/support/data/support_repository.dart` (modif) | `submitFeedback(...)` |
| `lib/features/support/application/feedback_controller.dart` (nouveau) | validation + envoi d'un avis |
| `lib/features/support/presentation/feedback_page.dart` (nouveau) | `/profile/feedback` |
| `lib/features/support/presentation/widgets/feedback_form.dart` (nouveau) | étoiles + commentaire |
| `lib/core/router/app_router.dart` (modif) | route `feedback` sous `/profile` |
| `lib/features/profile/presentation/profile_page.dart` (modif) | tuiles « Donner mon avis » et « Noter l'app » |
| `lib/core/config/env.dart` (modif) | `Env.appStoreId` |
| `lib/features/app_review/domain/review_eligibility.dart` (nouveau) | fonction pure + constantes |
| `lib/features/app_review/data/review_solicitation_storage.dart` (nouveau) | date de dernière sollicitation (`SharedPreferences`) |
| `lib/features/app_review/data/store_review_service.dart` (nouveau) | interface + impl `in_app_review` + `canRateInStore` |
| `lib/features/app_review/application/review_eligibility_provider.dart` (nouveau) | éligibilité branchée sur la session, le profil, les biens |
| `lib/features/app_review/presentation/app_review_prompt.dart` (nouveau) | fenêtre native (apps) ou carte (web) |
| `lib/features/dashboard/presentation/dashboard_page.dart` (modif) | insère `AppReviewPrompt` dans `_DataView` |
| Docs | `docs/state/schema/account.md`, `docs/state/routes/account.md`, `docs/state/FEATURES.md`, `docs/state/CHANGELOG.md`, `docs/STORE_COMPLIANCE.md`, `docs/MOBILE.md`, `dart-defines.prod.example.json` |

---

### Task 1: Règles Firestore — branche « avis » de `support_requests`

**Files:**
- Modify: `firestore.rules` (bloc `match /support_requests/{id}`, ~l.483-501)
- Test: `functions/rules-tests/firestore_rules.test.ts` (nouveau `describe` en fin de fichier)
- Modify: `docs/state/schema/account.md` (section `support_requests/{id}`)

**Interfaces:**
- Produces: contrat de données d'un avis (cf. Global Constraints), utilisé par la Task 2.

- [ ] **Step 1: Écrire les tests qui échouent** — en tête de `functions/rules-tests/firestore_rules.test.ts`, ajouter aux imports :

```ts
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";
```

puis, en fin de fichier :

```ts
describe("support_requests — support (FEAT-025) et avis (FEAT-060)", () => {
  const now = () => firebase.firestore.FieldValue.serverTimestamp();
  const support = (over: Record<string, unknown> = {}) => ({
    landlordId: LANDLORD_A,
    email: "a@example.com",
    subject: "Problème",
    message: "La quittance ne se génère pas.",
    appVersion: "1.0.0+1",
    appEnv: "staging",
    status: "new",
    createdAt: now(),
    ...over,
  });
  const feedback = (over: Record<string, unknown> = {}) => ({
    ...support({subject: "Avis — 4/5", message: "Très pratique."}),
    kind: "feedback",
    rating: 4,
    platform: "web",
    ...over,
  });
  const create = (db: firebase.firestore.Firestore, data: object) =>
    db.collection("support_requests").add(data);
  const asAnonymous = () =>
    env
      .authenticatedContext("anon-060", {
        firebase: {sign_in_provider: "anonymous"},
      })
      .firestore();

  it("demande de support valide → acceptée (inchangé)", async () => {
    await assertSucceeds(create(asOwnerA(), support()));
  });
  it("demande de support au message vide → refusée (inchangé)", async () => {
    await assertFails(create(asOwnerA(), support({message: ""})));
  });
  it("avis valide → accepté", async () => {
    await assertSucceeds(create(asOwnerA(), feedback()));
  });
  it("avis sans commentaire → accepté", async () => {
    await assertSucceeds(create(asOwnerA(), feedback({message: ""})));
  });
  it("avis de 1 et de 5 étoiles → acceptés (bornes)", async () => {
    await assertSucceeds(create(asOwnerA(), feedback({rating: 1})));
    await assertSucceeds(create(asOwnerA(), feedback({rating: 5})));
  });
  for (const rating of [0, 6, 3.5, "4"]) {
    it(`avis noté ${JSON.stringify(rating)} → refusé`, async () => {
      await assertFails(create(asOwnerA(), feedback({rating})));
    });
  }
  it("avis sans note → refusé", async () => {
    const data: Record<string, unknown> = feedback();
    delete data.rating;
    await assertFails(create(asOwnerA(), data));
  });
  it("kind inconnu → refusé", async () => {
    await assertFails(create(asOwnerA(), feedback({kind: "bug"})));
  });
  it("plateforme inconnue ou absente → refusée", async () => {
    await assertFails(create(asOwnerA(), feedback({platform: "windows"})));
    const data: Record<string, unknown> = feedback();
    delete data.platform;
    await assertFails(create(asOwnerA(), data));
  });
  it("commentaire > 2000 caractères → refusé", async () => {
    await assertFails(
      create(asOwnerA(), feedback({message: "x".repeat(2001)})),
    );
  });
  it("avis au nom d'un autre compte → refusé", async () => {
    await assertFails(create(asOtherB(), feedback()));
  });
  it("compte anonyme → refusé", async () => {
    await assertFails(
      create(asAnonymous(), feedback({landlordId: "anon-060"})),
    );
  });
  it("lecture d'un avis → refusée", async () => {
    await assertFails(
      asOwnerA().collection("support_requests").doc("x").get(),
    );
  });
});
```

(Si `firebase/compat` ne fournit pas le sentinel attendu par le contexte de test, utiliser l'équivalent exposé par `@firebase/rules-unit-testing` / le SDK installé et le noter dans le rapport — `createdAt` doit valoir l'heure serveur pour satisfaire `createdAt == request.time`.)

- [ ] **Step 2: Vérifier qu'ils échouent**

Run (depuis la racine) : `npx -y firebase-tools@13 emulators:exec --config firebase.altports.local.json --only firestore,storage --project demo-easyrent "npm --prefix functions run test:rules:inner"`
Expected: les cas « avis valide / sans commentaire / bornes » échouent (règle actuelle : pas de branche avis, message non vide exigé) ; les cas « support » passent.

- [ ] **Step 3: Implémenter** — dans `firestore.rules`, remplacer le bloc `match /support_requests/{id} { … }` par :

```
    match /support_requests/{id} {
      allow get, list: if false;   // l'utilisateur ne relit pas ses demandes en V1

      // Demande de support (FEAT-025) : pas de `kind`, message non vide.
      function isSupportRequest(d) {
        return !('kind' in d) && d.message.size() > 0;
      }

      // Avis (FEAT-060) : note entière 1-5, plateforme connue, commentaire
      // facultatif. Aucun renvoi vers les stores selon la note.
      function isFeedback(d) {
        return d.kind == 'feedback'
          && d.rating is int
          && d.rating >= 1
          && d.rating <= 5
          && d.platform in ['web', 'ios', 'android'];
      }

      allow create: if isFullyAuthed()
        && request.resource.data.landlordId == request.auth.uid
        && request.resource.data.email is string
        && request.resource.data.email.size() > 0
        && request.resource.data.subject is string
        && request.resource.data.subject.size() > 0
        && request.resource.data.subject.size() <= 120
        && request.resource.data.message is string
        && request.resource.data.message.size() <= 2000
        && request.resource.data.appVersion is string
        && request.resource.data.appEnv is string
        && request.resource.data.status == 'new'
        && request.resource.data.createdAt == request.time
        && (isSupportRequest(request.resource.data)
            || isFeedback(request.resource.data));

      allow update, delete: if false;
    }
```

- [ ] **Step 4: Vérifier que les tests passent**

Run : même commande qu'au Step 2.
Expected: tous les tests de règles PASS (anciens et nouveaux).

- [ ] **Step 5: Documenter le schéma** — dans `docs/state/schema/account.md`, section `support_requests/{id}` : ajouter au tableau les lignes `kind` (string, `'feedback'` pour un avis ; absent = demande de support, FEAT-060), `rating` (int 1-5, avis uniquement), `platform` (string `web`/`ios`/`android`, avis uniquement) ; préciser que `message` peut être vide pour un avis ; compléter « Règles Firestore » avec la branche avis.

- [ ] **Step 6: Commit**

```bash
git add firestore.rules functions/rules-tests/firestore_rules.test.ts docs/state/schema/account.md
git commit -m "feat(rules): avis in-app dans support_requests (FEAT-060)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Envoi d'un avis — dépôt et contrôleur

**Files:**
- Modify: `lib/features/support/domain/support_submit_error.dart`
- Modify: `lib/features/support/presentation/support_submit_error_l10n.dart`
- Modify: `lib/features/support/data/support_repository.dart`
- Create: `lib/features/support/application/feedback_controller.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Modify: toute classe de test qui `implements SupportRepository` (`grep -rn "implements SupportRepository" test`)
- Test: `test/unit/support_repository_firestore_test.dart` (ajout), `test/unit/feedback_controller_test.dart` (nouveau)

**Interfaces:**
- Consumes: contrat d'avis (Task 1).
- Produces: `SupportSubmitError.ratingRequired` ; `const int kFeedbackRatingMin = 1; const int kFeedbackRatingMax = 5;` ; `SupportRepository.submitFeedback({required int rating, required String comment, required String appVersion, required String appEnv, required String platform})` ; `class FeedbackController extends StateNotifier<SupportRequestState>` avec `Future<void> submit({required int? rating, required String comment, required String appVersion, required String appEnv, required String platform})` et `void reset()` ; `final feedbackControllerProvider = StateNotifierProvider.autoDispose<FeedbackController, SupportRequestState>`.

- [ ] **Step 1: Écrire les tests qui échouent**

Dans `test/unit/support_repository_firestore_test.dart`, ajouter un groupe (même montage `FakeFirebaseFirestore` + `MockFirebaseAuth` que le test existant) :

```dart
  group('FirestoreSupportRepository.submitFeedback', () {
    test('écrit un avis conforme aux rules (kind, rating, platform, sujet)',
        () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: _uid,
          email: _email,
          isAnonymous: false,
          isEmailVerified: true,
        ),
      );
      final repo = FirestoreSupportRepository(firestore, auth);

      await repo.submitFeedback(
        rating: 4,
        comment: '',
        appVersion: '1.0.0+42',
        appEnv: 'dev',
        platform: 'web',
      );

      final docs = (await firestore.collection('support_requests').get()).docs;
      expect(docs, hasLength(1));
      final data = docs.single.data();
      expect(data['landlordId'], _uid);
      expect(data['email'], _email);
      expect(data['kind'], 'feedback');
      expect(data['rating'], 4);
      expect(data['platform'], 'web');
      expect(data['subject'], 'Avis — 4/5');
      expect(data['message'], '');
      expect(data['status'], 'new');
      expect(data['createdAt'], isA<Timestamp>());
      expect(data.keys.toSet(), {
        'landlordId', 'email', 'subject', 'message', 'appVersion',
        'appEnv', 'status', 'createdAt', 'kind', 'rating', 'platform',
      });
    });
  });
```

Créer `test/unit/feedback_controller_test.dart` :

```dart
import 'package:easyrent/features/support/application/feedback_controller.dart';
import 'package:easyrent/features/support/data/support_repository.dart';
import 'package:easyrent/features/support/domain/support_request_state.dart';
import 'package:easyrent/features/support/domain/support_submit_error.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements SupportRepository {
  final List<Map<String, Object>> feedbacks = [];
  Object? error;

  @override
  Future<void> submit({
    required String subject,
    required String message,
    required String appVersion,
    required String appEnv,
  }) async {}

  @override
  Future<void> submitFeedback({
    required int rating,
    required String comment,
    required String appVersion,
    required String appEnv,
    required String platform,
  }) async {
    if (error != null) throw error!;
    feedbacks.add({'rating': rating, 'comment': comment, 'platform': platform});
  }
}

void main() {
  late _FakeRepo repo;
  late FeedbackController controller;
  setUp(() {
    repo = _FakeRepo();
    controller = FeedbackController(repo);
  });
  tearDown(() => controller.dispose());

  Future<void> send({int? rating = 4, String comment = '  Super  '}) =>
      controller.submit(
        rating: rating,
        comment: comment,
        appVersion: '1.0.0+1',
        appEnv: 'dev',
        platform: 'ios',
      );

  test('note absente → erreur ratingRequired, rien envoyé', () async {
    await send(rating: null);
    expect(
      controller.state,
      SupportRequestState.error(message: SupportSubmitError.ratingRequired.name),
    );
    expect(repo.feedbacks, isEmpty);
  });

  test('note hors 1-5 → erreur ratingRequired', () async {
    await send(rating: 0);
    await send(rating: 6);
    expect(repo.feedbacks, isEmpty);
  });

  test('commentaire > 2000 → erreur messageTooLong', () async {
    await send(comment: 'x' * 2001);
    expect(
      controller.state,
      SupportRequestState.error(message: SupportSubmitError.messageTooLong.name),
    );
  });

  test('avis valide → envoyé (commentaire nettoyé), succès', () async {
    await send();
    expect(repo.feedbacks.single,
        {'rating': 4, 'comment': 'Super', 'platform': 'ios'});
    expect(controller.state, const SupportRequestState.success());
  });

  test('commentaire vide autorisé', () async {
    await send(comment: '   ');
    expect(repo.feedbacks.single['comment'], '');
  });

  test('échec du dépôt → erreur sendFailed', () async {
    repo.error = StateError('réseau');
    await send();
    expect(
      controller.state,
      SupportRequestState.error(message: SupportSubmitError.sendFailed.name),
    );
  });
}
```

- [ ] **Step 2: Vérifier qu'ils échouent**

Run: `flutter test test/unit/support_repository_firestore_test.dart test/unit/feedback_controller_test.dart`
Expected: échec de compilation (`submitFeedback`, `feedback_controller.dart`, `ratingRequired` absents).

- [ ] **Step 3: Implémenter**

`support_submit_error.dart` — ajouter, après `messageTooLong` :

```dart
  /// Aucune note (ou note hors 1-5) pour un avis (FEAT-060).
  ratingRequired,
```

et en tête de fichier, sous les bornes existantes :

```dart
/// Bornes de la note d'un avis (FEAT-060) — mêmes valeurs que les rules.
const int kFeedbackRatingMin = 1;
const int kFeedbackRatingMax = 5;
```

`support_submit_error_l10n.dart` — ajouter au `switch` :

```dart
      SupportSubmitError.ratingRequired => l10n.feedbackRatingRequiredError,
```

l10n — `app_en.arb` (avec description) et `app_fr.arb` :

```json
  "feedbackRatingRequiredError": "Please choose a rating.",
  "@feedbackRatingRequiredError": {
    "description": "FEAT-060 — Feedback form validation error: no star rating selected."
  },
```

```json
  "feedbackRatingRequiredError": "Choisissez une note.",
```

`support_repository.dart` — dans l'interface :

```dart
  /// Écrit un avis (FEAT-060) dans `support_requests/{auto}` :
  /// `kind: 'feedback'`, [rating] 1-5, [comment] 0-2000 caractères (peut
  /// être vide), [platform] `web` / `ios` / `android`. Sujet fixe
  /// « Avis — {note}/5 ». Create-only, jamais relu.
  Future<void> submitFeedback({
    required int rating,
    required String comment,
    required String appVersion,
    required String appEnv,
    required String platform,
  });
```

et dans `FirestoreSupportRepository` :

```dart
  @override
  Future<void> submitFeedback({
    required int rating,
    required String comment,
    required String appVersion,
    required String appEnv,
    required String platform,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('SupportRepository.submitFeedback requires a user.');
    }
    _log.info('submitFeedback() rating=$rating platform=$platform');

    await _firestore.collection('support_requests').add({
      'landlordId': user.uid,
      'email': user.email,
      'subject': 'Avis — $rating/5',
      'message': comment,
      'appVersion': appVersion,
      'appEnv': appEnv,
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
      'kind': 'feedback',
      'rating': rating,
      'platform': platform,
    });
  }
```

`feedback_controller.dart` :

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/support_repository.dart';
import '../domain/support_request_state.dart';
import '../domain/support_submit_error.dart';

final _log = Logger('FeedbackController');

/// Contrôle le formulaire « Donner mon avis » (FEAT-060). Même état que
/// « Nous contacter » ([SupportRequestState]) ; validation bornée sur les
/// mêmes valeurs que les rules `support_requests` (branche avis).
class FeedbackController extends StateNotifier<SupportRequestState> {
  FeedbackController(this._repository)
    : super(const SupportRequestState.idle());

  final SupportRepository _repository;

  Future<void> submit({
    required int? rating,
    required String comment,
    required String appVersion,
    required String appEnv,
    required String platform,
  }) async {
    if (rating == null ||
        rating < kFeedbackRatingMin ||
        rating > kFeedbackRatingMax) {
      state = SupportRequestState.error(
        message: SupportSubmitError.ratingRequired.name,
      );
      return;
    }
    final trimmed = comment.trim();
    if (trimmed.length > kSupportMessageMaxLength) {
      state = SupportRequestState.error(
        message: SupportSubmitError.messageTooLong.name,
      );
      return;
    }

    state = const SupportRequestState.submitting();
    try {
      await _repository.submitFeedback(
        rating: rating,
        comment: trimmed,
        appVersion: appVersion,
        appEnv: appEnv,
        platform: platform,
      );
      state = const SupportRequestState.success();
      _log.info('Avis envoyé');
    } catch (e, st) {
      _log.warning('Erreur envoi avis', e, st);
      state = SupportRequestState.error(
        message: SupportSubmitError.sendFailed.name,
      );
    }
  }

  void reset() => state = const SupportRequestState.idle();
}

final feedbackControllerProvider =
    StateNotifierProvider.autoDispose<FeedbackController, SupportRequestState>(
      (ref) => FeedbackController(ref.watch(supportRepositoryProvider)),
    );
```

Puis, dans chaque classe de test qui `implements SupportRepository`, ajouter une implémentation vide de `submitFeedback` (même signature) pour que la suite compile.

- [ ] **Step 4: Vérifier**

Run: `flutter gen-l10n && flutter test test/unit/support_repository_firestore_test.dart test/unit/feedback_controller_test.dart && dart format lib/features/support test/unit && flutter analyze lib/features/support test/unit`
Expected: PASS ; « No issues found! ».

- [ ] **Step 5: Commit**

```bash
git add lib/features/support lib/l10n/app_en.arb lib/l10n/app_fr.arb test/unit/support_repository_firestore_test.dart test/unit/feedback_controller_test.dart
git add <fichiers de test modifiés pour submitFeedback>
git commit -m "feat(support): envoi d'un avis in-app (FEAT-060)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Écran « Donner mon avis » et entrée du profil

**Files:**
- Create: `lib/features/support/presentation/feedback_page.dart`
- Create: `lib/features/support/presentation/widgets/feedback_form.dart`
- Modify: `lib/core/router/app_router.dart` (route `feedback` juste après `support`, ~l.612-619)
- Modify: `lib/features/profile/presentation/profile_page.dart` (tuile après `tile_support`, ~l.129-136)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Test: `test/widget/feedback_page_test.dart` (nouveau), `test/widget/profile_page_test.dart` (ajout)

**Interfaces:**
- Consumes: `feedbackControllerProvider`, `SupportRequestState`, `SupportSubmitError.fromCode`, `SupportSubmitErrorL10n.message` (Task 2) ; `appInfoProvider` (`lib/core/app_info/app_info_provider.dart`), `Env.appEnv`, `AppAppBar(fallbackRoute: '/profile')`.
- Produces: route `/profile/feedback` ; `String feedbackPlatform()` (dans `feedback_form.dart`) ; clés `tile_feedback`, `btn_feedback_star_1`…`btn_feedback_star_5`, `field_feedback_comment`, `btn_feedback_submit`, `snackbar_feedback_success`.

- [ ] **Step 1: Textes** — ajouter (EN avec descriptions « FEAT-060 — … », FR) :

| Clé | EN | FR |
|---|---|---|
| `profileHubFeedbackTile` | Give feedback | Donner mon avis |
| `feedbackPageTitle` | Your feedback | Votre avis |
| `feedbackPageIntro` | How do you find Baillan? Your rating and comments help us improve it. | Que pensez-vous de Baillan ? Votre note et vos remarques nous aident à l'améliorer. |
| `feedbackRatingLabel` | Your rating | Votre note |
| `feedbackStarSemantics` (placeholder `count` int) | {count} out of 5 | {count} sur 5 |
| `feedbackCommentLabel` | Comment (optional) | Commentaire (facultatif) |
| `feedbackSubmitButton` | Send | Envoyer |
| `feedbackSuccessSnackbar` | Thank you for your feedback! | Merci pour votre avis ! |

- [ ] **Step 2: Écrire les tests qui échouent** — `test/widget/feedback_page_test.dart` (s'inspirer du montage de `test/widget/support_page_test.dart` : `ProviderScope` + `MaterialApp` localisé `fr`) :

```dart
// Montage : ProviderScope(overrides: [
//   supportRepositoryProvider.overrideWithValue(fakeRepo),
//   appInfoProvider.overrideWith(...)  // comme support_page_test.dart
// ], child: MaterialApp(..., home: const FeedbackPage()))
// fakeRepo : même _FakeRepo que test/unit/feedback_controller_test.dart.

testWidgets('« Envoyer » désactivé tant qu\'aucune note', (tester) async {
  // pump
  final btn = tester.widget<FilledButton>(
    find.byKey(const Key('btn_feedback_submit')),
  );
  expect(btn.onPressed, isNull);
});

testWidgets('4 étoiles + commentaire → avis envoyé et remerciement',
    (tester) async {
  // pump
  await tester.tap(find.byKey(const Key('btn_feedback_star_4')));
  await tester.enterText(
    find.byKey(const Key('field_feedback_comment')), 'Pratique');
  await tester.pump();
  await tester.tap(find.byKey(const Key('btn_feedback_submit')));
  await tester.pumpAndSettle();
  expect(fakeRepo.feedbacks.single['rating'], 4);
  expect(fakeRepo.feedbacks.single['comment'], 'Pratique');
  expect(find.byKey(const Key('snackbar_feedback_success')), findsOneWidget);
});

testWidgets('échec d\'envoi → message d\'erreur, formulaire conservé',
    (tester) async {
  fakeRepo.error = StateError('réseau');
  // pump, tap star 2, tap submit, pumpAndSettle
  expect(find.text(l10n.supportFormSendFailedError), findsOneWidget);
  expect(find.byKey(const Key('btn_feedback_submit')), findsOneWidget);
});
```

Dans `test/widget/profile_page_test.dart`, ajouter un test : la tuile `tile_feedback` est présente et, au tap, mène à `/profile/feedback` (reprendre le schéma du test existant de `tile_support` s'il existe ; sinon vérifier seulement la présence et le libellé « Donner mon avis »).

- [ ] **Step 3: Vérifier qu'ils échouent**

Run: `flutter gen-l10n && flutter test test/widget/feedback_page_test.dart test/widget/profile_page_test.dart`
Expected: échec (fichiers / tuile absents).

- [ ] **Step 4: Implémenter**

`feedback_form.dart` :

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/app_info/app_info_provider.dart';
import '../../../../core/config/env.dart';
import '../../../../core/i18n/l10n_extensions.dart';
import '../../application/feedback_controller.dart';
import '../../domain/support_request_state.dart';
import '../../domain/support_submit_error.dart';
import '../support_submit_error_l10n.dart';

/// Plateforme d'origine d'un avis (`support_requests.platform`).
String feedbackPlatform() {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
}

/// Formulaire « Donner mon avis » (FEAT-060) : note 1-5 obligatoire,
/// commentaire facultatif. Aucun renvoi vers les stores selon la note.
class FeedbackForm extends ConsumerStatefulWidget {
  const FeedbackForm({super.key});

  @override
  ConsumerState<FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends ConsumerState<FeedbackForm> {
  final _commentController = TextEditingController();
  int? _rating;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final appVersion = ref.read(appInfoProvider).maybeWhen(
      data: (info) => '${info.version}+${info.buildNumber}',
      orElse: () => 'inconnue',
    );
    await ref.read(feedbackControllerProvider.notifier).submit(
      rating: _rating,
      comment: _commentController.text,
      appVersion: appVersion,
      appEnv: Env.appEnv,
      platform: feedbackPlatform(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(feedbackControllerProvider);
    final submitting = state is SupportRequestStateSubmitting ||
        state.maybeWhen(submitting: () => true, orElse: () => false);

    ref.listen<SupportRequestState>(feedbackControllerProvider, (_, next) {
      next.whenOrNull(
        success: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const Key('snackbar_feedback_success'),
              content: Text(l10n.feedbackSuccessSnackbar),
            ),
          );
          ref.read(feedbackControllerProvider.notifier).reset();
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/profile');
          }
        },
      );
    });

    final error = state.maybeWhen(
      error: (code) => SupportSubmitError.fromCode(code).message(context),
      orElse: () => null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.feedbackRatingLabel,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                key: Key('btn_feedback_star_$i'),
                tooltip: l10n.feedbackStarSemantics(i),
                icon: Icon(
                  _rating != null && i <= _rating!
                      ? Icons.star
                      : Icons.star_border,
                ),
                color: Theme.of(context).colorScheme.primary,
                onPressed: submitting ? null : () => setState(() => _rating = i),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('field_feedback_comment'),
          controller: _commentController,
          maxLength: kSupportMessageMaxLength,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(labelText: l10n.feedbackCommentLabel),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('btn_feedback_submit'),
          onPressed: _rating == null || submitting ? null : _submit,
          child: Text(l10n.feedbackSubmitButton),
        ),
      ],
    );
  }
}
```

(Adapter la détection de `submitting` à l'API générée par freezed pour `SupportRequestState` — reprendre exactement la forme utilisée dans `profile_support_form.dart` ; supprimer la variante qui ne compile pas.)

`feedback_page.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info/app_info_provider.dart';
import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import 'widgets/feedback_form.dart';

/// Page `/profile/feedback` — « Donner mon avis » (FEAT-060).
class FeedbackPage extends ConsumerWidget {
  const FeedbackPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Même réchauffage qu'en SupportPage : appInfoProvider lu en synchrone
    // au submit.
    ref.watch(appInfoProvider);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppAppBar(title: l10n.feedbackPageTitle, fallbackRoute: '/profile'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.feedbackPageIntro,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                const FeedbackForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

`app_router.dart` — après la route `support` :

```dart
                  GoRoute(
                    path: 'feedback',
                    pageBuilder: (context, state) => appPage(
                      key: state.pageKey,
                      child: const FeedbackPage(),
                      transition: AppTransition.standard,
                    ),
                  ),
```

(+ import `../../features/support/presentation/feedback_page.dart` à sa place.)

`profile_page.dart` — après la `ListTile` `tile_support` :

```dart
            ListTile(
              key: const Key('tile_feedback'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.rate_review_outlined),
              title: Text(l10n.profileHubFeedbackTile),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/feedback'),
            ),
```

et compléter le commentaire de tête du fichier (liste des sous-pages) par `/profile/feedback : « Donner mon avis » (FEAT-060)`.

- [ ] **Step 5: Vérifier**

Run: `flutter gen-l10n && flutter test test/widget/feedback_page_test.dart test/widget/profile_page_test.dart test/widget/support_page_test.dart && dart format lib test && flutter analyze`
Expected: PASS ; « No issues found! ».

- [ ] **Step 6: Commit**

```bash
git add lib/features/support/presentation lib/core/router/app_router.dart lib/features/profile/presentation/profile_page.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/widget/feedback_page_test.dart test/widget/profile_page_test.dart
git commit -m "feat(support): écran « Donner mon avis » et entrée du profil (FEAT-060)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Sollicitation — éligibilité, stockage, service store, « Noter l'app »

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock` (`flutter pub add in_app_review:^2.0.12`)
- Modify: `lib/core/config/env.dart` (`appStoreId`, après les clés RevenueCat si présentes, sinon après `subscriptionsEnabled`)
- Create: `lib/features/app_review/domain/review_eligibility.dart`
- Create: `lib/features/app_review/data/review_solicitation_storage.dart`
- Create: `lib/features/app_review/data/store_review_service.dart`
- Create: `lib/features/app_review/application/review_eligibility_provider.dart`
- Modify: `lib/features/profile/presentation/profile_page.dart` (tuile `tile_rate_app` après `tile_feedback`)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb` (`profileHubRateAppTile` : « Rate the app » / « Noter l'app »)
- Test: `test/unit/review_eligibility_test.dart`, `test/unit/review_solicitation_storage_test.dart`, `test/unit/store_review_service_test.dart` (nouveaux), `test/widget/profile_page_test.dart` (ajout)

**Interfaces:**
- Consumes: `isStoreApp`, `debugIsStoreAppOverride` (`lib/core/config/store_billing.dart`) ; `sessionStateProvider`, `SessionState` ; `landlordProfileProvider` (`LandlordProfile.createdAt`) ; `propertiesListItemsProvider` (`lib/features/properties/application/properties_list_provider.dart`).
- Produces:
  - `const Duration kReviewMinAccountAge = Duration(days: 15);` `const Duration kReviewSolicitationInterval = Duration(days: 120);` `bool isReviewSolicitationEligible({required bool fullyAuthenticated, required DateTime accountCreatedAt, required bool hasProperty, required DateTime? lastSolicitedAt, required DateTime now})`.
  - `class ReviewSolicitationStorage { Future<DateTime?> readLastSolicitedAt(); Future<void> markSolicited(DateTime at); }` + `final reviewSolicitationStorageProvider = Provider<ReviewSolicitationStorage>`.
  - `abstract interface class StoreReviewService { Future<bool> isAvailable(); Future<void> requestReview(); Future<void> openStoreListing({String? appStoreId}); }` + `class InAppReviewStoreReviewService implements StoreReviewService` + `final storeReviewServiceProvider = Provider<StoreReviewService>` + `bool canRateInStore({required bool storeApp, required TargetPlatform platform, String appStoreId = Env.appStoreId})`.
  - `final reviewClockProvider = Provider<DateTime Function()>((_) => DateTime.now);` `final reviewEligibilityProvider = FutureProvider.autoDispose<bool>`.

- [ ] **Step 1: Dépendance** — `flutter pub add in_app_review:^2.0.12`. (Le paquet n'a pas de plugin web : rien à neutraliser côté web ; ne l'appeler que si `isStoreApp`.)

- [ ] **Step 2: Écrire les tests qui échouent**

`test/unit/review_eligibility_test.dart` :

```dart
import 'package:easyrent/features/app_review/domain/review_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 9, 12);
  bool eligible({
    bool full = true,
    Duration age = const Duration(days: 30),
    bool hasProperty = true,
    Duration? sinceLast,
  }) => isReviewSolicitationEligible(
    fullyAuthenticated: full,
    accountCreatedAt: now.subtract(age),
    hasProperty: hasProperty,
    lastSolicitedAt: sinceLast == null ? null : now.subtract(sinceLast),
    now: now,
  );

  test('cas nominal → éligible', () => expect(eligible(), isTrue));
  test('compte non complet → non', () => expect(eligible(full: false), isFalse));
  test('compte de 14 jours → non', () {
    expect(eligible(age: const Duration(days: 14)), isFalse);
  });
  test('compte de 15 jours pile → oui (borne incluse)', () {
    expect(eligible(age: kReviewMinAccountAge), isTrue);
  });
  test('aucun bien → non', () => expect(eligible(hasProperty: false), isFalse));
  test('sollicité il y a 119 jours → non', () {
    expect(eligible(sinceLast: const Duration(days: 119)), isFalse);
  });
  test('sollicité il y a 120 jours pile → oui (borne incluse)', () {
    expect(eligible(sinceLast: kReviewSolicitationInterval), isTrue);
  });
  test('jamais sollicité → oui', () => expect(eligible(sinceLast: null), isTrue));
}
```

`test/unit/review_solicitation_storage_test.dart` :

```dart
import 'package:easyrent/features/app_review/data/review_solicitation_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('jamais sollicité → null', () async {
    expect(await ReviewSolicitationStorage().readLastSolicitedAt(), isNull);
  });

  test('markSolicited puis lecture → même instant', () async {
    final at = DateTime.utc(2026, 10, 9, 8, 30);
    await ReviewSolicitationStorage().markSolicited(at);
    expect(await ReviewSolicitationStorage().readLastSolicitedAt(), at);
  });

  test('valeur illisible → null (jamais d\'exception)', () async {
    SharedPreferences.setMockInitialValues({'review_solicited_at': 'n/a'});
    expect(await ReviewSolicitationStorage().readLastSolicitedAt(), isNull);
  });
}
```

`test/unit/store_review_service_test.dart` :

```dart
import 'package:easyrent/features/app_review/data/store_review_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web / hors app store → jamais', () {
    expect(
      canRateInStore(storeApp: false, platform: TargetPlatform.android),
      isFalse,
    );
  });
  test('Android app store → oui, même sans identifiant App Store', () {
    expect(
      canRateInStore(storeApp: true, platform: TargetPlatform.android),
      isTrue,
    );
  });
  test('iOS sans APP_STORE_ID → non', () {
    expect(
      canRateInStore(storeApp: true, platform: TargetPlatform.iOS),
      isFalse,
    );
  });
  test('iOS avec identifiant → oui', () {
    expect(
      canRateInStore(
        storeApp: true,
        platform: TargetPlatform.iOS,
        appStoreId: '1234567890',
      ),
      isTrue,
    );
  });
}
```

Dans `test/widget/profile_page_test.dart` : tuile `tile_rate_app` absente par défaut (web, `debugIsStoreAppOverride = false` dans la config de test) ; présente avec `debugIsStoreAppOverride = true` et `debugDefaultTargetPlatformOverride = TargetPlatform.android` (les remettre à `false` / `null` en `addTearDown`) ; au tap, un faux `StoreReviewService` (via `storeReviewServiceProvider.overrideWithValue`) reçoit `openStoreListing(appStoreId: null)`.

- [ ] **Step 3: Vérifier qu'ils échouent**

Run: `flutter test test/unit/review_eligibility_test.dart test/unit/review_solicitation_storage_test.dart test/unit/store_review_service_test.dart test/widget/profile_page_test.dart`
Expected: échec de compilation.

- [ ] **Step 4: Implémenter**

`env.dart` :

```dart
  /// FEAT-060 — identifiant numérique de l'app dans l'App Store (App Store
  /// Connect → Informations sur l'app → Apple ID). Requis pour « Noter
  /// l'app » sur iOS ; vide → bouton masqué sur iOS.
  static const String appStoreId = String.fromEnvironment('APP_STORE_ID');
```

`review_eligibility.dart` :

```dart
/// Sollicitation d'avis (FEAT-060) : demande de note native dans les apps,
/// carte « Votre avis compte » sur le web.
library;

/// Ancienneté minimale du compte complet avant toute sollicitation.
const Duration kReviewMinAccountAge = Duration(days: 15);

/// Délai minimal entre deux sollicitations automatiques sur un appareil.
const Duration kReviewSolicitationInterval = Duration(days: 120);

/// PURE — vrai si l'on peut solliciter un avis maintenant : compte complet,
/// créé depuis au moins [kReviewMinAccountAge], au moins un bien, et aucune
/// sollicitation depuis [kReviewSolicitationInterval] sur cet appareil.
bool isReviewSolicitationEligible({
  required bool fullyAuthenticated,
  required DateTime accountCreatedAt,
  required bool hasProperty,
  required DateTime? lastSolicitedAt,
  required DateTime now,
}) {
  if (!fullyAuthenticated || !hasProperty) return false;
  if (now.difference(accountCreatedAt) < kReviewMinAccountAge) return false;
  if (lastSolicitedAt != null &&
      now.difference(lastSolicitedAt) < kReviewSolicitationInterval) {
    return false;
  }
  return true;
}
```

`review_solicitation_storage.dart` :

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Date de la dernière sollicitation d'avis sur cet appareil (FEAT-060),
/// en ISO-8601. Locale à l'appareil, comme le mode d'affichage des cartes.
class ReviewSolicitationStorage {
  static const _key = 'review_solicited_at';

  Future<DateTime?> readLastSolicitedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> markSolicited(DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, at.toIso8601String());
  }
}

final reviewSolicitationStorageProvider =
    Provider<ReviewSolicitationStorage>((_) => ReviewSolicitationStorage());
```

`store_review_service.dart` :

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../../core/config/env.dart';

/// Notation sur les stores (FEAT-060). Seule [InAppReviewStoreReviewService]
/// importe `in_app_review` ; n'appeler que dans une app store.
abstract interface class StoreReviewService {
  Future<bool> isAvailable();

  /// Fenêtre de note native. Le store décide de l'afficher ou non ; jamais
  /// précédée d'une question (règles Apple 5.6.1 et Google Play).
  Future<void> requestReview();

  /// Ouvre la fiche de l'app (iOS : [appStoreId] requis).
  Future<void> openStoreListing({String? appStoreId});
}

class InAppReviewStoreReviewService implements StoreReviewService {
  final InAppReview _inAppReview = InAppReview.instance;

  @override
  Future<bool> isAvailable() => _inAppReview.isAvailable();

  @override
  Future<void> requestReview() => _inAppReview.requestReview();

  @override
  Future<void> openStoreListing({String? appStoreId}) =>
      _inAppReview.openStoreListing(appStoreId: appStoreId);
}

final storeReviewServiceProvider = Provider<StoreReviewService>(
  (_) => InAppReviewStoreReviewService(),
);

/// « Noter l'app » disponible ? App store uniquement ; sur iOS, seulement
/// avec l'identifiant App Store ([Env.appStoreId]).
bool canRateInStore({
  required bool storeApp,
  required TargetPlatform platform,
  String appStoreId = Env.appStoreId,
}) {
  if (!storeApp) return false;
  if (platform == TargetPlatform.iOS) return appStoreId.trim().isNotEmpty;
  return true;
}
```

`review_eligibility_provider.dart` :

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_session_provider.dart';
import '../../auth/domain/session_state.dart';
import '../../profile/application/landlord_profile_provider.dart';
import '../../properties/application/properties_list_provider.dart';
import '../data/review_solicitation_storage.dart';
import '../domain/review_eligibility.dart';

/// Horloge injectable (tests).
final reviewClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Éligibilité à la sollicitation d'avis (FEAT-060). Faux en cas d'erreur
/// de chargement (jamais de sollicitation sur une donnée incertaine).
final reviewEligibilityProvider = FutureProvider.autoDispose<bool>((ref) async {
  final full = ref.watch(sessionStateProvider) == SessionState.fullyAuthenticated;
  if (!full) return false;
  try {
    final profile = await ref.watch(landlordProfileProvider.future);
    final items = await ref.watch(propertiesListItemsProvider.future);
    final last = await ref
        .watch(reviewSolicitationStorageProvider)
        .readLastSolicitedAt();
    return isReviewSolicitationEligible(
      fullyAuthenticated: full,
      accountCreatedAt: profile.createdAt,
      hasProperty: items.isNotEmpty,
      lastSolicitedAt: last,
      now: ref.watch(reviewClockProvider)(),
    );
  } catch (_) {
    return false;
  }
});
```

`profile_page.dart` — après `tile_feedback` :

```dart
            if (canRateInStore(
              storeApp: isStoreApp,
              platform: defaultTargetPlatform,
            ))
              ListTile(
                key: const Key('tile_rate_app'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.star_rate_outlined),
                title: Text(l10n.profileHubRateAppTile),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => ref.read(storeReviewServiceProvider).openStoreListing(
                  appStoreId: Env.appStoreId.isEmpty ? null : Env.appStoreId,
                ),
              ),
```

(imports : `store_billing.dart`, `store_review_service.dart`, `env.dart`, `package:flutter/foundation.dart` ; si le `build` de la page n'a pas de `ref`, utiliser un `Consumer` autour de la tuile.)

- [ ] **Step 5: Vérifier**

Run: `flutter gen-l10n && flutter test test/unit/review_eligibility_test.dart test/unit/review_solicitation_storage_test.dart test/unit/store_review_service_test.dart test/widget/profile_page_test.dart && dart format lib test && flutter analyze && flutter build web --release --pwa-strategy=none && flutter build apk --debug && git checkout -- android/gradle.properties`
Expected: tout PASS ; « No issues found! » ; les deux builds réussissent.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/config/env.dart lib/features/app_review lib/features/profile/presentation/profile_page.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/unit/review_eligibility_test.dart test/unit/review_solicitation_storage_test.dart test/unit/store_review_service_test.dart test/widget/profile_page_test.dart
git commit -m "feat(review): éligibilité, stockage et bouton « Noter l'app » (FEAT-060)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `AppReviewPrompt` — fenêtre native (apps) et carte (web) sur l'Accueil

**Files:**
- Create: `lib/features/app_review/presentation/app_review_prompt.dart`
- Modify: `lib/features/dashboard/presentation/dashboard_page.dart` (`_DataView`, en tête de la `Column`, avant « ZONE 1 »)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Test: `test/widget/app_review_prompt_test.dart` (nouveau) ; la suite `test/widget/dashboard_page_test.dart` doit rester verte

**Interfaces:**
- Consumes: `reviewEligibilityProvider`, `reviewClockProvider`, `reviewSolicitationStorageProvider`, `storeReviewServiceProvider`, `StoreReviewService` (Task 4) ; `isStoreApp`.
- Produces: `class AppReviewPrompt extends ConsumerStatefulWidget` ; clés `card_review_invite`, `btn_review_invite_feedback`, `btn_review_invite_close`.

- [ ] **Step 1: Textes** (EN avec descriptions « FEAT-060 — … », FR) :

| Clé | EN | FR |
|---|---|---|
| `reviewInviteTitle` | Your opinion matters | Votre avis compte |
| `reviewInviteBody` | You've been using Baillan for a few weeks. Tell us what you think — it takes 30 seconds. | Vous utilisez Baillan depuis quelques semaines. Dites-nous ce que vous en pensez : 30 secondes suffisent. |
| `reviewInviteButton` | Give feedback | Donner mon avis |
| `reviewInviteCloseTooltip` | Close | Fermer |

- [ ] **Step 2: Écrire les tests qui échouent** — `test/widget/app_review_prompt_test.dart` : monter `AppReviewPrompt` seul dans `ProviderScope` + `MaterialApp.router` (GoRouter avec `/` → `Scaffold(body: AppReviewPrompt())` et `/profile/feedback` → `Text('feedback-page')`), overrides : `reviewEligibilityProvider.overrideWith((ref) async => eligible)`, `reviewSolicitationStorageProvider.overrideWithValue(fakeStorage)` (enregistre `markSolicited`), `storeReviewServiceProvider.overrideWithValue(fakeService)` (journalise `isAvailable`/`requestReview`, `available` configurable), `reviewClockProvider.overrideWithValue(() => DateTime(2026, 10, 9))`. Cas :

1. Web (`debugIsStoreAppOverride = false`), éligible → carte `card_review_invite` visible ; aucun appel au service store.
2. Web, non éligible → aucune carte.
3. Web, « Donner mon avis » → `markSolicited(2026-10-09)` puis navigation vers `/profile/feedback` (`find.text('feedback-page')`).
4. Web, croix `btn_review_invite_close` → `markSolicited` et carte disparue.
5. App store (`debugIsStoreAppOverride = true`, remis à `false` en `addTearDown`), éligible, `available = true` → `requestReview` appelé une fois, `markSolicited` appelé, aucune carte.
6. App store, éligible, `available = false` → pas de `requestReview`, pas de `markSolicited`.
7. App store, non éligible → aucun appel.
8. App store, éligible : reconstruire le widget (pump d'un parent qui change) → `requestReview` toujours appelé une seule fois.

- [ ] **Step 3: Vérifier qu'ils échouent**

Run: `flutter gen-l10n && flutter test test/widget/app_review_prompt_test.dart`
Expected: échec de compilation.

- [ ] **Step 4: Implémenter** — `app_review_prompt.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/store_billing.dart';
import '../../../core/i18n/l10n_extensions.dart';
import '../application/review_eligibility_provider.dart';
import '../data/review_solicitation_storage.dart';
import '../data/store_review_service.dart';

/// Sollicitation d'avis sur l'Accueil (FEAT-060).
///
/// - App store : si éligible, fenêtre de note native (une fois par montage),
///   jamais précédée d'une question ; la date est enregistrée quand la
///   demande est faite. Rien n'est affiché.
/// - Web : carte « Votre avis compte » → formulaire in-app, ou fermeture.
///   L'une ou l'autre action la masque pour 120 jours.
class AppReviewPrompt extends ConsumerStatefulWidget {
  const AppReviewPrompt({super.key});

  @override
  ConsumerState<AppReviewPrompt> createState() => _AppReviewPromptState();
}

class _AppReviewPromptState extends ConsumerState<AppReviewPrompt> {
  bool _handled = false;

  Future<void> _markSolicited() => ref
      .read(reviewSolicitationStorageProvider)
      .markSolicited(ref.read(reviewClockProvider)());

  Future<void> _requestNativeReview() async {
    final service = ref.read(storeReviewServiceProvider);
    if (!await service.isAvailable()) return;
    await service.requestReview();
    await _markSolicited();
  }

  @override
  Widget build(BuildContext context) {
    final eligible = ref.watch(reviewEligibilityProvider).valueOrNull ?? false;
    if (!eligible || _handled) return const SizedBox.shrink();

    if (isStoreApp) {
      _handled = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _requestNativeReview(),
      );
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        key: const Key('card_review_invite'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.reviewInviteTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const Key('btn_review_invite_close'),
                    tooltip: l10n.reviewInviteCloseTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() => _handled = true);
                      _markSolicited();
                    },
                  ),
                ],
              ),
              Text(l10n.reviewInviteBody),
              const SizedBox(height: 12),
              FilledButton.tonal(
                key: const Key('btn_review_invite_feedback'),
                onPressed: () async {
                  setState(() => _handled = true);
                  await _markSolicited();
                  if (context.mounted) context.push('/profile/feedback');
                },
                child: Text(l10n.reviewInviteButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

`dashboard_page.dart` — dans `_DataView.build`, première entrée de la `Column` (après le `return` de l'onboarding) :

```dart
        // FEAT-060 — sollicitation d'avis (fenêtre native dans les apps,
        // carte sur le web). Ici seulement : après la checklist de démarrage.
        const AppReviewPrompt(),
```

(+ import `../../app_review/presentation/app_review_prompt.dart`.) Si la suite `test/widget/dashboard_page_test.dart` casse parce que `reviewEligibilityProvider` charge des dépendances non remplacées, ajouter dans son montage l'override `reviewEligibilityProvider.overrideWith((ref) async => false)` — sans modifier les assertions existantes.

- [ ] **Step 5: Vérifier**

Run: `flutter gen-l10n && flutter test test/widget/app_review_prompt_test.dart test/widget/dashboard_page_test.dart && dart format lib test && flutter analyze && flutter test`
Expected: tout PASS ; « No issues found! ».

- [ ] **Step 6: Commit**

```bash
git add lib/features/app_review/presentation/app_review_prompt.dart lib/features/dashboard/presentation/dashboard_page.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/widget/app_review_prompt_test.dart test/widget/dashboard_page_test.dart
git commit -m "feat(review): demande de note native et carte « Votre avis compte » sur l'Accueil (FEAT-060)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Documentation et état

**Files:**
- Modify: `docs/state/routes/account.md`, `docs/state/FEATURES.md`, `docs/state/CHANGELOG.md`, `docs/STORE_COMPLIANCE.md`, `docs/MOBILE.md`, `dart-defines.prod.example.json`

- [ ] **Step 1: `docs/state/routes/account.md`** — ajouter la ligne de route `| /profile/feedback | FeedbackPage | write | « Donner mon avis » (FEAT-060) : note 1-5 + commentaire facultatif → support_requests (kind feedback) |` près de `/profile/support`, et mentionner dans la ligne `/profile` les tuiles « Donner mon avis » et « Noter l'app » (app store ; iOS seulement avec `APP_STORE_ID`).

- [ ] **Step 2: `docs/state/FEATURES.md`** — nouvelle ligne `| FEAT-060 | Avis in-app + notation stores (fenêtre native après 15 j + 1 bien, « Noter l'app », carte web « Votre avis compte ») | 🚧 wip | account, dashboard | branche feat/060-feedback-reviews, spec docs/superpowers/specs/2026-10-09-feedback-store-reviews-design.md |`.

- [ ] **Step 3: `docs/state/CHANGELOG.md`** — entrée en tête de la période courante : `### FEAT-060 : avis in-app et notation sur les stores (2026-10-09)`, 3-4 puces (avis dans `support_requests` + règles ; écran et tuile ; sollicitation 15 j / 1 bien / 120 j, fenêtre native dans les apps, carte sur le web ; « Noter l'app », `APP_STORE_ID`).

- [ ] **Step 4: `docs/STORE_COMPLIANCE.md`** — ajouter une puce : « Notation (FEAT-060) : demande via l'API native (`in_app_review`, Apple 5.6.1 / Google In-App Review), jamais précédée d'une question ; au plus une sollicitation tous les 120 jours ; aucun tri des avis (le formulaire in-app ne renvoie jamais vers le store). »

- [ ] **Step 5: `docs/MOBILE.md`** — dans la section des builds de release, ajouter `--dart-define=APP_STORE_ID=<Apple ID numérique>` pour iOS, avec une phrase : sans lui, « Noter l'app » est masqué sur iOS (la fenêtre native fonctionne sans).

- [ ] **Step 6: `dart-defines.prod.example.json`** — ajouter `"APP_STORE_ID": ""`.

- [ ] **Step 7: Commit**

```bash
git add docs/state/routes/account.md docs/state/FEATURES.md docs/state/CHANGELOG.md docs/STORE_COMPLIANCE.md docs/MOBILE.md dart-defines.prod.example.json
git commit -m "docs: avis in-app et notation stores (FEAT-060)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
