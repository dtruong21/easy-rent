/**
 * finalizeAnonymousUpgrade — callable appelée par le client juste après un
 * `linkWithCredential` / `linkWithPopup` réussi sur un compte anonyme.
 *
 * Le provisioning initial du doc `landlords/{uid}` est 100 % côté client
 * (auth_repository.dart ; le blocking trigger handleNewUser a été retiré —
 * ADR 0001). Un `link` anonyme→compte est un update Auth (pas un create), donc
 * rien ne repromeut le doc automatiquement : il reste à l'état anonyme
 * (`subscriptionTier: 'anonymous'`, `rgpdConsentAt: null`) tant que cette
 * callable n'a pas tourné.
 *
 * Choix architecture (préférence produit BAILLAN-M1) : callable client-driven
 * plutôt qu'un trigger `onIdTokenChanged` — plus prévisible, retry-friendly,
 * moins de "magie" serveur asynchrone.
 *
 * Garanties :
 *   - Stampe `rgpdConsentAt`/`rgpdConsentVersion` UNIQUEMENT si `rgpdConsent`
 *     est explicitement `true` dans le payload (defense in depth : la UI
 *     Flutter refuse déjà d'appeler `linkAnonymousWith*` sans consentement,
 *     mais on ne fait jamais confiance au seul client pour du RGPD).
 *   - Idempotente : si le doc est déjà `subscriptionTier: 'free'` (ou
 *     'paid'), retourne `{ok: true, tier}` sans réécrire (évite d'écraser un
 *     upgrade ultérieur ou de re-stamper une date de consentement).
 *   - `anonExpiresAt` et `isAnonymous` sont remis à `null`/`false` — la
 *     session n'expire plus, ce n'est plus un compte anonyme.
 */

import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {asBag, requireAuthUid} from "../utils/callable_helpers";

/** Doit rester synchronisé avec `lib/features/auth/data/auth_repository.dart`
 * (`rgpdConsentVersion`) et le test `test/unit/rgpd_consent_test.dart`.
 * Historique : v1-2026-06 = PdC seule ; v2-2026-07 = CGU 1.0 + PdC 1.0 ;
 * v3-2026-07 = PdC 1.3 (rapport d'incident Crashlytics mobile, opt-in). */
export const CURRENT_RGPD_VERSION = "v3-2026-07";

/**
 * Résout la version de consentement RGPD à persister.
 *
 * rgpdConsentVersion est accepté depuis le client pour traçabilité mais
 * n'est jamais fait confiance seul : on retombe sur la constante serveur si
 * absente/invalide, et on ignore la valeur cliente si elle diffère de la
 * version courante (empêche un client obsolète — cache navigateur, ancien
 * build PWA non rafraîchi — de stamper une version de texte qui n'est plus
 * celle réellement affichée à l'utilisateur).
 *
 * Extrait en fonction pure (aucune dépendance Firebase) pour rester
 * testable en unitaire sans émulateur.
 */
export function resolveRgpdConsentVersion(clientValue: unknown): string {
  const clientVersion = typeof clientValue === "string" ? clientValue : null;
  return clientVersion === CURRENT_RGPD_VERSION
    ? clientVersion
    : CURRENT_RGPD_VERSION;
}

export const finalizeAnonymousUpgrade = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    const rgpdConsent = data.rgpdConsent === true;
    const rgpdConsentVersion = resolveRgpdConsentVersion(
      data.rgpdConsentVersion,
    );

    if (!rgpdConsent) {
      throw new HttpsError(
        "failed-precondition",
        "rgpdConsent must be true to finalize an anonymous upgrade",
      );
    }

    // CRITICAL fix — vérifie que le caller a effectivement lié un provider
    // externe (email/password / Google / Apple) via linkWithCredential /
    // linkWithPopup. Sans cette garde, un utilisateur strictement anonyme
    // peut invoquer la callable avec `rgpdConsent: true` et faire flip son
    // tier vers 'free' + stamp rgpdConsentAt sans jamais avoir donné un
    // vrai consentement RGPD. La preuve du link vient de providerData :
    // vide = anonyme pur, non-vide = au moins un provider lié.
    const authUser = await admin.auth().getUser(uid);
    if (authUser.providerData.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "cannot finalize upgrade — no provider linked on this account",
      );
    }

    const db = admin.firestore();
    const ref = db.doc(`landlords/${uid}`);

    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        throw new HttpsError(
          "not-found",
          `landlords/${uid} not found — cannot finalize upgrade`,
        );
      }
      const current = snap.data() ?? {};
      const currentTier =
        typeof current.subscriptionTier === "string"
          ? current.subscriptionTier
          : "anonymous";

      // Idempotence : déjà upgradé (retry après succès, double-clic, etc.)
      if (currentTier !== "anonymous") {
        return {ok: true, tier: currentTier};
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      tx.update(ref, {
        isAnonymous: false,
        subscriptionTier: "free",
        anonExpiresAt: null,
        rgpdConsentAt: now,
        rgpdConsentVersion,
        // FEAT-044 : garantit des compteurs de plan à 0 sur le compte
        // fraîchement upgradé (un anon ne peut avoir créé ni bien ni locataire
        // ni bail) — couvre aussi les docs anon legacy sans ces champs.
        activePropertiesCount: 0,
        activeTenantsCount: 0,
        activeLeasesCount: 0,
        updatedAt: now,
      });

      return {ok: true, tier: "free"};
    });
  },
);
