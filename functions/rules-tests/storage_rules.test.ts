/**
 * Tests des Storage Security Rules (`storage.rules`) — exécutés contre
 * l'émulateur Storage :
 *
 *   npm run test:rules   (depuis functions/ — wrappe firebase emulators:exec
 *                         --only firestore,storage)
 *
 * Créés suite à l'audit OWASP-04 : n'importe quel compte connecté — y compris
 * anonyme (création gratuite et illimitée) ou à email jamais vérifié — pouvait
 * déposer un nombre illimité d'objets de 50 Mio sous `documents/{son uid}/…`,
 * sous n'importe quel nom, dans le bucket PARTAGÉ prod/staging. Le quota
 * « documents » n'est appliqué que par le callable `createDocument`, qu'un
 * client peut ne jamais appeler. Les règles exigent désormais un compte non
 * anonyme à email de confiance (même condition que `hasTrustedEmail()` de
 * `firestore.rules`) et un nom d'objet au format RÉELLEMENT produit par le
 * client : `documents/{uid}/{docId Firestore, 20 car.}.{pdf|jpg|png|webp}`
 * (cf. `DocumentsRepository.upload`, extension = `extensionFromMime`).
 */

import {readFileSync} from "node:fs";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import type {RulesTestEnvironment} from "@firebase/rules-unit-testing";
import {
  deleteObject,
  getBytes,
  ref,
  updateMetadata,
  uploadBytes,
} from "firebase/storage";
import {afterAll, beforeAll, describe, it} from "vitest";

const LANDLORD_A = "landlord-a";
const LANDLORD_B = "landlord-b";

/** Plafond grossier de la règle : 50 Mio (= max de la grille des paliers). */
const MAX_BYTES = 50 * 1024 * 1024;

/**
 * Identifiant façon Firestore auto-ID : 20 caractères [A-Za-z0-9]. C'est
 * `_col.doc().id` côté client (`documents_repository.dart`).
 */
const DOC_ID = "a1B2c3D4e5F6g7H8i9J0";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-easyrent",
    storage: {rules: readFileSync("../storage.rules", "utf8")},
  });
});

afterAll(async () => {
  await env.cleanup();
});

// --- Contextes d'authentification ---------------------------------------
// Claims calqués sur ceux du jeton Firebase réel (cf. firestore_rules.test.ts).

type Token = Record<string, unknown>;

/** Email/mot de passe, email VÉRIFIÉ. */
const VERIFIED: Token = {
  email_verified: true,
  firebase: {sign_in_provider: "password"},
};
/** Email/mot de passe, email JAMAIS vérifié. */
const UNVERIFIED: Token = {
  email_verified: false,
  firebase: {sign_in_provider: "password"},
};
/** Claim `email_verified` absent (fail-closed attendu). */
const NO_CLAIM: Token = {firebase: {sign_in_provider: "password"}};
/** Google / Apple : `email_verified` retiré volontairement (provider de confiance). */
const GOOGLE: Token = {firebase: {sign_in_provider: "google.com"}};
const APPLE: Token = {firebase: {sign_in_provider: "apple.com"}};
const ANONYMOUS: Token = {firebase: {sign_in_provider: "anonymous"}};
/**
 * Compte anonyme dont le jeton porterait `email_verified: true` : cas
 * artificiel, mais la règle ne doit pas se contenter du claim.
 */
const ANONYMOUS_CLAIMING_VERIFIED: Token = {
  email_verified: true,
  firebase: {sign_in_provider: "anonymous"},
};

const storageOf = (uid: string, token: Token) =>
  env.authenticatedContext(uid, token).storage();

const bytes = (n: number) => new Uint8Array(n);

/** Téléverse comme le client : `putData(bytes, SettableMetadata(contentType))`. */
function upload(
  storage: ReturnType<typeof storageOf>,
  path: string,
  size = 16,
  contentType = "application/pdf",
) {
  return uploadBytes(ref(storage, path), bytes(size), {contentType});
}

const ownPdf = (uid: string) => `documents/${uid}/${DOC_ID}.pdf`;

