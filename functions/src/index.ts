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

// Garde-fou coût : pas plus de 2 conteneurs concurrents par défaut (baissé de
// 10 → 2 le 2026-07-25 pour rester sous le quota « Total CPU allocation » de
// Cloud Run sur europe-west1 ; 2 × ~80 req/conteneur reste très au-dessus du
// volume actuel). Sur-ajuster par fonction si workload nécessite (en runWith).
//
// `cpu: "gcf_gen1"` (2026-08-03, FEAT-056) : l'allocation CPU par instance
// repasse au ratio des fonctions 1re génération (~0,167 vCPU pour 256 Mio) au
// lieu du défaut gen2 de 1 vCPU entier. C'est le quota « Total CPU allocation »
// qui l'impose : il compte `nb_fonctions × maxInstances × cpu`, soit 16 × 2 × 1
// = 32 vCPU réservés avant ce changement — au-dessus du plafond régional. Le
// déploiement échouait alors sur un healthcheck Cloud Run (« Quota exceeded for
// total allowable CPU per project per region »), message qui ne dit PAS que le
// code est en cause : il l'est d'autant moins que seule la fonction ajoutée
// faisait déborder un projet déjà à la limite.
//
// Baisser `maxInstances` était l'autre levier, mais il est déjà à 2 — descendre
// à 1 supprimerait toute concurrence. Le CPU par instance est donc le seul
// réglage qui restait, et c'est celui qui coûte le moins : ces callables ne font
// que des lectures/écritures Firestore, elles sont bornées par l'E/S réseau, pas
// par le calcul. C'est exactement le régime des fonctions gen1 d'origine.
setGlobalOptions({
  region: "europe-west1",
  maxInstances: 2,
  cpu: "gcf_gen1",
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
  finalizeChargeRegularization,
  voidChargeStatement,
  markChargeStatementAsSent,
} from "./callable/charge_statements";
export {
  createDocument,
  getDocumentDownloadUrl,
} from "./callable/documents";
export {
  createExpense,
  updateExpense,
  setUpdatedAtExpenses,
} from "./callable/expenses";
export {createScenario} from "./callable/scenarios";
export {finalizeAnonymousUpgrade} from "./callable/finalize_anonymous_upgrade";
export {deleteAccount} from "./callable/delete_account";
export {exportAccountData} from "./callable/export_account_data";
export {createCheckoutSession} from "./callable/create_checkout_session";
export {manageSubscription} from "./callable/manage_subscription";

// ---------- HTTP (webhooks) ----------
export {revenueCatWebhook} from "./http/revenuecat_webhook";

// ---------- Scheduled ----------
export {cleanupExpiredAnon} from "./scheduled/cleanup_expired_anon";
export {reconcileEntitlements} from "./scheduled/reconcile_entitlements";
