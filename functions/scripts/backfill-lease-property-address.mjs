#!/usr/bin/env node
/**
 * Rattrapage de `leases.propertyAddress` — adresse complète du logement.
 *
 * ⚠️  DRY-RUN PAR DÉFAUT. Rien n'est écrit sans `--apply`.
 *
 * ## Pourquoi ce script existe
 *
 * `createLease` figeait `propertyAddress: property.address` — c'est-à-dire la
 * RUE SEULE, puisque `properties` porte `postalCode` et `city` dans des champs
 * distincts et que le formulaire n'y met en pratique que la rue. Les quittances
 * recopient ensuite `lease.propertyAddress` : leur champ « Logement : »
 * n'affichait donc pas la commune, alors que la loi du 6 juillet 1989 veut un
 * logement identifiable.
 *
 * Le correctif (composition dans `createLease`, cf.
 * `functions/src/utils/property_address.ts`) ne vaut que pour les baux CRÉÉS
 * ENSUITE. Les baux existants gardent la valeur tronquée et continueraient à
 * produire des quittances incomplètes : ce script les rattrape, à passer une
 * fois par base.
 *
 * ## Ce que ce script NE rattrape PAS
 *
 * Les QUITTANCES DÉJÀ ÉMISES. Leur `propertyAddress` est une snapshot légale
 * volontairement figée (`receipts.ts` : « jamais re-synchronisé même si les
 * entités sources sont modifiées ») et les Firestore rules posent
 * `allow update: if false` sur `receipts`. Elles resteront tronquées ; seules
 * les quittances émises APRÈS ce rattrapage porteront l'adresse complète.
 * C'est une conséquence assumée de l'immuabilité, pas un oubli du script.
 *
 * ## ⚠️  Une base à la fois
 *
 * ADR 0003 : la prod vit dans `(default)`, le staging dans `staging`. Ce
 * script ÉCRIT — il prend donc UNE seule base (`--database`), à relancer
 * explicitement pour chacune, plutôt qu'une liste où une faute de frappe
 * enverrait des écritures dans le mauvais environnement.
 *
 * ## Effet de bord attendu
 *
 * Le trigger `setUpdatedAtLeases` (déployé sur `(default)`) réagit à chaque
 * update et repose `updatedAt` : compter une écriture supplémentaire par bail
 * modifié. Aucun trigger ne touche aux quittances sur un update de bail (le
 * recompute `isStale` est branché sur `payments`), donc le rattrapage ne peut
 * pas marquer d'anciennes quittances comme révisées.
 *
 * Ce fichier vit HORS de `src/` volontairement : `tsconfig.json` ne compile que
 * `src/**`, donc il n'est jamais embarqué dans les functions déployées (une
 * migration ne doit jamais tourner au deploy). Même convention que
 * `purge-orphan-documents.mjs` et `backfill_active_properties_count.js`.
 *
 * Il importe en revanche la fonction de composition COMPILÉE
 * (`../lib/utils/property_address.js`) : c'est la même que celle qu'exécute
 * `createLease`, donc le rattrapage ne peut pas diverger de ce que produira le
 * prochain bail. Lance `npm run build` avant.
 *
 * ## Usage (depuis le répertoire `functions/`)
 *
 *   npm run build   # indispensable : le script lit lib/utils/property_address.js
 *
 *   # 1. Inspecter (n'écrit rien) :
 *   node scripts/backfill-lease-property-address.mjs --project easy-rent-54cd4 \
 *     --database "(default)"
 *
 *   # 2. Écrire pour de vrai, après avoir relu le rapport :
 *   node scripts/backfill-lease-property-address.mjs --project easy-rent-54cd4 \
 *     --database "(default)" --apply
 *
 * Options :
 *   --project <id>     projet Firebase (défaut : $GCLOUD_PROJECT)
 *   --database <id>    base Firestore visée (défaut : "(default)")
 *   --landlord <uid>   ne traite que les baux de ce bailleur (répétition
 *                      possible) — pour valider sur un compte avant la masse
 *   --include-deleted  traite aussi les baux soft-deleted (par défaut ignorés)
 *   --limit <n>        s'arrête après n baux à modifier (test de bout en bout)
 *   --apply            écrit réellement (sinon : dry-run)
 *
 * ## Auth — Application Default Credentials
 *
 *   gcloud auth application-default login
 *   gcloud auth application-default set-quota-project easy-rent-54cd4
 *
 * ⚠️  `gcloud auth login` ne suffit PAS : les identifiants de la CLI et les ADC
 * lus par les bibliothèques sont deux stores distincts.
 *
 * Alternative : GOOGLE_APPLICATION_CREDENTIALS vers un service account JSON.
 */

