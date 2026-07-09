/**
 * One-off backfill — FEAT-044 (Phase A).
 *
 * Recompute `landlords/{uid}.activePropertiesCount` from the live property docs
 * (non-deleted) for EXISTING accounts. New accounts already initialise the
 * counter to 0 at provisioning; only pre-existing landlords need this.
 *
 * MUST be run before the `createProperty` gate is trusted on existing data:
 * until an account's counter is set, the gate reads a missing counter as 0 and
 * would let an over-cap free account create more. Idempotent — safe to re-run.
 *
 * This file lives OUTSIDE `src/` on purpose: `tsconfig.json` only compiles
 * `src/**`, so it is never bundled into the deployed functions (a backfill must
 * never run on deploy). Plain CommonJS so it runs with `node` — no ts-node/tsx.
 *
 * Run (from the `functions/` directory), DRY RUN first:
 *   GOOGLE_CLOUD_PROJECT=<projectId> \
 *   GOOGLE_APPLICATION_CREDENTIALS=/abs/path/serviceAccount.json \
 *   node scripts/backfill_active_properties_count.js
 *
 * Then, to actually write:
 *   ... node scripts/backfill_active_properties_count.js --commit
 *
 * (Or point at the Firestore emulator with FIRESTORE_EMULATOR_HOST=localhost:8080.)
 */

const admin = require("firebase-admin");

const COMMIT = process.argv.includes("--commit");

admin.initializeApp();
const db = admin.firestore();

async function main() {
  const landlords = await db.collection("landlords").get();
  let checked = 0;
  let drift = 0;
  let written = 0;

  for (const doc of landlords.docs) {
    checked++;
    const uid = doc.id;
    const current = doc.get("activePropertiesCount");
    const agg = await db
      .collection("properties")
      .where("landlordId", "==", uid)
      .where("deletedAt", "==", null)
      .count()
      .get();
    const actual = agg.data().count;

    if (current === actual) continue;
    drift++;
    console.log(
      `${uid}: activePropertiesCount ${current === undefined ? "(absent)" : current} -> ${actual}`,
    );
    if (COMMIT) {
      await doc.ref.update({activePropertiesCount: actual});
      written++;
    }
  }

  console.log(
    `\n${checked} landlords checked, ${drift} needing update` +
      (COMMIT
        ? `, ${written} written.`
        : " (DRY RUN — re-run with --commit to write)."),
  );
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
