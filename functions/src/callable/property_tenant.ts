/**
 * createProperty — callable de création d'un bien, avec gating free-tier
 * (FEAT-044, Phase A).
 *
 * Pourquoi côté serveur : la création de `properties` était un write client
 * direct (`docRef.set`) gardé par les seules Firestore rules. Un plafond de
 * plan (freemium) NE PEUT PAS être imposé par les rules (pas d'agrégation, pas
 * de réservation atomique) ni par un trigger asynchrone (course à la borne).
 * On déplace donc la création dans cette callable : elle lit le tier + le
 * compteur dénormalisé `landlords/{uid}.activePropertiesCount` et réserve le
 * slot DANS LA MÊME TRANSACTION que l'incrément — Firestore rejoue la
 * transaction en cas de conflit, donc deux créations concurrentes à la borne
 * ne peuvent pas dépasser le plafond.
 *
 * La rule `properties/create` passe à `if false` (CF-exclusif). Le compteur
 * `activePropertiesCount` est maintenu uniquement par les callables Admin SDK
 * (création ici, décrément dans `softDeleteEntity`) — les rules interdisent au
 * client de le muter.
 *
 * ⚠️ Migration : le compteur doit être backfillé sur les comptes EXISTANTS
 * avant que le gate soit fiable (les nouveaux comptes l'initialisent à 0 au
 * provisioning). Voir `functions/scripts/backfill_active_properties_count.ts`.
 */

import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  asBag,
  dataOrFail,
  optionalInt,
  optionalNumber,
  optionalString,
  optionalTimestamp,
  requireAuthUid,
  requireBool,
  requireString,
} from "../utils/callable_helpers";
import {dbForRequest} from "../utils/db_router";


// Miroir de `PropertyType.sqlValue` (Dart) + de la rule `properties/create`.
const PROPERTY_TYPES = new Set(["appartement", "maison", "studio", "autre"]);

// Plafonds par tier — miroir de `SubscriptionTier.{propertyLimit,activeTenantLimit}`
// (lib/features/auth/domain/subscription_tier.dart). `null` = illimité.
const FREE_PROPERTY_LIMIT = 2;
const FREE_TENANT_LIMIT = 3;

// Miroir de la validation email de la rule `tenants/create`.
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/**
 * Plafond du tier pour un compteur donné. `null` = illimité (paid). Tout tier
 * inconnu ou anonyme → 0 (le registre est réservé aux comptes complets ;
 * defense-in-depth avec la rule qui exigeait déjà `isFullyAuthed`).
 */
function limitForTier(tier: string, freeLimit: number): number | null {
  switch (tier) {
    case "paid":
      return null;
    case "free":
      return freeLimit;
    default:
      return 0;
  }
}

/** Trim + chaîne vide → null (miroir du `_orNull` client). */
function emptyToNull(s: string | null): string | null {
  if (s === null) return null;
  const t = s.trim();
  return t.length === 0 ? null : t;
}

/**
 * Pré-calcul fail-closed du compteur de plan (HORS transaction : count() n'y
 * est pas disponible). Si le champ `counterField` du doc landlord est ABSENT
 * (compte legacy pré-backfill), recompte les entités actives de
 * `countCollection` en direct → on ferme le gate au lieu de repartir de 0.
 * Retourne `null` si le compteur existe déjà (l'appelant incrémente) ou si le
 * landlord n'existe pas (la transaction lèvera `not-found`).
 */
async function precomputeSeedCount(
  db: admin.firestore.Firestore,
  uid: string,
  counterField: string,
  countCollection: string,
): Promise<number | null> {
  const preSnap = await db.doc(`landlords/${uid}`).get();
  if (!preSnap.exists) return null;
  const preData = (preSnap.data() ?? {}) as Record<string, unknown>;
  if (typeof preData[counterField] === "number") return null;
  const agg = await db
    .collection(countCollection)
    .where("landlordId", "==", uid)
    .where("deletedAt", "==", null)
    .count()
    .get();
  return agg.data().count;
}

