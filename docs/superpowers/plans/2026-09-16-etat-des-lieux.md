# FEAT-037 — État des lieux digital (V1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre au bailleur de rédiger un état des lieux (entrée/sortie) conforme au décret 2016-382 dans l'app et d'en produire un PDF rattaché au bail, persisté en collection immuable.

**Architecture:** Nouvelle collection immuable CF-exclusive `etat_des_lieux` (patron `charge_statements`/FEAT-033) écrite par une callable `createEtatDesLieux` qui fige les parties/adresse depuis le bail ; PDF rendu **côté client** à la demande depuis le snapshot (patron `receipt_pdf_renderer`). UI : formulaire multi-sections pré-rempli par un template + liste des EDL sur la fiche bail.

**Tech Stack:** Flutter/Dart, Riverpod, freezed, cloud_firestore, cloud_functions, `pdf: ^3.11.0` ; Cloud Functions TS (onCall europe-west1, vitest + FakeFirestore) ; Firestore Rules + indexes.

## Global Constraints

- **Collection immuable CF-exclusive** : `etat_des_lieux` — Rules `create,update,delete: if false` ; toute écriture via la callable `createEtatDesLieux`. Patron exact = `charge_statements` (`firestore.rules:346`, `functions/src/callable/charge_statements.ts`).
- **Immutabilité légale (loi 6/7/1989)** : la callable **fige** `propertyAddress`, `landlordFullName`, `tenantFullName` depuis le bail/profil au moment de la création — jamais acceptés du client.
- **Accès données** : Flutter → `firestoreProvider` (jamais `FirebaseFirestore.instance` hors main.dart) ; Functions → `dbForRequest(request)` (ADR 0003).
- **PDF client-side** : rendu à la demande depuis le snapshot (pas de `pdfPath`, pas de Storage serveur), patron `receipt_pdf_renderer.dart`.
- **i18n** : toute chaîne visible via `.arb` FR/EN, `@description` sur template EN, parité `test/l10n/arb_parity_test.dart`, `flutter gen-l10n`. Les libellés internes du PDF peuvent rester dans le renderer.
- **Généré jamais commité** : `*.freezed.dart`, `*.g.dart`, `app_localizations*.dart` sont gitignorés + régénérés par CI/build_runner. Committer seulement les sources.
- **Build vert par tâche** : Dart → `dart format .` + `flutter analyze` + tests ; Functions → `npm run lint && npm run build && npm test` (la CI functions lance les trois).
- **Déploiement reporté (gel GitHub Actions, Plan A)** : functions (manuel `firebase deploy --only functions`), rules + indexes (`--only firestore:rules,firestore:indexes`) à déployer au reset du quota. Ne bloque pas le merge (vert local).
- **Nommage** : enums `sqlValue` en snake_case (patron `DocumentCategory`). Collection/champs Firestore en camelCase côté doc (patron `charge_statements`).

---

### Task 1: Modèles de domaine + enums + template

**Files:**
- Create: `lib/features/etat_des_lieux/domain/etat_des_lieux.dart` (+ `.freezed.dart` généré)
- Create: `lib/features/etat_des_lieux/domain/edl_enums.dart`
- Create: `lib/features/etat_des_lieux/domain/edl_default_template.dart`
- Test: `test/unit/etat_des_lieux_model_test.dart`

**Interfaces:**
- Produces : `EtatDesLieux`, `EdlRoom`, `EdlElement`, `EdlMeterReadings` (freezed) ; enums `EtatDesLieuxType {entree, sortie}` et `EdlCondition {neuf, bon, moyen, mauvais}` avec `sqlValue`/`fromSql` ; `defaultEdlRooms()` → `List<EdlRoom>`.

- [ ] **Step 1: Écrire le test (échoue)**

`test/unit/etat_des_lieux_model_test.dart` :

```dart
import 'package:easyrent/features/etat_des_lieux/domain/edl_enums.dart';
import 'package:easyrent/features/etat_des_lieux/domain/edl_default_template.dart';
import 'package:easyrent/features/etat_des_lieux/domain/etat_des_lieux.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EtatDesLieuxType round-trip sqlValue', () {
    for (final t in EtatDesLieuxType.values) {
      expect(EtatDesLieuxType.fromSql(t.sqlValue), t);
    }
    expect(EtatDesLieuxType.entree.sqlValue, 'entree');
    expect(EtatDesLieuxType.sortie.sqlValue, 'sortie');
  });

  test('EdlCondition round-trip sqlValue', () {
    for (final c in EdlCondition.values) {
      expect(EdlCondition.fromSql(c.sqlValue), c);
    }
    expect(EdlCondition.neuf.sqlValue, 'neuf');
    expect(EdlCondition.mauvais.sqlValue, 'mauvais');
  });

  test('defaultEdlRooms fournit des pièces non vides avec éléments', () {
    final rooms = defaultEdlRooms();
    expect(rooms, isNotEmpty);
    expect(rooms.every((r) => r.elements.isNotEmpty), isTrue);
  });

  test('EtatDesLieux se construit avec ses champs', () {
    final edl = EtatDesLieux(
      id: 'e1',
      landlordId: 'l1',
      leaseId: 'lease1',
      type: EtatDesLieuxType.entree,
      date: DateTime(2026, 9, 16),
      propertyAddress: '1 rue X, 75001 Paris',
      landlordFullName: 'Jean Bailleur',
      tenantFullName: 'Marie Locataire',
      rooms: const [
        EdlRoom(name: 'Séjour', elements: [
          EdlElement(name: 'Murs', condition: EdlCondition.bon, comment: null),
        ]),
      ],
      meterReadings: const EdlMeterReadings(
        waterIndex: '123', electricityIndex: null, gasIndex: null,
      ),
      keysCount: 3,
      generalComment: null,
      createdAt: DateTime(2026, 9, 16),
    );
    expect(edl.rooms.single.elements.single.condition, EdlCondition.bon);
    expect(edl.keysCount, 3);
  });
}
```

