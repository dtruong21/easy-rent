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
import {FieldValue} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {asBag, requireAuthUid} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";


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

/** Vue minimale d'un `UserRecord` — permet de tester sans firebase-admin. */
export interface AuthIdentity {
  email?: string | null;
  displayName?: string | null;
  providerData: ReadonlyArray<{
    email?: string | null;
    displayName?: string | null;
  }>;
}

const nonEmpty = (v: unknown): v is string =>
  typeof v === "string" && v.trim().length > 0;

/**
 * Résout `email` et `fullName` à persister lors de l'upgrade anonyme → compte.
 *
 * **Le bug que ça corrige.** Le doc anonyme est créé avec `email: null` et
 * `fullName: ''` — normal, un anonyme n'a ni l'un ni l'autre. Cette callable
 * basculait ensuite `isAnonymous`, le tier et le consentement, mais **laissait
 * ces deux champs intacts** : on obtenait un compte complet sans email ni nom.
 * Conséquences observées en recette : le dashboard affiche « Hello » sans nom,
 * et l'écran Informations personnelles échoue à charger, `LandlordProfile`
 * déclarant `required String email` alors que le doc contient `null`.
 * La règle Firestore impose bien `email is string` et `fullName.size() > 0`,
 * mais seulement à la CRÉATION — ce doc passe par une création anonyme puis un
 * update, il contournait donc l'invariant sans jamais le violer formellement.
 *
 * **Pourquoi `providerData` et pas seulement le niveau supérieur.** Sur un
 * `linkWithPopup` Google, `authUser.displayName` peut valoir `undefined` alors
 * que l'entrée du fournisseur porte le nom réel. Observé tel quel : un compte
 * Google fournissant « Thi Kim Chi Le » ressortait avec `fullName: ''`. Idem
 * pour l'email. On lit donc le niveau supérieur d'abord, puis les fournisseurs.
 *
 * **On ne réécrit jamais par-dessus une valeur déjà renseignée** : la fonction
 * ne renvoie que les champs manquants ou vides. Un upgrade rejoué ne peut donc
 * pas écraser un nom que l'utilisateur aurait corrigé entre-temps.
 *
 * Dernier repli du nom : l'email. C'est laid mais ça respecte l'invariant
 * « un compte complet a un nom non vide », et ça reste modifiable dans l'app —
 * mieux qu'un champ vide qui casse l'écran de profil.
 *
 * Pure (aucune dépendance Firebase) pour rester testable sans émulateur.
 */
export function resolveUpgradeIdentity(
  authUser: AuthIdentity,
  current: Record<string, unknown>,
): {email?: string; fullName?: string} {
  const fromProviders = <K extends "email" | "displayName">(key: K) =>
    authUser.providerData.find((p) => nonEmpty(p[key]))?.[key];

  const email = nonEmpty(authUser.email) ?
    authUser.email :
    fromProviders("email");
  const displayName = nonEmpty(authUser.displayName) ?
    authUser.displayName :
    fromProviders("displayName");

  const patch: {email?: string; fullName?: string} = {};
  if (!nonEmpty(current.email) && nonEmpty(email)) {
    patch.email = email.trim();
  }
  if (!nonEmpty(current.fullName)) {
    const name = nonEmpty(displayName) ? displayName : email;
    if (nonEmpty(name)) patch.fullName = name.trim();
  }
  return patch;
}

export const finalizeAnonymousUpgrade = onCall(
  {region: "europe-west1"},
  async (request) => {
    // OWASP-02 — EXEMPTÉE de `requireVerifiedUid` (volontairement) : le client
    // l'appelle juste après le link email/mot de passe et AVANT l'envoi de
    // l'email de vérification (`linkAnonymousWithEmailPassword`) — le compte
    // est donc non vérifié par construction à cet instant. Elle ne donne
    // aucun accès métier : elle bascule seulement le tier anonyme → free ;
    // c'est la vérification de l'email qui débloque ensuite le compte complet.
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

    const db = await dbForRequest(request);
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

      const now = FieldValue.serverTimestamp();
      // `email` / `fullName` viennent d'Auth (niveau supérieur puis
      // `providerData`) — le doc anonyme les portait vides par construction, et
      // ne pas les renseigner ici produisait un compte complet sans identité.
      // Ne réécrit jamais par-dessus une valeur déjà présente.
      const identity = resolveUpgradeIdentity(authUser, current);
      tx.update(ref, {
        ...identity,
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