export const createProperty = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    // --- Validation (miroir de la rule `properties/create` + du payload
    // client `property_repository.dart`). La CF est désormais la seule
    // gardienne de la forme : elle remplace la validation que faisaient les
    // rules avant de passer `create` à `if false`. ---
    const name = requireString(data.name, "name");
    const address = requireString(data.address, "address");
    const type = requireString(data.type, "type");
    if (!PROPERTY_TYPES.has(type)) {
      throw new HttpsError("invalid-argument", `invalid property type: ${type}`);
    }
    const surfaceM2 = optionalNumber(data.surfaceM2, "surfaceM2");
    const postalCode = optionalString(data.postalCode, "postalCode");
    const city = optionalString(data.city, "city");
    const rooms = optionalInt(data.rooms, "rooms", {min: 0});
    const bedrooms = optionalInt(data.bedrooms, "bedrooms", {min: 0});
    const floor = optionalInt(data.floor, "floor");
    const hasElevator = requireBool(data.hasElevator, "hasElevator");
    const furnished = requireBool(data.furnished, "furnished");
    const heatingType = optionalString(data.heatingType, "heatingType");
    const dpeLetter = optionalString(data.dpeLetter, "dpeLetter");
    const dpeValueKwhM2Year = optionalInt(
      data.dpeValueKwhM2Year,
      "dpeValueKwhM2Year",
      {min: 0},
    );
    const gesLetter = optionalString(data.gesLetter, "gesLetter");
    const constructionYear = optionalInt(
      data.constructionYear,
      "constructionYear",
    );
    const purchasePriceCents = optionalInt(
      data.purchasePriceCents,
      "purchasePriceCents",
      {min: 0},
    );
    const purchaseDate = optionalTimestamp(data.purchaseDate, "purchaseDate");
    const notaryFeesCents = optionalInt(
      data.notaryFeesCents,
      "notaryFeesCents",
      {min: 0},
    );
    const isNewProperty = requireBool(data.isNewProperty, "isNewProperty");
    const propertyTaxAnnualCents = optionalInt(
      data.propertyTaxAnnualCents,
      "propertyTaxAnnualCents",
      {min: 0},
    );
    const insurancePnoAnnualCents = optionalInt(
      data.insurancePnoAnnualCents,
      "insurancePnoAnnualCents",
      {min: 0},
    );
    const condoFeesNonRecoverableCents = optionalInt(
      data.condoFeesNonRecoverableCents,
      "condoFeesNonRecoverableCents",
      {min: 0},
    );
    const loanPrincipalCents = optionalInt(
      data.loanPrincipalCents,
      "loanPrincipalCents",
      {min: 0},
    );
    const loanRateBps = optionalInt(data.loanRateBps, "loanRateBps", {min: 0});
    const loanInsuranceBps = optionalInt(
      data.loanInsuranceBps,
      "loanInsuranceBps",
      {min: 0},
    );
    const loanDurationMonths = optionalInt(
      data.loanDurationMonths,
      "loanDurationMonths",
      {min: 0},
    );
    const loanStartDate = optionalTimestamp(data.loanStartDate, "loanStartDate");
    const loanMonthlyPaymentOverrideCents = optionalInt(
      data.loanMonthlyPaymentOverrideCents,
      "loanMonthlyPaymentOverrideCents",
      {min: 0},
    );

    const db = dbForRequest(request);
    const landlordRef = db.doc(`landlords/${uid}`);
    const propertyRef = db.collection("properties").doc();

    // Fail-closed sur compteur absent (compte legacy pré-backfill) — recompte
    // les biens actifs pour fermer le gate au lieu de repartir de 0.
    // Détail : cf. en-tête de precomputeSeedCount. La course éventuelle
    // (create/soft-delete concurrent pendant le seed initial) est bénigne et se
    // corrige d'elle-même ; l'atomicité stricte à la borne vaut une fois le
    // compteur présent (chemin increment ci-dessous).
    const seededCount = await precomputeSeedCount(
      db,
      uid,
      "activePropertiesCount",
      "properties",
    );

    return await db.runTransaction(async (tx) => {
      const landlordSnap = await tx.get(landlordRef);
      const landlord = dataOrFail(landlordSnap, "landlord not found");

      const tier =
        typeof landlord.subscriptionTier === "string" ?
          landlord.subscriptionTier :
          "anonymous";
      const limit = limitForTier(tier, FREE_PROPERTY_LIMIT);
      const rawCount = landlord.activePropertiesCount;
      const hasCounter = typeof rawCount === "number";
      const count = hasCounter ? rawCount : (seededCount ?? 0);

      if (limit !== null && count >= limit) {
        throw new HttpsError(
          "resource-exhausted",
          "property_limit_reached",
        );
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      tx.set(propertyRef, {
        id: propertyRef.id,
        landlordId: uid,
        name: name.trim(),
        address: address.trim(),
        type,
        surfaceM2,
        postalCode: postalCode === null ? null : postalCode.trim(),
        city: city === null ? null : city.trim(),
        rooms,
        bedrooms,
        floor,
        hasElevator,
        furnished,
        heatingType,
        dpeLetter,
        dpeValueKwhM2Year,
        gesLetter,
        constructionYear,
        purchasePriceCents,
        purchaseDate,
        notaryFeesCents,
        isNewProperty,
        propertyTaxAnnualCents,
        insurancePnoAnnualCents,
        condoFeesNonRecoverableCents,
        loanPrincipalCents,
        loanRateBps,
        loanInsuranceBps,
        loanDurationMonths,
        loanStartDate,
        loanMonthlyPaymentOverrideCents,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        // Maintenu par createLease / updateLease / softDeleteEntity.
        activeLeaseCount: 0,
      });
      // Réservation atomique du slot : incrément dans la même transaction que
      // le gate ci-dessus → une création concurrente à la borne fait rejouer
      // la transaction et re-vérifie le plafond. Sur un compte legacy sans
      // compteur, on SÈME la vraie valeur (recomptée ci-dessus) + 1 plutôt
      // qu'un increment (qui partirait de 0 et sous-compterait).
      if (hasCounter) {
        tx.update(landlordRef, {
          activePropertiesCount: admin.firestore.FieldValue.increment(1),
          updatedAt: now,
        });
      } else {
        tx.update(landlordRef, {
          activePropertiesCount: (seededCount ?? 0) + 1,
          updatedAt: now,
        });
      }

      return {propertyId: propertyRef.id};
    });
  },
);

