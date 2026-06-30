/**
 * handleNewUser — beforeUserCreated blocking trigger.
 *
 * Réplique du trigger Postgres `handle_new_user()` qui insérait une ligne
 * dans `public.landlords` à chaque INSERT dans `auth.users`. Ici on écrit
 * `landlords/{uid}` dans Firestore avant que la création du compte Firebase
 * Auth soit confirmée — si l'écriture échoue, la création est annulée
 * (atomicité signup + landlord_insert + consentement RGPD).
 *
 * Garanties :
 *   - `rgpdConsentAt` = serverTimestamp() (accountability RGPD art. 7.1)
 *   - `rgpdConsentVersion` = version courante du texte de PdC ("v1-2026-06")
 *     correspondant à ce qui a été accepté côté client au signup
 *   - Idempotent (`set({merge:true})`) au cas où le trigger refire
 */

import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";
import {HttpsError} from "firebase-functions/v2/https";
import {beforeUserCreated} from "firebase-functions/v2/identity";
import type {AuthBlockingEvent} from "firebase-functions/v2/identity";

/**
 * Version courante du texte de consentement RGPD.
 *
 * À incrémenter à chaque mise à jour du texte de politique de confidentialité
 * ou des finalités de traitement (synchroniser avec
 * `lib/features/auth/data/auth_repository.dart::_rgpdConsentVersion`).
 */
const CURRENT_RGPD_VERSION = "v1-2026-06";

const EMAIL_REGEX = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export const handleNewUser = beforeUserCreated(
  async (event: AuthBlockingEvent) => {
    const user = event.data;
    if (!user) {
      throw new HttpsError("invalid-argument", "missing user data");
    }

    const uid = user.uid;
    const email = user.email ?? null;
    if (!email || !EMAIL_REGEX.test(email)) {
      throw new HttpsError("invalid-argument", "invalid email");
    }

    const db = admin.firestore();
    const now = admin.firestore.FieldValue.serverTimestamp();

    try {
      await db.doc(`landlords/${uid}`).set(
        {
          id: uid,
          email,
          fullName: user.displayName ?? "",
          phone: null,
          address: null,
          rgpdConsentAt: now,
          rgpdConsentVersion: CURRENT_RGPD_VERSION,
          createdAt: now,
          updatedAt: now,
          deletedAt: null,
        },
        {merge: true},
      );

      logger.info("landlord provisioned", {
        uid,
        rgpdVersion: CURRENT_RGPD_VERSION,
      });
    } catch (err) {
      logger.error("handleNewUser failed to provision landlord", {uid, err});
      throw new HttpsError(
        "internal",
        "could not provision landlord profile",
      );
    }

    // Retourner sans rien = autoriser la création du compte Firebase Auth.
    return;
  },
);
