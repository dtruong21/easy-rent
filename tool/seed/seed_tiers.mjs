#!/usr/bin/env node
// Seed de landlords par palier d'abonnement — pour QA manuelle de l'UX
// tier-gated (plafonds simulateur, sections « Plan Pro », modales de limite).
//
// POURQUOI CE SCRIPT EXISTE
// -------------------------
// Le palier `paid` n'a AUCUN chemin applicatif : les règles Firestore figent
// `subscriptionTier` à la création et le rendent immuable côté client (« seule
// la Callable finalize peut upgrader », et finalize n'écrit que 'free'). Il
// n'existe pas encore d'IAP / webhook de paiement (FEAT-044, roadmap). Le SEUL
// moyen de voir l'app en tant qu'utilisateur `paid` aujourd'hui est une
// écriture serveur de confiance — c'est exactement ce que fait ce script via
// l'Admin SDK (qui bypasse les règles).
//
// SÉCURITÉ (garde-fou dur)
// ------------------------
// Ce script REFUSE de tourner s'il ne cible pas les émulateurs. Il crée de
// vrais comptes Auth + docs Firestore ; le lancer sur le projet réel
// créerait des utilisateurs `paid` en production. La présence de
// FIRESTORE_EMULATOR_HOST est obligatoire — sans elle, exit 1 immédiat.
//
// USAGE
// -----
//   1. Démarrer les émulateurs :
//        firebase emulators:start --only auth,firestore
//      (Ports par défaut : Firestore 8080, Auth 9099. firebase.json ne définit
//       pas de bloc `emulators` — les défauts s'appliquent. Adapter les
//       variables ci-dessous si vous en configurez un.)
//   2. Dans un autre terminal, depuis la racine du dépôt :
//        FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
//        FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//        node tool/seed/seed_tiers.mjs
//   3. Lancer l'app Flutter branchée sur les émulateurs et se connecter avec
//      les identifiants imprimés en fin de script.
//
//   Options :
//     --tier=free|paid   ne semer qu'un palier (défaut : les deux)
//     --project=<id>     projectId émulateur (défaut : easy-rent-54cd4, =
//                        celui de l'app, pour que les docs soient visibles)
//
// NOTE — palier `anonymous` : non semé ici. Un anon est défini par SA MÉTHODE
// de connexion (signInAnonymously côté client), pas reconstructible par
// l'Admin SDK de façon fidèle (un login par custom token donnerait
// isAnonymous=false côté client). Pour tester l'anonyme, utiliser le bouton
// « essai sans compte » de l'app — la CF handleNewUser provisionne le doc.

import { createRequire } from 'node:module';

// firebase-admin n'est pas une dépendance de la racine : on le résout depuis
// functions/node_modules (où il vit déjà en ^12.7.0), donc aucun `npm install`
// supplémentaire. createRequire ancré sur functions/package.json fait la
// résolution comme si on requérait depuis functions/.
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const admin = require('firebase-admin');

// --- Garde-fou production : émulateur obligatoire -------------------------
const EMU_FS = process.env.FIRESTORE_EMULATOR_HOST;
const EMU_AUTH = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!EMU_FS) {
  console.error(
    '\n⛔ FIRESTORE_EMULATOR_HOST non défini — refus de tourner.\n' +
    "   Ce script écrit de vrais comptes ; sans émulateur il viserait la PROD.\n" +
    '   Démarrer les émulateurs puis relancer avec la variable positionnée.\n' +
    '   Ex : FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 ' +
    'FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 node tool/seed/seed_tiers.mjs\n',
  );
  process.exit(1);
}
if (!EMU_AUTH) {
  console.error(
    '\n⛔ FIREBASE_AUTH_EMULATOR_HOST non défini — nécessaire pour créer les ' +
    'comptes Auth de test. Le positionner (défaut Auth : 127.0.0.1:9099).\n',
  );
  process.exit(1);
}

// --- Args -----------------------------------------------------------------
const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, '').split('=');
    return [k, v ?? true];
  }),
);
const PROJECT_ID = args.project || 'easy-rent-54cd4';
const ONLY_TIER = args.tier; // 'free' | 'paid' | undefined (= les deux)
if (ONLY_TIER && !['free', 'paid'].includes(ONLY_TIER)) {
  console.error(`⛔ --tier invalide : ${ONLY_TIER} (attendu : free | paid)`);
  process.exit(1);
}

// Doit correspondre à CURRENT_RGPD_VERSION dans
// functions/src/callable/finalize_anonymous_upgrade.ts — un doc « compte
// complet » sans consentement à la version courante serait incohérent.
const RGPD_VERSION = 'v3-2026-07';
const DEV_PASSWORD = 'seedpass123'; // mot de passe de test partagé (émulateur)

admin.initializeApp({ projectId: PROJECT_ID });
const auth = admin.auth();
const db = admin.firestore();

/**
 * Crée (ou réutilise, idempotent) un compte Auth email/password + son doc
 * landlords/{uid} au palier voulu. L'Admin SDK bypasse les règles Firestore,
 * donc il peut écrire subscriptionTier:'paid' — ce qu'aucun client ne peut.
 */
async function seedTier(tier) {
  const email = `${tier}@seed.test`;

  // Auth : upsert par email pour rendre le script rejouable sans erreur.
  let user;
  try {
    user = await auth.getUserByEmail(email);
  } catch {
    user = await auth.createUser({
      email,
      password: DEV_PASSWORD,
      emailVerified: true,
      displayName: `Seed ${tier}`,
    });
  }
  const uid = user.uid;

  const now = admin.firestore.FieldValue.serverTimestamp();
  // Forme alignée sur le doc écrit par la CF de provisioning + finalize :
  // compte complet, RGPD consenti, compteurs de plan à 0, non supprimé.
  await db.doc(`landlords/${uid}`).set(
    {
      id: uid,
      email,
      fullName: `Seed ${tier}`,
      isAnonymous: false,
      subscriptionTier: tier, // 'free' ou 'paid' (paid = impossible côté client)
      rgpdConsentAt: now,
      rgpdConsentVersion: RGPD_VERSION,
      activePropertiesCount: 0,
      activeTenantsCount: 0,
      activeLeasesCount: 0,
      deletedAt: null,
      createdAt: now,
      updatedAt: now,
    },
    { merge: true },
  );

  return { tier, email, uid };
}

async function main() {
  const tiers = ONLY_TIER ? [ONLY_TIER] : ['free', 'paid'];
  console.log(
    `\n🌱 Seed tiers sur l'émulateur (project=${PROJECT_ID}, ` +
    `Firestore=${EMU_FS}, Auth=${EMU_AUTH})\n`,
  );

  const results = [];
  for (const tier of tiers) {
    results.push(await seedTier(tier));
  }

  console.log('✅ Comptes de test prêts — se connecter dans l\'app :\n');
  for (const r of results) {
    console.log(`   • ${r.tier.toUpperCase().padEnd(4)}  ${r.email}  /  ${DEV_PASSWORD}   (uid ${r.uid})`);
  }
  console.log(
    '\nℹ️  Palier anonymous : passer par le bouton « essai sans compte » de ' +
    'l\'app (non semé — voir l\'en-tête du script).\n',
  );
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('⛔ Échec du seed :', err);
    process.exit(1);
  });
