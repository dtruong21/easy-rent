/**
 * handleNewUser — beforeUserCreated blocking trigger.
 *
 * Réplique du trigger Postgres `handle_new_user()` qui insérait une ligne
 * dans `public.landlords` à chaque INSERT dans `auth.users`. Ici on écrit
 * `landlords/{uid}` dans Firestore avant que la création du compte Firebase
 * Auth soit confirmée — si l'écriture échoue, la création est annulée
 * (atomicité signup + landlord_insert + consentement RGPD).
 *
 * BAILLAN-M1 — branche anonyme vs non-anonyme :
 *   - Compte NON-anonyme (email/password, Google, Apple) : comportement
 *     inchangé — `rgpdConsentAt`/`rgpdConsentVersion` stampés (l'utilisateur
 *     a explicitement consenti côté UI avant l'appel signup).
 *   - Compte anonyme (Firebase Anonymous Auth, aucun provider ni email) :
 *     **aucun consentement RGPD n'est stampé** (l'anonyme n'a rien signé).
 *     Le doc est créé avec `isAnonymous: true`, `subscriptionTier:
 *     'anonymous'` et `anonExpiresAt: now + 14 jours` (expiration glissante,
 *     renouvelée côté client à chaque activité — voir
 *     `anon_expiry_renewer.dart`).
 *
 * Garanties (compte non-anonyme) :
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

const ANON_EXPIRY_DAYS = 14;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Détecte si un utilisateur Firebase Auth nouvellement créé est anonyme.
 *
 * Heuristique : un anonyme n'a ni email ni provider externe (Google/Apple)
 * attaché — `providerData` est vide (Firebase Anonymous Auth n'a pas de
 * provider dédié dans `providerData`, contrairement à `password`/`google.com`
 * /`apple.com`). Extrait en fonction pure pour rester testable sans
 * émulateur Firebase.
 */
export function isAnonymousUser(user: {
  email?: string | null;
  providerData?: readonly unknown[] | null;
}): boolean {
  return !user.email && (user.providerData ?? []).length === 0;
}

export const handleNewUser = beforeUserCreated(
  async (event: AuthBlockingEvent) => {
    const user = event.data;
    if (!user) {
      throw new HttpsError("invalid-argument", "missing user data");
    }

    const uid = user.uid;
    const isAnonymous = isAnonymousUser(user);

    const db = admin.firestore();
    const now = admin.firestore.FieldValue.serverTimestamp();

    try {
      if (isAnonymous) {
        const anonExpiresAt = admin.firestore.Timestamp.fromMillis(
          Date.now() + ANON_EXPIRY_DAYS * MS_PER_DAY,
        );
        await db.doc(`landlords/${uid}`).set(
          {
            id: uid,
            email: null,
            fullName: "",
            phone: null,
            address: null,
            isAnonymous: true,
            subscriptionTier: "anonymous",
            anonExpiresAt,
            rgpdConsentAt: null,
            rgpdConsentVersion: null,
            createdAt: now,
            updatedAt: now,
            deletedAt: null,
          },
          {merge: true},
        );
        logger.info("anonymous landlord provisioned", {uid});
        return;
      }

      const email = user.email ?? null;
      if (!email || !EMAIL_REGEX.test(email)) {
        throw new HttpsError("invalid-argument", "invalid email");
      }

      await db.doc(`landlords/${uid}`).set(
        {
          id: uid,
          email,
          fullName: user.displayName ?? "",
          phone: null,
          address: null,
          isAnonymous: false,
          subscriptionTier: "free",
          anonExpiresAt: null,
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
      if (err instanceof HttpsError) throw err;
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