import admin from "firebase-admin";

import {composePropertyAddress} from "../lib/utils/property_address.js";

const BATCH_SIZE = 400; // < 500 (limite Firestore), marge pour les retries.

function parseArgs(argv) {
  const args = {
    project: process.env.GCLOUD_PROJECT ?? null,
    database: "(default)",
    landlords: [],
    includeDeleted: false,
    limit: Infinity,
    apply: false,
  };
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
    else if (arg === "--include-deleted") args.includeDeleted = true;
    else if (arg === "--project") args.project = argv[++i];
    else if (arg === "--database") args.database = argv[++i];
    else if (arg === "--landlord") args.landlords.push(argv[++i]);
    else if (arg === "--limit") args.limit = Number(argv[++i]);
    else {
      console.error(`Option inconnue : ${arg}`);
      process.exit(2);
    }
  }
  if (!args.project) {
    console.error("--project est requis (ou GCLOUD_PROJECT).");
    process.exit(2);
  }
  if (!args.database) {
    console.error("--database ne peut pas être vide.");
    process.exit(2);
  }
  if (!(args.limit > 0)) {
    console.error("--limit doit être un nombre > 0.");
    process.exit(2);
  }
  return args;
}

/** Traduit les échecs d'authentification en instructions actionnables. */
function explainAuthError(err) {
  const msg = String(err?.message ?? err);
  if (/default credentials/i.test(msg)) {
    return [
      "Application Default Credentials introuvables.",
      "",
      "  gcloud auth application-default login",
      "  gcloud auth application-default set-quota-project <projectId>",
      "",
      "Ou pointe GOOGLE_APPLICATION_CREDENTIALS vers un service account JSON.",
      "Note : `gcloud auth login` seul ne suffit PAS (store différent).",
    ].join("\n");
  }
  if (/quota project|billing|SERVICE_DISABLED/i.test(msg)) {
    return [
      "Identifiants OK mais projet de quota absent ou API désactivée :",
      "",
      "  gcloud auth application-default set-quota-project <projectId>",
    ].join("\n");
  }
  if (/permission|PERMISSION_DENIED|403/i.test(msg)) {
    return [
      "Identifiants OK mais droits insuffisants. Il faut la lecture Firestore",
      "et, pour --apply, l'écriture sur la collection `leases`.",
    ].join("\n");
  }
  if (/Cannot find module.*property_address/i.test(msg)) {
    return [
      "La fonction de composition compilée est absente. Depuis functions/ :",
      "",
      "  npm run build",
    ].join("\n");
  }
  return null;
}