- [ ] **Step 2: Lancer — échoue** (`flutter test test/unit/etat_des_lieux_model_test.dart`).

- [ ] **Step 3: Écrire les enums** — `edl_enums.dart` :

```dart
/// Type d'état des lieux (loi 6/7/1989 : à l'entrée ET à la sortie).
enum EtatDesLieuxType {
  entree('entree'),
  sortie('sortie');

  const EtatDesLieuxType(this.sqlValue);
  final String sqlValue;

  static EtatDesLieuxType fromSql(String value) =>
      EtatDesLieuxType.values.firstWhere((t) => t.sqlValue == value);
}

/// État d'un élément constaté (échelle usuelle des EDL).
enum EdlCondition {
  neuf('neuf'),
  bon('bon'),
  moyen('moyen'),
  mauvais('mauvais');

  const EdlCondition(this.sqlValue);
  final String sqlValue;

  static EdlCondition fromSql(String value) =>
      EdlCondition.values.firstWhere((c) => c.sqlValue == value);
}
```

- [ ] **Step 4: Écrire le modèle** — `etat_des_lieux.dart` (freezed + json, `@JsonKey` snake_case, `EnumX` converters via `sqlValue`) :

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

import 'edl_enums.dart';

part 'etat_des_lieux.freezed.dart';
part 'etat_des_lieux.g.dart';

EtatDesLieuxType _typeFromJson(String v) => EtatDesLieuxType.fromSql(v);
String _typeToJson(EtatDesLieuxType v) => v.sqlValue;
EdlCondition _condFromJson(String v) => EdlCondition.fromSql(v);
String _condToJson(EdlCondition v) => v.sqlValue;

