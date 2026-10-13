#!/usr/bin/env node
/**
 * Purge des objets Storage orphelins sous `documents/`.
 *
 * ⚠️  DRY-RUN PAR DÉFAUT. Rien n'est supprimé sans `--apply`.
 *
 * ## Pourquoi ce script existe
 *
 * `storage.rules` pose `allow delete: if false` sur `documents/**`. Le
 * nettoyage vivait côté client (`documents_repository.dart`) : il était donc
 * TOUJOURS refusé et avalé par un catch. Chaque document supprimé — et chaque
 * upload dont le `createDocument` a échoué — a laissé son fichier dans le
 * bucket. Le correctif (purge serveur dans `softDeleteEntity` /
 * `createDocument`) arrête l'hémorragie mais ne rattrape PAS l'existant :
 * c'est le rôle de ce script, à passer une fois.
 *
 * ## ⚠️  Le bucket est PARTAGÉ entre prod et staging
 *
 * Les deux environnements écrivent dans `documents/` du même bucket
 * (ADR 0003 — l'isolation Storage est un risque résiduel assumé), MAIS
 * depuis ADR 0003 leurs documents Firestore vivent dans des bases
 * DIFFÉRENTES (`(default)` en prod, `staging` en staging).
 *
 * Conséquence : un script qui ne lirait que `(default)` classerait TOUS les
 * fichiers de staging comme orphelins et les supprimerait. Ce script
 * interroge donc TOUTES les bases passées via `--databases` et ne supprime
 * qu'un objet référencé par AUCUNE d'entre elles. Vérifie cette liste avant
 * de lancer — sur une branche antérieure à ADR 0003 il n'y a qu'une base.
 *
 * ## Est orphelin un objet dont, dans TOUTES les bases :
 *   - aucun document ne porte ce `storagePath`, OU
 *   - le document qui le porte est soft-deleted ET n'est pas sous legalHold.
 * Un document sous `legalHold` est TOUJOURS conservé (rétention légale, même
 * soft-deleted).
 *
 * Ce fichier vit HORS de `src/` volontairement : `tsconfig.json` ne compile que
 * `src/**`, donc il n'est jamais embarqué dans les functions déployées (une
 * purge ne doit jamais tourner au deploy). Même convention que
 * `backfill_active_properties_count.js`.
 *
 * ## Usage (depuis le répertoire `functions/`)
 *
 *   # 1. Inspecter (n'écrit rien) :
 *   GOOGLE_APPLICATION_CREDENTIALS=/abs/path/sa.json \
 *   node scripts/purge-orphan-documents.mjs --project easy-rent-54cd4 \
 *     --databases "(default),staging"
 *
 *   # 2. Supprimer pour de vrai, après avoir relu le rapport :
 *   GOOGLE_APPLICATION_CREDENTIALS=/abs/path/sa.json \
 *   node scripts/purge-orphan-documents.mjs --project easy-rent-54cd4 \
 *     --databases "(default),staging" --apply
 *
 * Options :
 *   --project <id>       projet Firebase (défaut : $GCLOUD_PROJECT)
 *   --bucket <nom>       bucket Storage (défaut :
 *                        `<project>.firebasestorage.app`)
 *   --databases <liste>  bases Firestore à interroger, séparées par des
 *                        virgules (défaut : "(default)")
 *   --older-than <h>     n'examine que les objets plus vieux que N heures
 *                        (défaut : 24). Garde-fou anti-race : un upload en
 *                        cours n'a pas encore son doc Firestore et
 *                        ressemblerait à un orphelin.
 *   --apply              supprime réellement (sinon : dry-run)
 *
 * ## Auth — Application Default Credentials
 *
 *   gcloud auth application-default login
 *   gcloud auth application-default set-quota-project easy-rent-54cd4
 *
 * ⚠️  `gcloud auth login` ne suffit PAS : les identifiants de la CLI et les ADC
 * lus par les bibliothèques sont deux stores distincts. Être connecté dans
 * `gcloud auth list` alors que l'ADC est absent donne « Could not load the
 * default credentials ».
 *
 * Alternative : GOOGLE_APPLICATION_CREDENTIALS vers un service account JSON.
 */

import admin from "firebase-admin";

function parseArgs(argv) {
  const args = {
    project: process.env.GCLOUD_PROJECT ?? null,
    bucket: null,
    databases: ["(default)"],
    olderThanHours: 24,
    apply: false,
  };
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
    else if (arg === "--project") args.project = argv[++i];
    else if (arg === "--bucket") args.bucket = argv[++i];
    else if (arg === "--databases") {
      args.databases = argv[++i].split(",").map((d) => d.trim()).filter(Boolean);
    } else if (arg === "--older-than") {
      args.olderThanHours = Number(argv[++i]);
    } else {
      console.error(`Option inconnue : ${arg}`);
      process.exit(2);
    }
  }
  if (!args.project) {
    console.error("--project est requis (ou GCLOUD_PROJECT).");
    process.exit(2);
  }
  if (!Number.isFinite(args.olderThanHours) || args.olderThanHours < 0) {
    console.error("--older-than doit être un nombre d'heures >= 0.");
    process.exit(2);
  }
  // Convention Firebase actuelle. Les projets antérieurs à ~2024 utilisent
  // `<project>.appspot.com` — d'où `--bucket` pour forcer.
  args.bucket ??= `${args.project}.firebasestorage.app`;
  return args;
}

