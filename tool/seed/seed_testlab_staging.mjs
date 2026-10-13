#!/usr/bin/env node
// Seed du compte de test Test Lab (Robo) sur la base `staging`.
//
// POURQUOI CE SCRIPT EXISTE
// -------------------------
// Le build Android de test (`MOBILE_STAGING`, cf. docs/MOBILE.md § Test Lab)
// se connecte automatiquement avec un compte staging-only. Ce script le
// prépare de bout en bout, sans passer par l'inscription web :
//   1. compte Auth email/mot de passe (Auth est partagée prod/staging),
//      email marqué vérifié, mot de passe aléatoire (tourne à chaque run) ;
//   2. doc `landlords/{uid}` dans la base `staging` UNIQUEMENT (profil complet,
//      palier `paid` pour que Robo explore sans modale de limite) ;
//   3. données métier créées via les VRAIES callables, avec l'Origin de l'app
//      staging web → routées vers `staging` par `dbForRequest` (compteurs,
//      quittances PDF… identiques à un usage réel) ;
//   4. écrit `dart-defines.testlab.json` (gitignoré) avec les identifiants.
//      Le mot de passe n'est jamais affiché.
//
// SÉCURITÉ (garde-fous durs)
// --------------------------
// - Le compte ne doit JAMAIS exister en prod : si `landlords/{uid}` existe
//   dans `(default)`, refus (le routage mobile par compte l'y enverrait).
// - Les écritures Admin ne visent que la base `staging` ; `(default)` n'est
//   que lue (garde ci-dessus).
// - Projet réel : flag `--yes-staging` obligatoire.
// - Mode émulateur (vérification locale) : si FIRESTORE_EMULATOR_HOST est
//   posé, SEED_AUTH_REST_BASE et SEED_FUNCTIONS_BASE doivent l'être aussi
//   (jamais d'émulateur Firestore mélangé aux vraies Functions) ; le fichier
//   dart-defines n'est alors pas écrit.
//
// USAGE (projet réel, depuis la racine du dépôt)
// ----------------------------------------------
//   gcloud auth application-default login   # une fois, compte owner
//   node tool/seed/seed_testlab_staging.mjs --yes-staging
//
//   Options :
//     --email=<adresse>   compte de test (défaut : testlab.robo@example.com)
//
// USAGE (émulateurs, ports alternatifs de firebase.altports.local.json)
// ---------------------------------------------------------------------
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8081 \
//   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9098 \
//   SEED_AUTH_REST_BASE=http://127.0.0.1:9098/identitytoolkit.googleapis.com \
//   SEED_FUNCTIONS_BASE=http://127.0.0.1:5002/easy-rent-54cd4/europe-west1 \
//   node tool/seed/seed_testlab_staging.mjs

import { createRequire } from 'node:module';
import { randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

// firebase-admin vit dans functions/node_modules (cf. seed_tiers.mjs).
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const PROJECT_ID = 'easy-rent-54cd4';
const STAGING_DATABASE_ID = 'staging';
// Doit rester égal à STAGING_ORIGIN (functions/src/utils/db_router.ts).
const STAGING_ORIGIN = 'https://app.staging.baillan.com';
// Clé API web publique, lue dans lib/firebase_options.dart (pas recopiée ici).
const WEB_API_KEY = readFileSync(new URL('../../lib/firebase_options.dart', import.meta.url), 'utf8')
  .match(/FirebaseOptions web = FirebaseOptions\(\s*apiKey: '([^']+)'/)?.[1];
// Doit rester égal à CURRENT_RGPD_VERSION
// (functions/src/callable/finalize_anonymous_upgrade.ts).
const RGPD_VERSION = 'v3-2026-07';
const DEFINES_EXAMPLE = new URL('../../dart-defines.testlab.example.json', import.meta.url);
const DEFINES_OUT = new URL('../../dart-defines.testlab.json', import.meta.url);

// --- Args & mode ------------------------------------------------------------
const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, '').split('=');
    return [k, v ?? true];
  }),
);
const EMAIL = args.email || 'testlab.robo@example.com';
const EMULATOR = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const AUTH_REST_BASE = process.env.SEED_AUTH_REST_BASE || 'https://identitytoolkit.googleapis.com';
const FUNCTIONS_BASE =
  process.env.SEED_FUNCTIONS_BASE || `https://europe-west1-${PROJECT_ID}.cloudfunctions.net`;

function fail(message) {
  console.error(`\n⛔ ${message}\n`);
  process.exit(1);
}

