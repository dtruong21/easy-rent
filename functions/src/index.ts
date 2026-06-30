/**
 * EasyRent — Cloud Functions entry point.
 *
 * Region par défaut : europe-west1 (configurée dans firebase.json).
 * Chaque trigger est défini dans son propre module sous `src/<domain>/`
 * et ré-exporté ici pour que `firebase deploy --only functions` les voie.
 *
 * FEAT-019 — Phase 0 : skeleton uniquement. Les triggers concrets
 * (handleNewUser, onLeaseWrite, schedulers de rappels, etc.) sont
 * implémentés à partir de la Phase 1.
 */

import {setGlobalOptions} from "firebase-functions/v2";

// Garde-fou coût : Phase 0 — pas plus de 10 conteneurs concurrents.
// À ajuster par fonction une fois les workloads connus (Phase 3+).
setGlobalOptions({
  region: "europe-west1",
  maxInstances: 10,
});

export {handleNewUser} from "./auth/handle_new_user";

// Placeholder — à remplir en Phase 1 :
// export {onPaymentWrite} from "./payments/on_payment_write";
// export {sendRentReminders} from "./schedulers/send_rent_reminders";