/**
 * Traduit les échecs d'authentification en instructions actionnables. Sans ça
 * on ne récolte qu'un « Could not load the default credentials » opaque : les
 * identifiants `gcloud auth login` (CLI) et les Application Default
 * Credentials (bibliothèques) sont DEUX stores distincts — être connecté au
 * premier ne fournit rien au second.
 */
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
      "et, pour --apply, `storage.objects.delete` sur le bucket.",
    ].join("\n");
  }
  return null;
}

/**
 * Chemins à CONSERVER selon une base : tout document non supprimé, plus tout
 * document sous legalHold (même soft-deleted — rétention légale).
 */
async function protectedPathsFor(app, databaseId) {
  const db =
    databaseId === "(default)" ?
      admin.firestore(app) :
      admin.firestore(app, databaseId);

  let snap;
  try {
    snap = await db.collection("documents").get();
  } catch (err) {
    if (/NOT_FOUND|does not exist/i.test(String(err?.message ?? err))) {
      // Fail-closed BRUYANT : si on avalait ça en « 0 chemin protégé », tous
      // les fichiers de cette base seraient classés orphelins et supprimés.
      throw new Error(
        `Base Firestore introuvable : "${databaseId}".\n` +
          "Vérifie la liste réelle des bases du projet :\n" +
          "  gcloud firestore databases list --project <projectId>\n" +
          "puis ajuste --databases. NE LANCE PAS --apply avec une base " +
          "manquante : ses fichiers seraient vus comme orphelins.",
      );
    }
    throw err;
  }
  const keep = new Set();
  for (const doc of snap.docs) {
    const data = doc.data();
    const path = data.storagePath;
    if (typeof path !== "string" || path === "") continue;
    const isDeleted = data.deletedAt != null;
    const legalHold = data.legalHold === true;
    if (!isDeleted || legalHold) keep.add(path);
  }
  console.log(
    `  base ${databaseId} : ${snap.size} documents, ${keep.size} chemins à conserver`,
  );
  return keep;
}

async function main() {
  const args = parseArgs(process.argv);

  console.log("Purge des objets Storage orphelins sous documents/");
  console.log(`  projet      : ${args.project}`);
  console.log(`  bucket      : ${args.bucket}`);
  console.log(`  bases       : ${args.databases.join(", ")}`);
  console.log(`  plus vieux que : ${args.olderThanHours} h`);
  console.log(
    `  mode        : ${args.apply ? "⚠️  APPLY (suppression réelle)" : "dry-run"}`,
  );
  console.log("");

  const app = admin.initializeApp({
    projectId: args.project,
    storageBucket: args.bucket,
  });

  console.log("Lecture des documents Firestore…");
  const keep = new Set();
  for (const databaseId of args.databases) {
    for (const path of await protectedPathsFor(app, databaseId)) keep.add(path);
  }
  console.log(`  → ${keep.size} chemins protégés au total\n`);

  console.log("Parcours du bucket…");
  const [files] = await admin.storage().bucket().getFiles({prefix: "documents/"});

  // Garde-fou : 0 chemin protégé alors que le bucket contient des objets =
  // signature d'une mauvaise base ou de mauvais identifiants, et TOUT serait
  // classé orphelin. On refuse d'aller plus loin.
  // Le test porte sur `files.length` et pas seulement sur `keep.size` : un
  // bucket vide avec 0 document est un état parfaitement cohérent (feature
  // jamais utilisée), pas une anomalie — il ne doit pas déclencher l'alarme.
  if (keep.size === 0 && files.length > 0) {
    console.error(
      `AUCUN chemin protégé alors que le bucket contient ${files.length} ` +
        "objets — probablement une mauvaise base (--databases) ou de mauvais " +
        "identifiants. Arrêt par sécurité : tout aurait été classé orphelin.",
    );
    process.exit(1);
  }

  const cutoff = Date.now() - args.olderThanHours * 3600 * 1000;

  const orphans = [];
  let tooRecent = 0;
  let bytesReclaimed = 0;
  for (const file of files) {
    if (keep.has(file.name)) continue;
    const created = Date.parse(file.metadata.timeCreated ?? "");
    if (Number.isFinite(created) && created > cutoff) {
      tooRecent++; // upload possiblement en vol — on n'y touche pas
      continue;
    }
    orphans.push(file);
    bytesReclaimed += Number(file.metadata.size ?? 0);
  }

  console.log(`  ${files.length} objets sous documents/`);
  console.log(`  ${tooRecent} ignorés (trop récents)`);
  console.log(
    `  ${orphans.length} orphelins — ${(bytesReclaimed / 1024 / 1024).toFixed(1)} Mio récupérables\n`,
  );

  for (const file of orphans) {
    console.log(
      `  ${args.apply ? "SUPPRIME" : "orphelin"} ${file.name} ` +
        `(${file.metadata.size} o, créé ${file.metadata.timeCreated})`,
    );
  }

  if (!args.apply) {
    console.log("\nDry-run : rien n'a été supprimé. Relance avec --apply.");
    return;
  }

  console.log("\nSuppression…");
  let deleted = 0;
  let failed = 0;
  for (const file of orphans) {
    try {
      await file.delete({ignoreNotFound: true});
      deleted++;
    } catch (err) {
      failed++;
      console.error(`  ÉCHEC ${file.name} : ${err.message}`);
    }
  }
  console.log(`\n${deleted} supprimés, ${failed} en échec.`);
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