describe("storage.rules — documents/{landlordId}/{docId}.{ext} (OWASP-04)", () => {
  // --- Cas nominal : le chemin EXACT produit par le client ----------------
  describe("cas nominal (chemin produit par DocumentsRepository.upload)", () => {
    it("email vérifié, son dossier, PDF → accepté", async () => {
      await assertSucceeds(
        upload(storageOf(LANDLORD_A, VERIFIED), ownPdf(LANDLORD_A)),
      );
    });

    // Extension = `extensionFromMime(mimeType)` : jpeg → `jpg`.
    it.each([
      ["application/pdf", "pdf", "p"],
      ["image/jpeg", "jpg", "j"],
      ["image/png", "png", "n"],
      ["image/webp", "webp", "w"],
    ])("type %s → %s accepté", async (contentType, ext, letter) => {
      const id = `${letter}${DOC_ID.slice(1)}`;
      await assertSucceeds(
        upload(
          storageOf(LANDLORD_A, VERIFIED),
          `documents/${LANDLORD_A}/${id}.${ext}`,
          16,
          contentType,
        ),
      );
    });

    it("compte Google (email_verified absent) → accepté", async () => {
      await assertSucceeds(
        upload(storageOf("g-user", GOOGLE), ownPdf("g-user")),
      );
    });

    it("compte Apple (email_verified absent) → accepté", async () => {
      await assertSucceeds(
        upload(storageOf("a-user", APPLE), ownPdf("a-user")),
      );
    });

    it("exactement 50 Mio → accepté (le plafond est inclusif)", async () => {
      await assertSucceeds(
        upload(
          storageOf("big-ok", VERIFIED),
          `documents/big-ok/${DOC_ID}.pdf`,
          MAX_BYTES,
        ),
      );
    });
  });

  // --- Identité --------------------------------------------------------------
  describe("identité", () => {
    it("compte ANONYME refusé", async () => {
      await assertFails(
        upload(storageOf("anon-1", ANONYMOUS), ownPdf("anon-1")),
      );
    });

    it("compte anonyme portant email_verified:true refusé", async () => {
      await assertFails(
        upload(
          storageOf("anon-2", ANONYMOUS_CLAIMING_VERIFIED),
          ownPdf("anon-2"),
        ),
      );
    });

    it("email/mot de passe NON vérifié refusé", async () => {
      await assertFails(
        upload(storageOf("unv-1", UNVERIFIED), ownPdf("unv-1")),
      );
    });

    it("claim email_verified absent (fail-closed) refusé", async () => {
      await assertFails(
        upload(storageOf("noclaim-1", NO_CLAIM), ownPdf("noclaim-1")),
      );
    });

    it("non authentifié refusé", async () => {
      await assertFails(
        upload(env.unauthenticatedContext().storage(), ownPdf(LANDLORD_A)),
      );
    });

    it("un bailleur ne peut pas écrire dans le dossier d'un AUTRE", async () => {
      await assertFails(
        upload(storageOf(LANDLORD_B, VERIFIED), ownPdf(LANDLORD_A)),
      );
    });
  });

  // --- Nom d'objet -----------------------------------------------------------
  describe("nom d'objet contraint au format du client", () => {
    const own = `documents/${LANDLORD_A}`;

    it.each([
      ["id trop court", `${own}/abc123.pdf`],
      ["id trop long (21 car.)", `${own}/${DOC_ID}X.pdf`],
      ["id avec tiret", `${own}/a1B2c3D4e5F6g7H8i9-0.pdf`],
      ["sans extension", `${own}/${DOC_ID}`],
      ["extension non prévue (.exe)", `${own}/${DOC_ID}.exe`],
      ["extension non prévue (.html)", `${own}/${DOC_ID}.html`],
      ["extension .jpeg (le client produit .jpg)", `${own}/${DOC_ID}.jpeg`],
      ["extension en majuscules", `${own}/${DOC_ID}.PDF`],
      ["double extension", `${own}/${DOC_ID}.pdf.exe`],
      ["nom libre", `${own}/mon-bail-signe.pdf`],
      ["sous-dossier", `${own}/sub/${DOC_ID}.pdf`],
      ["sous-dossier profond", `${own}/a/b/c/${DOC_ID}.pdf`],
    ])("%s → refusé", async (_label, path) => {
      await assertFails(upload(storageOf(LANDLORD_A, VERIFIED), path));
    });

    it("hors du préfixe documents/ → refusé (deny-by-default)", async () => {
      await assertFails(
        upload(
          storageOf(LANDLORD_A, VERIFIED),
          `uploads/${LANDLORD_A}/${DOC_ID}.pdf`,
        ),
      );
    });
  });

  // --- Taille et type : inchangés --------------------------------------------
  describe("taille et type (inchangés)", () => {
    it("50 Mio + 1 octet → refusé", async () => {
      await assertFails(
        upload(
          storageOf(LANDLORD_A, VERIFIED),
          ownPdf(LANDLORD_A),
          MAX_BYTES + 1,
        ),
      );
    });

    it("content-type hors liste (text/html) → refusé", async () => {
      await assertFails(
        upload(
          storageOf(LANDLORD_A, VERIFIED),
          ownPdf(LANDLORD_A),
          16,
          "text/html",
        ),
      );
    });

    it("content-type exécutable (application/x-msdownload) → refusé", async () => {
      await assertFails(
        upload(
          storageOf(LANDLORD_A, VERIFIED),
          ownPdf(LANDLORD_A),
          16,
          "application/x-msdownload",
        ),
      );
    });
  });

  // --- Lecture / update / delete : inchangés ---------------------------------
  describe("lecture, mise à jour et suppression (inchangées : interdites)", () => {
    const seededPath = `documents/seeded-owner/${DOC_ID}.pdf`;

    beforeAll(async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await uploadBytes(ref(ctx.storage(), seededPath), bytes(8), {
          contentType: "application/pdf",
        });
        // Témoin : l'objet existe bien — sans quoi les refus ci-dessous
        // pourraient n'être que des « objet introuvable ».
        await getBytes(ref(ctx.storage(), seededPath));
      });
    });

    it("le propriétaire ne peut PAS lire (download via URL signée serveur)", async () => {
      await assertFails(
        getBytes(ref(storageOf("seeded-owner", VERIFIED), seededPath)),
      );
    });

    // NB : l'émulateur évalue TOUT upload comme `create`, même sur un nom déjà
    // pris (firebase-tools, storage/files.js → RulesetOperationMethod.CREATE),
    // alors que la production l'évalue comme `update`. L'écrasement par upload
    // n'est donc pas testable ici ; on exerce `update` via la mise à jour des
    // métadonnées (PATCH), qui passe bien par la méthode `update`.
    it("le propriétaire ne peut PAS modifier un objet existant (update)", async () => {
      await assertFails(
        updateMetadata(ref(storageOf("seeded-owner", VERIFIED), seededPath), {
          contentType: "image/png",
        }),
      );
    });

    it("le propriétaire ne peut PAS supprimer un objet (delete)", async () => {
      await assertFails(
        deleteObject(ref(storageOf("seeded-owner", VERIFIED), seededPath)),
      );
    });

    it("un autre bailleur ne peut PAS lire", async () => {
      await assertFails(
        getBytes(ref(storageOf(LANDLORD_B, VERIFIED), seededPath)),
      );
    });
  });
});
