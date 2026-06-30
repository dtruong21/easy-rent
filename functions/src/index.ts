/**
 * EasyRent — Cloud Functions entry point.
 *
 * Region par défaut : europe-west1 (configurée dans firebase.json).
 * Chaque trigger / callable est défini dans son propre module sous
 * `src/<domain>/` et ré-exporté ici pour que `firebase deploy --only functions`
 * les voie.
 *
 * FEAT-019 — Phase 1 backend foundations (handleNewUser + setUpdatedAt
 * + softDelete + lease/payment cross-entity callables + recompute stale).
 * Phase 2 ajoutera generate/void/markSent receipts + create document.
 */

import * as admin from "firebase-admin";
import {setGlobalOptions} from "firebase-functions/v2";

// Init Admin SDK une seule fois pour tous les modules.
admin.initializeApp();

// Garde-fou coût : pas plus de 10 conteneurs concurrents par défaut.
// Sur-ajuster par fonction si workload nécessite (en runWith).
setGlobalOptions({
  region: "europe-west1",
  maxInstances: 10,
});

// ---------- Auth ----------
export {handleNewUser} from "./auth/handle_new_user";

// ---------- Triggers ----------
export {
  setUpdatedAtLandlords,
  setUpdatedAtProperties,
  setUpdatedAtTenants,
  setUpdatedAtLeases,
  setUpdatedAtPayments,
  setUpdatedAtDocuments,
  setUpdatedAtInvestmentScenarios,
} from "./triggers/set_updated_at";
export {recomputeReceiptStale} from "./triggers/recompute_receipt_stale";

// ---------- Callables ----------
export {softDeleteEntity} from "./callable/soft_delete";
export {
  createLease,
  updateLease,
  createPayment,
  updatePayment,
} from "./callable/lease_payment";
export {
  generateReceipt,
  getReceiptPdfUrl,
  voidReceipt,
  markReceiptAsSent,
} from "./callable/receipts";
export {
  createDocument,
  getDocumentDownloadUrl,
} from "./callable/documents";
