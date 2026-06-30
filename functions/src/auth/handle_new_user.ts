/**
 * handleNewUser — beforeUserCreated blocking trigger.
 *
 * FEAT-019 Phase 1 : à l'inscription d'un nouvel utilisateur Firebase Auth,
 * provisionne le document `landlords/{uid}` dans Firestore avec les valeurs
 * par défaut (consent RGPD vide, plan free, created_at = now).
 *
 * Référence schéma : docs/state/SCHEMA.md (section Firestore — collection
 * `landlords`).
 *
 * Trigger blocking → si on throw une HttpsError, l'inscription est annulée
 * côté client. À utiliser pour rejeter les emails sur blocklist (spam,
 * comptes déjà supprimés non-réutilisables) en Phase 2.
 */

import {beforeUserCreated} from "firebase-functions/v2/identity";
import type {AuthBlockingEvent} from "firebase-functions/v2/identity";

export const handleNewUser = beforeUserCreated(
  async (event: AuthBlockingEvent) => {
    // TODO(FEAT-019 Phase 1) :
    //   1. Valider event.data.email (format, blocklist).
    //   2. Créer le doc landlords/{event.data.uid} via admin SDK :
    //        - email, displayName
    //        - plan: "free"
    //        - createdAt: FieldValue.serverTimestamp()
    //        - rgpdConsent: { version: null, acceptedAt: null }
    //   3. Logger via firebase-functions/logger pour audit RGPD.
    //
    // Retourner {} (ou rien) = autoriser la création.
    // Throw HttpsError("permission-denied", ...) = bloquer.
    return;
  },
);