// ============================================================================
// createTenant — même patron de gating que createProperty (FEAT-044).
// ============================================================================
export const createTenant = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = requireAuthUid(request);
    const data = asBag(request.data);

    // Validation (miroir de la rule `tenants/create` + du payload client
    // tenant_repository.dart) — la CF est désormais la seule gardienne de la
    // forme (la rule create passe à `if false`).
    const firstName = requireString(data.firstName, "firstName");
    const lastName = requireString(data.lastName, "lastName");
    const email = requireString(data.email, "email");
    if (!EMAIL_RE.test(email)) {
      throw new HttpsError("invalid-argument", "invalid email");
    }
    const phone = optionalString(data.phone, "phone");
    const birthDate = optionalTimestamp(data.birthDate, "birthDate");
    const birthPlace = optionalString(data.birthPlace, "birthPlace");
    const nationality = optionalString(data.nationality, "nationality");
    const profession = optionalString(data.profession, "profession");
    const employer = optionalString(data.employer, "employer");
    const monthlyIncomeCents = optionalInt(
      data.monthlyIncomeCents,
      "monthlyIncomeCents",
      {min: 0},
    );
    const previousAddress = optionalString(
      data.previousAddress,
      "previousAddress",
    );
    const guarantorName = optionalString(data.guarantorName, "guarantorName");
    const guarantorEmail = optionalString(data.guarantorEmail, "guarantorEmail");
    const guarantorPhone = optionalString(data.guarantorPhone, "guarantorPhone");

    const db = dbForRequest(request);
    const landlordRef = db.doc(`landlords/${uid}`);
    const tenantRef = db.collection("tenants").doc();

    // Fail-closed sur compteur absent (cf. createProperty / precomputeSeedCount).
    const seededCount = await precomputeSeedCount(
      db,
      uid,
      "activeTenantsCount",
      "tenants",
    );

    return await db.runTransaction(async (tx) => {
      const landlordSnap = await tx.get(landlordRef);
      const landlord = dataOrFail(landlordSnap, "landlord not found");

      const tier =
        typeof landlord.subscriptionTier === "string" ?
          landlord.subscriptionTier :
          "anonymous";
      const limit = limitForTier(tier, FREE_TENANT_LIMIT);
      const rawCount = landlord.activeTenantsCount;
      const hasCounter = typeof rawCount === "number";
      const count = hasCounter ? rawCount : (seededCount ?? 0);

      if (limit !== null && count >= limit) {
        throw new HttpsError("resource-exhausted", "tenant_limit_reached");
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      tx.set(tenantRef, {
        id: tenantRef.id,
        landlordId: uid,
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        email: email.trim(),
        phone: emptyToNull(phone),
        birthDate,
        birthPlace: emptyToNull(birthPlace),
        nationality: emptyToNull(nationality),
        profession: emptyToNull(profession),
        employer: emptyToNull(employer),
        monthlyIncomeCents,
        previousAddress: emptyToNull(previousAddress),
        guarantorName: emptyToNull(guarantorName),
        guarantorEmail: emptyToNull(guarantorEmail),
        guarantorPhone: emptyToNull(guarantorPhone),
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        // Maintenu par createLease / updateLease / softDeleteEntity.
        activeLeaseCount: 0,
      });
      if (hasCounter) {
        tx.update(landlordRef, {
          activeTenantsCount: admin.firestore.FieldValue.increment(1),
          updatedAt: now,
        });
      } else {
        tx.update(landlordRef, {
          activeTenantsCount: (seededCount ?? 0) + 1,
          updatedAt: now,
        });
      }

      return {tenantId: tenantRef.id};
    });
  },
);