async function main() {
  const args = parseArgs(process.argv);

  console.log("Rattrapage de leases.propertyAddress (adresse complète)");
  console.log(`  projet   : ${args.project}`);
  console.log(`  base     : ${args.database}`);
  console.log(
    `  bailleurs: ${args.landlords.length === 0 ? "tous" : args.landlords.join(", ")}`,
  );
  console.log(
    `  supprimés: ${args.includeDeleted ? "inclus" : "ignorés (baux actifs seulement)"}`,
  );
  if (args.limit !== Infinity) console.log(`  limite   : ${args.limit} baux`);
  console.log(
    `  mode     : ${args.apply ? "⚠️  APPLY (écriture réelle)" : "dry-run"}`,
  );
  console.log("");

  const app = admin.initializeApp({projectId: args.project});
  const db =
    args.database === "(default)" ?
      admin.firestore(app) :
      admin.firestore(app, args.database);

  // --- Biens : source de vérité de l'adresse, chargés en une passe.
  console.log("Lecture des biens…");
  let propertiesSnap;
  try {
    propertiesSnap = await db.collection("properties").get();
  } catch (err) {
    if (/NOT_FOUND|does not exist/i.test(String(err?.message ?? err))) {
      throw new Error(
        `Base Firestore introuvable : "${args.database}".\n` +
          "Vérifie la liste réelle des bases du projet :\n" +
          "  gcloud firestore databases list --project <projectId>\n" +
          "puis ajuste --database.",
      );
    }
    throw err;
  }
  const properties = new Map();
  for (const doc of propertiesSnap.docs) properties.set(doc.id, doc.data());
  console.log(`  ${properties.size} biens\n`);

  console.log("Lecture des baux…");
  const leasesSnap = await db.collection("leases").get();
  console.log(`  ${leasesSnap.size} baux\n`);

  // Garde-fou fail-closed : des baux mais aucun bien = signature d'une
  // mauvaise base ou de mauvais identifiants. Tous les baux seraient classés
  // « bien introuvable » et on repartirait sur un rapport vide et trompeur.
  if (properties.size === 0 && leasesSnap.size > 0) {
    console.error(
      `AUCUN bien alors que la base contient ${leasesSnap.size} baux — ` +
        "probablement une mauvaise base (--database) ou de mauvais " +
        "identifiants. Arrêt par sécurité.",
    );
    process.exit(1);
  }

  const landlordFilter =
    args.landlords.length === 0 ? null : new Set(args.landlords);

  const pending = [];
  let skippedDeleted = 0;
  let skippedOtherLandlord = 0;
  let unchanged = 0;
  const orphans = [];

  for (const doc of leasesSnap.docs) {
    const lease = doc.data();

    if (landlordFilter !== null && !landlordFilter.has(lease.landlordId)) {
      skippedOtherLandlord++;
      continue;
    }
    if (!args.includeDeleted && lease.deletedAt != null) {
      skippedDeleted++;
      continue;
    }

    const property = properties.get(lease.propertyId);
    if (property === undefined) {
      // Bien absent : on ne peut RIEN recomposer. On ne touche pas au bail —
      // écraser une adresse figée par une chaîne vide serait pire que la
      // laisser tronquée.
      orphans.push({leaseId: doc.id, propertyId: lease.propertyId});
      continue;
    }

    const composed = composePropertyAddress({
      address: property.address,
      postalCode: property.postalCode,
      city: property.city,
    });
    const current = typeof lease.propertyAddress === "string" ?
      lease.propertyAddress :
      "";

    if (composed === current) {
      unchanged++;
      continue;
    }
    // Sécurité : ne jamais APPAUVRIR un bail. Si la composition rendait moins
    // que ce qui est déjà stocké (bien vidé de son adresse depuis la création
    // du bail, par exemple), on signale sans écrire.
    if (composed === "") {
      orphans.push({
        leaseId: doc.id,
        propertyId: lease.propertyId,
        reason: "adresse composée vide",
      });
      continue;
    }

    pending.push({ref: doc.ref, leaseId: doc.id, current, composed});
    if (pending.length >= args.limit) break;
  }

  console.log(`  ${unchanged} baux déjà corrects`);
  if (skippedDeleted > 0) {
    console.log(`  ${skippedDeleted} baux soft-deleted ignorés`);
  }
  if (skippedOtherLandlord > 0) {
    console.log(`  ${skippedOtherLandlord} baux hors du filtre --landlord`);
  }
  console.log(`  ${pending.length} baux à mettre à jour\n`);

  for (const {leaseId, current, composed} of pending) {
    console.log(`  ${args.apply ? "ÉCRIT" : "à corriger"} ${leaseId}`);
    console.log(`    avant : ${current === "" ? "(vide)" : current}`);
    console.log(`    après : ${composed}`);
  }

  if (orphans.length > 0) {
    console.log(`\n${orphans.length} baux NON traités (à regarder à la main) :`);
    for (const o of orphans) {
      console.log(
        `  ${o.leaseId} → bien ${o.propertyId} : ${o.reason ?? "introuvable"}`,
      );
    }
  }

  if (!args.apply) {
    console.log("\nDry-run : rien n'a été écrit. Relance avec --apply.");
    return;
  }
  if (pending.length === 0) {
    console.log("\nRien à écrire.");
    return;
  }

  console.log("\nÉcriture…");
  let written = 0;
  for (let i = 0; i < pending.length; i += BATCH_SIZE) {
    const slice = pending.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    // `update` (et non `set(..., {merge})`) : échoue si le doc a disparu entre
    // la lecture et l'écriture, plutôt que de recréer un bail fantôme.
    for (const {ref, composed} of slice) {
      batch.update(ref, {propertyAddress: composed});
    }
    try {
      await batch.commit();
      written += slice.length;
      console.log(`  ${written}/${pending.length}`);
    } catch (err) {
      console.error(
        `  ÉCHEC du lot ${i}–${i + slice.length - 1} : ${err.message}`,
      );
      throw err;
    }
  }
  console.log(`\n${written} baux mis à jour.`);
  console.log(
    "\nRappel : les quittances DÉJÀ ÉMISES gardent l'adresse tronquée " +
      "(snapshot légale immuable). Seules les prochaines seront complètes.",
  );
}

main().catch((err) => {
  const hint = explainAuthError(err);
  if (hint) {
    console.error(`\n${hint}\n`);
    console.error(`(détail : ${err?.message ?? err})`);
  } else {
    console.error(err);
  }
  process.exit(1);
});