@freezed
class EtatDesLieux with _$EtatDesLieux {
  const factory EtatDesLieux({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    @JsonKey(name: 'lease_id') required String leaseId,
    @JsonKey(name: 'type', fromJson: _typeFromJson, toJson: _typeToJson)
    required EtatDesLieuxType type,
    required DateTime date,
    @JsonKey(name: 'property_address') required String propertyAddress,
    @JsonKey(name: 'landlord_full_name') required String landlordFullName,
    @JsonKey(name: 'tenant_full_name') required String tenantFullName,
    required List<EdlRoom> rooms,
    @JsonKey(name: 'meter_readings') required EdlMeterReadings meterReadings,
    @JsonKey(name: 'keys_count') required int keysCount,
    @JsonKey(name: 'general_comment') String? generalComment,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _EtatDesLieux;

  factory EtatDesLieux.fromJson(Map<String, dynamic> json) =>
      _$EtatDesLieuxFromJson(json);
}

@freezed
class EdlRoom with _$EdlRoom {
  const factory EdlRoom({
    required String name,
    required List<EdlElement> elements,
  }) = _EdlRoom;

  factory EdlRoom.fromJson(Map<String, dynamic> json) => _$EdlRoomFromJson(json);
}

@freezed
class EdlElement with _$EdlElement {
  const factory EdlElement({
    required String name,
    @JsonKey(fromJson: _condFromJson, toJson: _condToJson)
    required EdlCondition condition,
    String? comment,
  }) = _EdlElement;

  factory EdlElement.fromJson(Map<String, dynamic> json) =>
      _$EdlElementFromJson(json);
}

@freezed
class EdlMeterReadings with _$EdlMeterReadings {
  const factory EdlMeterReadings({
    @JsonKey(name: 'water_index') String? waterIndex,
    @JsonKey(name: 'electricity_index') String? electricityIndex,
    @JsonKey(name: 'gas_index') String? gasIndex,
  }) = _EdlMeterReadings;

  factory EdlMeterReadings.fromJson(Map<String, dynamic> json) =>
      _$EdlMeterReadingsFromJson(json);
}
```

> ⚠️ Vérifier le convertisseur de `DateTime`/`Timestamp` utilisé ailleurs (les autres modèles lisant Firestore passent par `firestoreDocToSnakeJson` + un converter date). Aligner `date`/`createdAt` sur le patron `Receipt`/`ChargeStatement` (probable `Timestamp`→ISO au read). Si un helper de conversion date existe (`lib/core/`), le réutiliser plutôt que d'inventer.

- [ ] **Step 5: Écrire le template** — `edl_default_template.dart` :

```dart
import 'edl_enums.dart';
import 'etat_des_lieux.dart';

/// Pièces/éléments par défaut proposés à la création d'un EDL — évite la page
/// blanche. Entièrement éditable/supprimable par le bailleur. Condition par
/// défaut `bon` (l'usage : le bailleur ajuste ce qui diffère).
List<EdlRoom> defaultEdlRooms() {
  EdlElement e(String name) =>
      EdlElement(name: name, condition: EdlCondition.bon, comment: null);
  const surfaces = ['Sol', 'Murs', 'Plafond'];
  return [
    EdlRoom(name: 'Séjour', elements: [for (final s in surfaces) e(s)]),
    EdlRoom(name: 'Chambre', elements: [for (final s in surfaces) e(s)]),
    EdlRoom(
      name: 'Cuisine',
      elements: [for (final s in surfaces) e(s), e('Équipements')],
    ),
    EdlRoom(
      name: 'Salle de bain',
      elements: [for (final s in surfaces) e(s), e('Sanitaires')],
    ),
    EdlRoom(name: 'WC', elements: [for (final s in surfaces) e(s)]),
  ];
}
```

> Les noms du template sont en français en dur (données métier, pas de l'UI chrome) ; acceptable en V1 (le bailleur les édite). Si la revue exige l'i18n du template, le passer en clés — mais YAGNI par défaut.

- [ ] **Step 6: build_runner** — `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 7: Lancer — passe** ; `flutter analyze lib/features/etat_des_lieux` clean.

- [ ] **Step 8: Commit** (sources uniquement, PAS les `.freezed.dart`/`.g.dart`) :

```bash
dart format lib/features/etat_des_lieux test/unit/etat_des_lieux_model_test.dart
git add lib/features/etat_des_lieux/domain/etat_des_lieux.dart lib/features/etat_des_lieux/domain/edl_enums.dart lib/features/etat_des_lieux/domain/edl_default_template.dart test/unit/etat_des_lieux_model_test.dart
git commit -m "feat(edl): modèles état des lieux (EtatDesLieux, pièces, compteurs) + template"
```

---

### Task 2: Rules + index `etat_des_lieux`

**Files:**
- Modify: `firestore.rules` (nouveau bloc `match /etat_des_lieux/{id}`)
- Modify: `firestore.indexes.json` (index composite)
- Test: `functions/rules-tests/` (ajouter un cas cross-user, patron des tests `charge_statements`/`receipts`)

**Interfaces:** Produces : collection `etat_des_lieux` lisible owner-scoped, non-écrivable client.

- [ ] **Step 1: Ajouter le bloc Rules** — dans `firestore.rules`, à côté de `charge_statements` (patron identique, `firestore.rules:346`) :

```
    // etat_des_lieux/{id} — IMMUABLES (loi 6/7/1989, décret 2016-382) → CF exclusive
    // État des lieux figé (FEAT-037). Owner-scoped en get ET list, comme
    // receipts/charge_statements. Création via callable createEtatDesLieux.
    match /etat_des_lieux/{id} {
      allow get:  if isOwner(resource.data.landlordId);
      allow list: if isOwner(resource.data.landlordId);
      allow create, update, delete: if false;
    }
```

- [ ] **Step 2: Ajouter l'index** — dans `firestore.indexes.json`, un index composite pour la liste par bail triée :

```json
    {
      "collectionGroup": "etat_des_lieux",
      "queryScope": "COLLECTION",
      "fields": [
        {"fieldPath": "landlordId", "order": "ASCENDING"},
        {"fieldPath": "leaseId", "order": "ASCENDING"},
        {"fieldPath": "createdAt", "order": "DESCENDING"}
      ]
    }
```

> Respecter le format exact du fichier (virgules, position dans le tableau `indexes`).

- [ ] **Step 3: Test Rules cross-user** — dans `functions/rules-tests/` (repérer le fichier des tests rules ; patron des cas `charge_statements`) : (a) le propriétaire peut `get`/`list` ses EDL ; (b) un autre landlord ne peut PAS les lire ; (c) `create`/`update`/`delete` refusés même au propriétaire.

- [ ] **Step 4: Lancer les tests Rules** — commande du repo (probable `cd functions && npm run test:rules` — vérifier `functions/package.json`). Émulateur requis ; si indisponible en local, noter que la CI rules le couvre (mais ici CI gelée → exécuter en local via l'émulateur si présent).

- [ ] **Step 5: Commit**

```bash
git add firestore.rules firestore.indexes.json functions/rules-tests/
git commit -m "feat(edl): rules + index etat_des_lieux (immuable, owner-scoped, CF-exclusive)"
```

---

### Task 3: Callable `createEtatDesLieux`

**Files:**
- Create: `functions/src/callable/etat_des_lieux.ts`
- Modify: `functions/src/index.ts` (export)
- Test: `functions/src/__tests__/etat_des_lieux.test.ts`

**Interfaces:** Produces : `createEtatDesLieux` (onCall europe-west1) → `{etatDesLieuxId}`.

- [ ] **Step 1: Écrire le test (échoue)** — `functions/src/__tests__/etat_des_lieux.test.ts`, patron `charge_statements.test.ts` (mock hoisted `firebase-admin`, `FakeFirestore`, `makeRequest`). Cas :

```
- happy path : bail possédé → doc écrit dans etat_des_lieux ; parties/adresse
  FIGÉES depuis le bail (pas depuis le payload) ; type/condition conservés ;
  retour {etatDesLieuxId}.
- refuse bail non possédé (permission-denied).
- refuse bail supprimé (failed-precondition).
- refuse type invalide (invalid-argument).
- refuse une condition d'élément hors enum (invalid-argument).
- refuse keysCount < 0 (invalid-argument).
- non authentifié → throw.
```

Utiliser `.run(makeRequest(uid, data))` et lire l'état via `fakeDb.peek(...)` (patron `documents.test.ts`/`charge_statements.test.ts`).

- [ ] **Step 2: Lancer — échoue** (`cd functions && npx vitest run src/__tests__/etat_des_lieux.test.ts`).

- [ ] **Step 3: Implémenter la callable** — `functions/src/callable/etat_des_lieux.ts` (patron `finalizeChargeRegularization`) :

```ts
/**
 * createEtatDesLieux — callable (FEAT-037).
 *
 * Écrit un état des lieux immuable (Rules create/update/delete: if false),
 * patron `charge_statements`. Fige parties + adresse depuis le bail (loi
 * 6/7/1989). PDF rendu côté client depuis le snapshot (pas de Storage).
 */
import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  asBag,
  dataOrFail,
  optionalString,
  requireAuthUid,
  requireInt,
  requireString,
  toTimestamp,
} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";

const TYPES = new Set(["entree", "sortie"]);
const CONDITIONS = new Set(["neuf", "bon", "moyen", "mauvais"]);

interface EdlElement {
  name: string;
  condition: string;
  comment: string | null;
}
interface EdlRoom {
  name: string;
  elements: EdlElement[];
}

/** Valide et normalise les pièces/éléments. Jette invalid-argument sinon. */
export function validateRooms(raw: unknown): EdlRoom[] {
  if (!Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "rooms must be an array");
  }
  return raw.map((r, i) => {
    const room = asBag(r);
    const elementsRaw = Array.isArray(room.elements) ? room.elements : [];
    const elements: EdlElement[] = elementsRaw.map((e, j) => {
      const el = asBag(e);
      const condition = requireString(el.condition, `rooms[${i}].elements[${j}].condition`);
      if (!CONDITIONS.has(condition)) {
        throw new HttpsError("invalid-argument", `invalid condition: ${condition}`);
      }
      return {
        name: requireString(el.name, `rooms[${i}].elements[${j}].name`),
        condition,
        comment: optionalString(el.comment, `rooms[${i}].elements[${j}].comment`) ?? null,
      };
    });
    return {name: requireString(room.name, `rooms[${i}].name`), elements};
  });
}

export const createEtatDesLieux = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    const leaseId = requireString(data.leaseId, "leaseId");
    const type = requireString(data.type, "type");
    if (!TYPES.has(type)) {
      throw new HttpsError("invalid-argument", `invalid type: ${type}`);
    }
    const date = toTimestamp(data.date, "date");
    const keysCount = requireInt(data.keysCount, "keysCount");
    if (keysCount < 0) {
      throw new HttpsError("invalid-argument", "keysCount must be >= 0");
    }
    const rooms = validateRooms(data.rooms);
    const meter = asBag(data.meterReadings ?? {});
    const meterReadings = {
      waterIndex: optionalString(meter.waterIndex, "waterIndex") ?? null,
      electricityIndex: optionalString(meter.electricityIndex, "electricityIndex") ?? null,
      gasIndex: optionalString(meter.gasIndex, "gasIndex") ?? null,
    };
    const generalComment = optionalString(data.generalComment, "generalComment") ?? null;

    const db = dbForRequest(request);

    // Landlord (fullName légal)
    const landlordSnap = await db.doc(`landlords/${uid}`).get();
    const landlordData = dataOrFail(landlordSnap, "landlord not found");
    const landlordFullName = String(landlordData.fullName ?? "").trim();
    if (landlordFullName.length === 0) {
      throw new HttpsError("failed-precondition", "profile_incomplete", {missing: ["fullName"]});
    }

    // Lease + ownership + non supprimé ; fige adresse + locataire
    const leaseSnap = await db.doc(`leases/${leaseId}`).get();
    const lease = dataOrFail(leaseSnap, "lease not found");
    if (String(lease.landlordId ?? "") !== uid) {
      throw new HttpsError("permission-denied", "lease not owned");
    }
    if (lease.deletedAt != null) {
      throw new HttpsError("failed-precondition", "lease is deleted");
    }
    const tenantFullName =
      `${String(lease.tenantFirstName ?? "")} ${String(lease.tenantLastName ?? "")}`.trim();
    const propertyAddress = String(lease.propertyAddress ?? "");

    const ref = db.collection("etat_des_lieux").doc();
    const id = ref.id;
    const now = admin.firestore.FieldValue.serverTimestamp();
    try {
      await ref.set({
        id,
        landlordId: uid,
        leaseId,
        propertyId: String(lease.propertyId ?? ""),
        type,
        date,
        propertyAddress,
        landlordFullName,
        tenantFullName,
        rooms,
        meterReadings,
        keysCount,
        generalComment,
        createdAt: now,
        schemaVersion: 1,
      });
    } catch (err) {
      logger.error("etat_des_lieux write failed", {uid, id, err});
      throw new HttpsError("internal", "etat_des_lieux_persist_failed");
    }

    logger.info("etat des lieux created", {uid, id, type});
    return {etatDesLieuxId: id};
  },
);
```

- [ ] **Step 4: Exporter** — `functions/src/index.ts`, à côté des autres callables :

```ts
export {createEtatDesLieux} from "./callable/etat_des_lieux";
```

- [ ] **Step 5: Lancer — passe** (`npx vitest run src/__tests__/etat_des_lieux.test.ts`).

- [ ] **Step 6: lint+build+suite** — `cd functions && npm run lint && npm run build && npm test` (les trois verts ; eslint inclus — attention `require-await`, imports inutilisés).

- [ ] **Step 7: Commit**

```bash
git add functions/src/callable/etat_des_lieux.ts functions/src/index.ts functions/src/__tests__/etat_des_lieux.test.ts
git commit -m "feat(edl): callable createEtatDesLieux (immuable, fige parties/adresse)"
```

---

### Task 4: Renderer PDF client

**Files:**
- Create: `lib/features/etat_des_lieux/data/etat_des_lieux_pdf_renderer.dart`
- Test: `test/unit/etat_des_lieux_pdf_renderer_test.dart`

**Interfaces:** Produces : `Future<Uint8List> renderEtatDesLieuxPdf(EtatDesLieux edl, {AppLocalizations? l10n})` (ou classe, aligner sur la signature de `receipt_pdf_renderer.dart`).

- [ ] **Step 1: Lire le renderer de référence** — `lib/features/receipts/data/receipt_pdf_renderer.dart` (structure `Document`, polices via `pdf_brand_fonts.dart`, helpers de mise en page). Reproduire la même ossature.

- [ ] **Step 2: Écrire le test de fumée (échoue)** :

```dart
import 'package:easyrent/features/etat_des_lieux/data/etat_des_lieux_pdf_renderer.dart';
import 'package:easyrent/features/etat_des_lieux/domain/edl_enums.dart';
import 'package:easyrent/features/etat_des_lieux/domain/etat_des_lieux.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renderEtatDesLieuxPdf produit des bytes non vides', () async {
    final edl = EtatDesLieux(
      id: 'e1', landlordId: 'l1', leaseId: 'lease1',
      type: EtatDesLieuxType.entree, date: DateTime(2026, 9, 16),
      propertyAddress: '1 rue X, 75001 Paris',
      landlordFullName: 'Jean Bailleur', tenantFullName: 'Marie Locataire',
      rooms: const [
        EdlRoom(name: 'Séjour', elements: [
          EdlElement(name: 'Murs', condition: EdlCondition.bon, comment: 'RAS'),
        ]),
      ],
      meterReadings: const EdlMeterReadings(
        waterIndex: '123', electricityIndex: '456', gasIndex: null),
      keysCount: 3, generalComment: null, createdAt: DateTime(2026, 9, 16),
    );
    final bytes = await renderEtatDesLieuxPdf(edl);
    expect(bytes, isNotEmpty);
  });
}
```

- [ ] **Step 3: Implémenter le renderer** — `pw.Document` avec sections, dans l'ordre décret 2016-382 :
  1. En-tête : titre « État des lieux d'entrée/de sortie », date, adresse, parties (bailleur/locataire).
  2. Par pièce : tableau `pw.Table` (élément | état | commentaire).
  3. Relevés compteurs (eau/élec/gaz — n'afficher que les non-null).
  4. Nombre de clés remises.
  5. Commentaire général (si présent).
  6. Blocs signature : « Le bailleur » / « Le locataire » + lignes date & lieu.
  Réutiliser les polices/couleurs de `pdf_brand_fonts.dart` comme `receipt_pdf_renderer.dart`. Mapper `EdlCondition` vers un libellé français (`neuf/bon/moyen/mauvais` → « Neuf/Bon/Moyen/Mauvais »).

  > Pas de placeholder : écrire le code complet du `Document`. Se calquer sur `receipt_pdf_renderer.dart` pour l'API `pdf`/`printing` exacte (imports, `PdfPageFormat`, `MultiPage` vs `Page`, `theme`). Un EDL peut être long → **`pw.MultiPage`** (pagination auto), pas `pw.Page`.

- [ ] **Step 4: Lancer — passe** (`flutter test test/unit/etat_des_lieux_pdf_renderer_test.dart`).

- [ ] **Step 5: Commit**

```bash
dart format lib/features/etat_des_lieux/data/etat_des_lieux_pdf_renderer.dart test/unit/etat_des_lieux_pdf_renderer_test.dart
git add lib/features/etat_des_lieux/data/etat_des_lieux_pdf_renderer.dart test/unit/etat_des_lieux_pdf_renderer_test.dart
git commit -m "feat(edl): renderer PDF conforme décret 2016-382"
```

---

### Task 5: Repository

**Files:**
- Create: `lib/features/etat_des_lieux/data/etat_des_lieux_repository.dart`
- Test: `test/unit/etat_des_lieux_repository_test.dart`

**Interfaces:**
- Consumes : callable `createEtatDesLieux`, modèle `EtatDesLieux`.
- Produces : `EtatDesLieuxRepository` { `create(...) → Future<EtatDesLieux>`, `listForLease(String) → Future<List<EtatDesLieux>>`, `getById(String) → Future<EtatDesLieux>` } + `etatDesLieuxRepositoryProvider`.

- [ ] **Step 1: Écrire le test (échoue)** — `fake_cloud_firestore` + `firebase_auth_mocks` (patron `dashboard_repository_firestore_test.dart`). Cas : `listForLease` renvoie les EDL du bail triés `createdAt desc`, owner-scopé (n'inclut pas ceux d'un autre landlord) ; `getById` renvoie le bon ; `getById` d'un doc d'un autre landlord → exception not-found. (Le chemin `create` via callable est difficile à tester en fake : soit mocker `FirebaseFunctions` comme dans les tests receipts, soit se limiter à un test de lecture ; s'aligner sur le patron des tests repository existants — regarder `receipts_repository` s'il a un test.)

- [ ] **Step 2: Lancer — échoue.**

- [ ] **Step 3: Implémenter** — patron `FirestoreReceiptsRepository` (`_firestore`, `_auth`, `_functions`, `_callable`, `firestoreDocToSnakeJson`) :

```dart
// interface + impl :
abstract interface class EtatDesLieuxRepository {
  Future<EtatDesLieux> create({
    required String leaseId,
    required EtatDesLieuxType type,
    required DateTime date,
    required List<EdlRoom> rooms,
    required EdlMeterReadings meterReadings,
    required int keysCount,
    String? generalComment,
  });
  Future<List<EtatDesLieux>> listForLease(String leaseId);
  Future<EtatDesLieux> getById(String id);
}
```

- `create` : `_callable('createEtatDesLieux').call({... payload snake/camel attendu par la callable ...})` puis `getById(res.data['etatDesLieuxId'])`. **Attention** : la callable lit `data.type`, `data.rooms[].condition`, etc. — envoyer les `sqlValue` des enums et les dates en ISO/millis (aligner sur ce que `toTimestamp` accepte côté callable — vérifier `callable_helpers.toTimestamp`).
- `listForLease` : `collection('etat_des_lieux').where('landlordId', ==uid).where('leaseId', ==id).orderBy('createdAt', descending:true).get()` → `EtatDesLieux.fromJson(firestoreDocToSnakeJson(...))`.
- `getById` : lecture + garde `landlordId == uid` (patron `documents_repository.getById`).
- Provider `etatDesLieuxRepositoryProvider` via `firestoreProvider` + `FirebaseAuth.instance` + `FirebaseFunctions.instanceFor(region: 'europe-west1')` (vérifier le patron exact des autres repos functions).

- [ ] **Step 4: Lancer — passe** ; `flutter analyze` clean.

- [ ] **Step 5: Commit**

```bash
dart format lib/features/etat_des_lieux/data/etat_des_lieux_repository.dart test/unit/etat_des_lieux_repository_test.dart
git add lib/features/etat_des_lieux/data/etat_des_lieux_repository.dart test/unit/etat_des_lieux_repository_test.dart
git commit -m "feat(edl): repository (create via callable, listForLease, getById)"
```

---

### Task 6: Contrôleur + formulaire UI + i18n

**Files:**
- Create: `lib/features/etat_des_lieux/application/etat_des_lieux_form_controller.dart`
- Create: `lib/features/etat_des_lieux/presentation/etat_des_lieux_form_page.dart`
- Create: `lib/features/etat_des_lieux/presentation/edl_condition_l10n.dart`
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`
- Test: `test/widget/etat_des_lieux_form_page_test.dart`

**Interfaces:**
- Consumes : `EtatDesLieuxRepository`, `defaultEdlRooms()`, PDF renderer.
- Produces : `etatDesLieuxFormControllerProvider` (état sealed idle/submitting/success(edl)/error(reason)) ; `EtatDesLieuxFormPage`.

- [ ] **Step 1: Clés i18n** — FR + EN (`@description` EN) : titres (form/list), `edlTypeEntree`/`edlTypeSortie`, labels états (`edlConditionNeuf/Bon/Moyen/Mauvais`), sections (`edlSectionRooms`, `edlSectionMeters`, `edlMeterWater/Electricity/Gas`, `edlKeysCount`, `edlGeneralComment`), boutons (`edlAddRoom`, `edlAddElement`, `edlGenerate`), erreurs (`edlErrorLeaseNotOwned`/`edlErrorProfileIncomplete`/`edlErrorGeneric`). `flutter gen-l10n`. Parité `arb_parity_test`.

- [ ] **Step 2: Contrôleur** — `StateNotifier` avec état sealed (patron `update_document_category_controller.dart`) ; méthode `submit({...})` qui appelle `repository.create(...)`, mappe `FirebaseFunctionsException` (`lease not owned`, `profile_incomplete`, autre) vers un `EdlFormErrorReason`, expose `success(edl)`.

- [ ] **Step 3: Page formulaire** — `ConsumerStatefulWidget` :
  - État local : `EtatDesLieuxType` (SegmentedButton entrée/sortie), `DateTime date` (date picker, défaut aujourd'hui), `List<EdlRoom> rooms` (init `defaultEdlRooms()`), 3 contrôleurs texte compteurs, `keysCount` (int field), `generalComment`.
  - Section pièces : pour chaque pièce, un `Card` avec nom éditable, liste d'éléments (nom + `DropdownButton<EdlCondition>` + champ commentaire), boutons supprimer élément / ajouter élément ; bouton supprimer pièce / ajouter pièce.
  - Bouton « Générer » → `controller.submit(...)` ; sur `success`, rendre le PDF (`renderEtatDesLieuxPdf`) et l'ouvrir (patron `open_receipt_pdf.dart`) ; sur `error`, SnackBar i18n.
  - Design tokens uniquement (AppSpacing…), responsive.

  > Code complet requis. Se calquer sur un formulaire multi-sections existant (ex. `PaymentFormPage` / `LeaseFormPage`) pour les patterns de champs, validation, et soumission.

- [ ] **Step 4: gen-l10n + analyze + tests** — `flutter gen-l10n && flutter analyze lib/features/etat_des_lieux && flutter test test/widget/etat_des_lieux_form_page_test.dart test/l10n/arb_parity_test.dart`. Le widget test couvre : template rendu (5 pièces), ajout/suppression pièce+élément, changement d'état via dropdown, « Générer » appelle le contrôleur (repo mocké), erreur → SnackBar.

- [ ] **Step 5: Commit** (sources uniquement, pas de généré) :

```bash
dart format lib/features/etat_des_lieux test/widget/etat_des_lieux_form_page_test.dart lib/l10n/app_fr.arb lib/l10n/app_en.arb
git add lib/features/etat_des_lieux/application/etat_des_lieux_form_controller.dart lib/features/etat_des_lieux/presentation/etat_des_lieux_form_page.dart lib/features/etat_des_lieux/presentation/edl_condition_l10n.dart lib/l10n/app_fr.arb lib/l10n/app_en.arb test/widget/etat_des_lieux_form_page_test.dart
git commit -m "feat(edl): formulaire de saisie + contrôleur + i18n"
```

---

### Task 7: Liste EDL + entrée fiche bail + routes

**Files:**
- Create: `lib/features/etat_des_lieux/presentation/etat_des_lieux_list_page.dart`
- Modify: `lib/core/router/app_router.dart` (2 routes)
- Modify: `lib/features/leases/presentation/lease_detail_page.dart` (section/tuile d'accès)
- Test: `test/widget/etat_des_lieux_list_page_test.dart`

**Interfaces:**
- Consumes : `etatDesLieuxRepositoryProvider`, `EtatDesLieuxFormPage`, renderer PDF.
- Produces : routes `/leases/:id/etat-des-lieux` (liste) et `/leases/:id/etat-des-lieux/new` (form).

- [ ] **Step 1: Provider liste** — `FutureProvider.family<List<EtatDesLieux>, String>` (leaseId) → `repository.listForLease` (patron `leaseDocumentsProvider`/receipts).

- [ ] **Step 2: Page liste** — `EtatDesLieuxListPage(leaseId)` : liste (type + date, bouton « PDF » qui rend+ouvre), empty state (`CardEmptyState`), CTA « Nouvel état des lieux » → push `/leases/:id/etat-des-lieux/new`. Patron `LeaseReceiptsPage` (`lib/features/receipts/presentation/`).

- [ ] **Step 3: Routes** — dans `app_router.dart`, sous la branche baux (patron des routes `/leases/:id/receipts` et `/leases/:id/payments/new`, `app_router.dart:~515-536`) :

```dart
GoRoute(
  path: 'etat-des-lieux',
  pageBuilder: (context, state) => appPage(
    key: state.pageKey,
    child: EtatDesLieuxListPage(leaseId: state.pathParameters['id']!),
    transition: AppTransition.standard,
  ),
  routes: [
    GoRoute(
      path: 'new',
      pageBuilder: (context, state) => appPage(
        key: state.pageKey,
        child: EtatDesLieuxFormPage(leaseId: state.pathParameters['id']!),
        transition: AppTransition.standard,
      ),
    ),
  ],
),
```

> Vérifier le chemin parent exact du bail (`/leases/:id`) et la forme `appPage`/`AppTransition` réellement utilisée dans le fichier ; recopier le patron voisin.

- [ ] **Step 4: Entrée fiche bail** — dans `lease_detail_page.dart`, ajouter une tuile/section « États des lieux » naviguant vers `/leases/<id>/etat-des-lieux` (patron des autres sections de la fiche, ex. accès quittances/documents).

- [ ] **Step 5: analyze + tests** — `flutter analyze lib/features/etat_des_lieux lib/features/leases lib/core/router && flutter test test/widget/etat_des_lieux_list_page_test.dart`. Widget test liste : empty state ; liste avec 2 EDL (repo mocké) ; CTA navigue.

- [ ] **Step 6: Suite complète + format repo-wide** — `dart format --set-exit-if-changed .` (doit être clean) puis `flutter test` (suite entière verte — vérifie l'absence de régression sur les tests router/lease existants).

- [ ] **Step 7: Commit**

```bash
git add lib/features/etat_des_lieux/presentation/etat_des_lieux_list_page.dart lib/core/router/app_router.dart lib/features/leases/presentation/lease_detail_page.dart test/widget/etat_des_lieux_list_page_test.dart
git commit -m "feat(edl): page liste + entrée fiche bail + routes"
```

---

### Task 8: Documentation d'état (DoD)

**Files:**
- Modify: `docs/state/schema/leases.md` (collection `etat_des_lieux`)
- Modify: `docs/state/functions/leases.md` (callable `createEtatDesLieux`)
- Modify: `docs/state/routes/leases.md` (routes EDL)
- Modify: `docs/state/FEATURES.md` (FEAT-037 → done)
- Modify: `docs/state/CHANGELOG.md`
- Modify: `docs/state/INDEX.md` (décomptes : collections +1, callables +1, index +1)

- [ ] **Step 1** : schema — documenter la collection immuable `etat_des_lieux` (champs, immutabilité, CF-exclusive, index composite).
- [ ] **Step 2** : functions — `createEtatDesLieux` (fige parties/adresse, refus ownership/type/condition/keysCount, retour).
- [ ] **Step 3** : routes — `/leases/:id/etat-des-lieux` + `/new`, entrée fiche bail.
- [ ] **Step 4** : `FEATURES.md` — `| FEAT-037 | État des lieux digital (V1 : saisie + PDF décret 2016-382, collection immuable) | ✅ done | leases | feat/037-etat-des-lieux |`.
- [ ] **Step 5** : `CHANGELOG.md` — entrée FEAT-037 : saisie EDL entrée/sortie → PDF conforme, collection immuable CF-exclusive, cuts V2 (photos, e-signature, comparaison). **Déploiement functions + rules/index reporté (gel Actions).**
- [ ] **Step 6** : `INDEX.md` — mettre à jour les décomptes de la section Stack (collections, callables, index composites).
- [ ] **Step 7: Commit**

```bash
git add docs/state/
git commit -m "docs(state): FEAT-037 état des lieux digital V1"
```

---

## Self-Review

- **Spec coverage** : modèles+template (T1), rules+index immuables (T2), callable fige-parties (T3), PDF décret (T4), repo (T5), form+i18n (T6), liste+routes+entrée bail (T7), docs (T8). Cuts V2 (photos/e-signature/comparaison) absents du plan = respectés. ✅
- **Placeholder scan** : code complet fourni pour modèles, enums, template, rules, index, callable, tests functions ; skeletons détaillés + fichiers-miroirs explicites pour PDF (T4) et UI (T6/T7) où reproduire ~centaines de lignes verbatim serait fragile — chaque skeleton donne le mapping de données exact et le fichier à calquer. À la charge de l'implémenteur de compléter en suivant le miroir ; la revue de tâche vérifie.
- **Type consistency** : `EtatDesLieux`/`EdlRoom`/`EdlElement`/`EdlMeterReadings` + enums `EtatDesLieuxType`/`EdlCondition` cohérents T1→T7. Payload callable (T3) ↔ repository `create` (T5) : enums envoyés en `sqlValue`, dates via `toTimestamp` — **point de vigilance explicite en T5 Step 3** (aligner le format date sur `callable_helpers.toTimestamp`).
- **Build vert par tâche** : chaque tâche compile et teste isolément ; les routes/UI (T6/T7) référencent des symboles créés en T1-T5. T2 (rules) et T3 (callable) sont backend, testés via vitest/émulateur.
- **Risques** : (a) format de conversion date Firestore↔Dart (T1/T5) — vérifier le helper existant ; (b) test `create` via callable en fake Firestore (T5) — mocker `FirebaseFunctions` ou se limiter aux lectures selon le patron receipts ; (c) API `pdf`/`MultiPage` (T4) — calquer `receipt_pdf_renderer.dart`. Tous signalés dans les tâches.
- **Déploiement** : functions manuel + rules/index — **reportés** (gel Actions, Plan A) ; à lister au récap post-merge.