if (EMULATOR) {
  if (!process.env.FIREBASE_AUTH_EMULATOR_HOST || !process.env.SEED_AUTH_REST_BASE || !process.env.SEED_FUNCTIONS_BASE) {
    fail(
      'Mode émulateur incomplet : FIREBASE_AUTH_EMULATOR_HOST, SEED_AUTH_REST_BASE ' +
        'et SEED_FUNCTIONS_BASE sont requis avec FIRESTORE_EMULATOR_HOST.',
    );
  }
} else {
  if (process.env.FIREBASE_AUTH_EMULATOR_HOST || process.env.SEED_AUTH_REST_BASE || process.env.SEED_FUNCTIONS_BASE) {
    fail('Variables d\'émulateur partielles sans FIRESTORE_EMULATOR_HOST — refus (mélange réel/émulateur).');
  }
  if (!args['yes-staging']) {
    fail('Projet réel : relancer avec --yes-staging (écrit dans la base `staging` et l\'Auth partagée).');
  }
}

if (!WEB_API_KEY) fail('Clé API web introuvable dans lib/firebase_options.dart.');

const app = initializeApp({ projectId: PROJECT_ID });
const auth = getAuth(app);
const prodDb = getFirestore(app); // lecture seule (garde « jamais en prod »)
const stagingDb = getFirestore(app, STAGING_DATABASE_ID);

// --- 1. Compte Auth ---------------------------------------------------------
async function findAuthUid() {
  try {
    return (await auth.getUserByEmail(EMAIL)).uid;
  } catch (err) {
    if (err?.code === 'auth/user-not-found') return null;
    throw err;
  }
}

/** Refuse tout compte qui a un doc landlord en prod — AVANT d'y toucher. */
async function assertNotInProd(uid) {
  if ((await prodDb.doc(`landlords/${uid}`).get()).exists) {
    fail(
      `landlords/${uid} existe dans (default) = PROD. Ce compte ne peut pas servir de ` +
        'compte de test staging (le routage mobile par compte l\'enverrait en prod). ' +
        'Choisir un autre --email. Rien n\'a été modifié.',
    );
  }
}

async function upsertAuthUser(password) {
  const existingUid = await findAuthUid();
  if (existingUid) {
    // Garde avant updateUser : ne jamais changer le mot de passe d'un compte prod.
    await assertNotInProd(existingUid);
    await auth.updateUser(existingUid, { password, emailVerified: true });
    return { uid: existingUid, created: false };
  }
  const user = await auth.createUser({
    email: EMAIL,
    password,
    emailVerified: true,
    displayName: 'Robo Test Lab',
  });
  await assertNotInProd(user.uid);
  return { uid: user.uid, created: true };
}

// --- 2. Doc landlord staging ------------------------------------------------
async function upsertStagingLandlord(uid) {
  const ref = stagingDb.doc(`landlords/${uid}`);
  const snap = await ref.get();
  const now = FieldValue.serverTimestamp();
  // Forme alignée sur le doc écrit par l'inscription (auth_repository.dart) ;
  // adresse + nom requis pour générer quittances et EDL.
  await ref.set(
    {
      id: uid,
      email: EMAIL,
      fullName: 'Robo Test Lab',
      phone: null,
      address: '5 avenue du Bailleur, 75008 Paris',
      isAnonymous: false,
      subscriptionTier: 'paid',
      anonExpiresAt: null,
      rgpdConsentAt: now,
      rgpdConsentVersion: RGPD_VERSION,
      deletedAt: null,
      updatedAt: now,
      ...(snap.exists
        ? {}
        : { activePropertiesCount: 0, activeTenantsCount: 0, activeLeasesCount: 0, createdAt: now }),
    },
    { merge: true },
  );
  return (await ref.get()).data();
}

