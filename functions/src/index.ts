/**
 * EasyRent — Cloud Functions entry point.
 *
 * Region par défaut : europe-west1 (configurée dans firebase.json).
 * Chaque trigger / callable est défini dans son propre module sous
 * `src/<domain>/` et ré-exporté ici pour que `firebase deploy --only functions`
 * les voie.
 *
 * FEAT-019 — Phase 1 backend foundations (setUpdatedAt + softDelete +
 * lease/payment cross-entity callables + recompute stale).
 * Phase 2 ajoutera generate/void/markSent receipts + create document.
 *
 * NB — le trigger bloquant `handleNewUser` (beforeUserCreated) a été retiré
 * (ADR 0001) : il exigeait Identity Platform (GCIP) non activé sur le projet,
 * ce qui faisait échouer `firebase deploy --only functions` (exit 2). Le
 * provisioning du doc landlord est 100 % côté client (auth_repository.dart),
 * gardé par les Firestore rules. NE PAS réintroduire de blocking function
 * sans réactiver GCIP au préalable.
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
export {createProperty, createTenant} from "./callable/property_tenant";
export {
  createLease,
  updateLease,
  createPayment,
  updatePayment,
} from "./callable/lease_payment";
export {
  generateReceipt,
  voidReceipt,
  markReceiptAsSent,
} from "./callable/receipts";
export {
  createDocument,
  getDocumentDownloadUrl,
} from "./callable/documents";
export {
  createExpense,
  updateExpense,
  setUpdatedAtExpenses,
} from "./callable/expenses";
export {finalizeAnonymousUpgrade} from "./callable/finalize_anonymous_upgrade";
export {deleteAccount} from "./callable/delete_account";

// ---------- HTTP (webhooks) ----------
export {revenueCatWebhook} from "./http/revenuecat_webhook";

// ---------- Scheduled ----------
export {cleanupExpiredAnon} from "./scheduled/cleanup_expired_anon";
export {reconcileEntitlements} from "./scheduled/reconcile_entitlements";
