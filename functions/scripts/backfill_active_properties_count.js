/**
 * One-off backfill — FEAT-044 (Phase A).
 *
 * Recompute the three plan counters on `landlords/{uid}` from live docs
 * (non-deleted) for EXISTING accounts:
 *   - activePropertiesCount = properties (deletedAt == null)
 *   - activeTenantsCount    = tenants    (deletedAt == null)
 *   - activeLeasesCount     = leases     (status == 'active' && deletedAt == null)
 * New accounts initialise these to 0 at provisioning; only pre-existing
 * landlords need this.
 *
 * MUST be run before the create gates are trusted on existing data: until an
 * account's counters are set, a gate reads a missing counter as 0 and would let
 * an over-cap free account create more. Idempotent — safe to re-run.
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

async function activeCount(uid, collection, statusActive) {
  let q = db
    .collection(collection)
    .where("landlordId", "==", uid)
    .where("deletedAt", "==", null);
  if (statusActive) q = q.where("status", "==", "active");
  const agg = await q.count().get();
  return agg.data().count;
}

async function main() {
  const landlords = await db.collection("landlords").get();
  let checked = 0;
  let drift = 0;
  let written = 0;

  for (const doc of landlords.docs) {
    checked++;
    const uid = doc.id;
    const targets = {
      activePropertiesCount: await activeCount(uid, "properties", false),
      activeTenantsCount: await activeCount(uid, "tenants", false),
      activeLeasesCount: await activeCount(uid, "leases", true),
    };

    const update = {};
    for (const [field, actual] of Object.entries(targets)) {
      const current = doc.get(field);
      if (current === actual) continue;
      console.log(
        `${uid}: ${field} ${current === undefined ? "(absent)" : current} -> ${actual}`,
      );
      update[field] = actual;
    }

    if (Object.keys(update).length === 0) continue;
    drift++;
    if (COMMIT) {
      await doc.ref.update(update);
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