// --- 3. Données métier via les callables -------------------------------------
async function signIn(password) {
  const res = await fetch(`${AUTH_REST_BASE}/v1/accounts:signInWithPassword?key=${WEB_API_KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Referer: `${STAGING_ORIGIN}/` },
    body: JSON.stringify({ email: EMAIL, password, returnSecureToken: true }),
  });
  const json = await res.json();
  if (!json.idToken) throw new Error(`connexion refusée : ${json.error?.message ?? res.status}`);
  return json.idToken;
}

function callableClient(idToken) {
  return async function call(name, data) {
    const res = await fetch(`${FUNCTIONS_BASE}/${name}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${idToken}`,
        // Route vers `staging` (dbForRequest, routage web par Origin).
        Origin: STAGING_ORIGIN,
      },
      body: JSON.stringify({ data }),
    });
    const json = await res.json().catch(() => ({}));
    if (!res.ok || json.error) throw new Error(`${name} : ${JSON.stringify(json.error ?? res.status)}`);
    return json.result;
  };
}

/** 1er jour du mois courant décalé de [offset] mois, en ISO UTC. */
function monthStart(offset) {
  const d = new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + offset, 1)).toISOString();
}

/** Dernier jour du mois courant décalé de [offset] mois, en ISO UTC. */
function monthEnd(offset) {
  const d = new Date();
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + offset + 1, 0)).toISOString();
}

async function seedBusinessData(call) {
  const property = (name, address, type = 'appartement') =>
    call('createProperty', {
      name, address, postalCode: '75011', city: 'Paris', type,
      hasElevator: false, furnished: false, isNewProperty: false,
    });
  const p1 = await property('Studio Lilas', '12 rue des Lilas');
  const p2 = await property('T3 Montparnasse', '128 boulevard du Montparnasse');
  const p3 = await property('Maison Vincennes', '4 allée des Tilleuls', 'maison');
  await property('T2 Bastille', '1 rue de la Roquette'); // vacant

  const tenant = (firstName, lastName, email, phone) =>
    call('createTenant', { firstName, lastName, email, ...(phone ? { phone } : {}) });
  const t1 = await tenant('Marie', 'Locataire', 'marie.locataire@example.com', '06 12 34 56 78');
  const t2 = await tenant('Jean-Baptiste', 'Longuenomdefamille', 'jb.longuenom@example.com');
  const t3 = await tenant('Sophie', 'Martin', 'sophie.martin@example.com', '07 00 00 00 00');
  await tenant('Paul', 'Candidat', 'paul.candidat@example.com'); // sans bail

  const lease = (propertyId, tenantId, rent, charges, startDate) =>
    call('createLease', {
      propertyId, tenantId, rentAmountCents: rent, chargesAmountCents: charges, startDate,
      leaseType: 'unfurnished', paymentDay: 5, paymentMethod: 'virement',
      status: 'active', chargeMode: 'provisions',
    });
  const l1 = await lease(p1.propertyId, t1.tenantId, 75000, 5000, monthStart(-1));
  const l2 = await lease(p2.propertyId, t2.tenantId, 124500, 15000, monthStart(-3));
  await lease(p3.propertyId, t3.tenantId, 180000, 0, monthStart(-12)); // sans paiement → en retard

  async function payAndReceipt(leaseId, rent, charges, offset) {
    const payment = await call('createPayment', {
      leaseId, rentAmountCents: rent, chargesAmountCents: charges,
      periodStart: monthStart(offset), periodEnd: monthEnd(offset), paidAt: monthEnd(offset),
      paymentMethod: 'virement',
    });
    await call('generateReceipt', { leaseId, paymentIds: [payment.paymentId] });
  }
  await payAndReceipt(l1.leaseId, 75000, 5000, -1);
  await payAndReceipt(l2.leaseId, 124500, 15000, -3);
  await payAndReceipt(l2.leaseId, 124500, 15000, -2);
  await payAndReceipt(l2.leaseId, 124500, 15000, -1);
}

// --- 4. dart-defines --------------------------------------------------------
function writeDefines(password) {
  const defines = JSON.parse(readFileSync(DEFINES_EXAMPLE, 'utf8'));
  defines.TEST_AUTO_LOGIN_EMAIL = EMAIL;
  defines.TEST_AUTO_LOGIN_PASSWORD = password;
  writeFileSync(DEFINES_OUT, `${JSON.stringify(defines, null, 2)}\n`, { mode: 0o600 });
}

async function main() {
  console.log(`\n🌱 Seed Test Lab — ${EMULATOR ? 'ÉMULATEUR' : 'projet réel'}, base \`${STAGING_DATABASE_ID}\`, compte ${EMAIL}\n`);

  const password = randomBytes(18).toString('base64url');
  // Garde « jamais en prod » incluse, avant toute modification du compte.
  const { uid, created } = await upsertAuthUser(password);

  const landlord = await upsertStagingLandlord(uid);
  const alreadySeeded = (landlord.activePropertiesCount ?? 0) > 0;
  if (alreadySeeded) {
    console.log(`• Données déjà présentes (${landlord.activePropertiesCount} biens) — pas de nouveau seed.`);
  } else {
    await seedBusinessData(callableClient(await signIn(password)));
    console.log('• Données créées : 4 biens, 4 locataires, 3 baux, 4 paiements + quittances.');
  }

  if (EMULATOR) {
    console.log('• Mode émulateur : dart-defines.testlab.json non écrit.');
  } else {
    writeDefines(password);
    console.log('• dart-defines.testlab.json écrit (gitignoré, mot de passe renouvelé).');
  }
  console.log(`\n✅ Compte ${created ? 'créé' : 'mis à jour'} — uid ${uid}\n`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('⛔ Échec du seed :', err);
    process.exit(1);
  });
