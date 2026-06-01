/**
 * Email template for quittance de loyer (rent receipt).
 *
 * Legal requirement: loi du 6 juillet 1989, art. 21.
 * Language: French (vouvoiement by default).
 * Encoding: UTF-8 (é, è, ç, €, à, œ).
 */

// ---------------------------------------------------------------------------
// HTML escaping — prevents injection via user-controlled fields (SEC-1)
// ---------------------------------------------------------------------------

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// ---------------------------------------------------------------------------
// Month names with accented characters for the email subject
// ---------------------------------------------------------------------------

const MONTHS_FR_FULL = [
  "janvier",
  "février",
  "mars",
  "avril",
  "mai",
  "juin",
  "juillet",
  "août",
  "septembre",
  "octobre",
  "novembre",
  "décembre",
];

/**
 * Returns "mai 2026" from "2026-05-01".
 */
function formatMonthYearFr(isoDate: string): string {
  const d = new Date(isoDate);
  return `${MONTHS_FR_FULL[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

/**
 * Returns "01/05/2026" from "2026-05-01".
 */
function formatDateFr(isoDate: string): string {
  const d = new Date(isoDate);
  const day = String(d.getUTCDate()).padStart(2, "0");
  const month = String(d.getUTCMonth() + 1).padStart(2, "0");
  const year = d.getUTCFullYear();
  return `${day}/${month}/${year}`;
}

/**
 * Returns "1 234,56 €" from 123456 cents.
 * Uses non-breaking space (U+00A0) as thousands separator per fr-FR convention.
 */
function formatEurosFromCents(cents: number): string {
  const euros = cents / 100;
  const [intPart, decPart] = euros.toFixed(2).split(".");
  const formattedInt = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return `${formattedInt},${decPart} €`;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Builds the email subject line.
 * Example: "Votre quittance de loyer — mai 2026"
 */
export function subject(periodStart: string): string {
  return `Votre quittance de loyer — ${formatMonthYearFr(periodStart)}`;
}

export interface HtmlBodyParams {
  tenantFirstName: string;
  periodStart: string;   // "YYYY-MM-DD"
  periodEnd: string;     // "YYYY-MM-DD"
  totalCents: number;
  landlordFullName: string;
}

/**
 * Builds the HTML body of the email.
 *
 * Content requirements (LEGAL.md + plan §3.5 step 10):
 * - Salutation with tenant first name
 * - Period in DD/MM/YYYY format
 * - Amount formatted fr-FR (X,XX €)
 * - Landlord signature
 * - Legal mention: loi 6 juillet 1989, art. 21
 *
 * Design: minimal HTML, no external CSS, white background, UTF-8.
 */
export function htmlBody({
  tenantFirstName,
  periodStart,
  periodEnd,
  totalCents,
  landlordFullName,
}: HtmlBodyParams): string {
  const periodStartFr = formatDateFr(periodStart);
  const periodEndFr = formatDateFr(periodEnd);
  const montant = formatEurosFromCents(totalCents);
  const monthYear = formatMonthYearFr(periodStart);
  const safeTenantFirstName = escapeHtml(tenantFirstName);
  const safeLandlordFullName = escapeHtml(landlordFullName);

  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Quittance de loyer — ${monthYear}</title>
</head>
<body style="font-family: Arial, sans-serif; color: #222; background: #fff; max-width: 600px; margin: 0 auto; padding: 24px;">

  <p>Bonjour ${safeTenantFirstName},</p>

  <p>
    Veuillez trouver en pièce jointe votre quittance de loyer pour la période
    du ${periodStartFr} au ${periodEndFr}, pour un montant total de ${montant}.
  </p>

  <p>
    Nous vous confirmons avoir reçu ce règlement. Conservez ce document, il
    atteste du paiement de votre loyer pour la période concernée.
  </p>

  <p>Cordialement,</p>

  <p><strong>${safeLandlordFullName}</strong></p>

  <hr style="border: none; border-top: 1px solid #ddd; margin: 24px 0;" />

  <p style="font-size: 12px; color: #666;">
    Cette quittance vous libère du paiement pour la période concernée,
    conformément à la loi du 6 juillet 1989, art. 21.<br />
    Ce message est envoyé automatiquement via EasyRent. Merci de ne pas y répondre directement.
  </p>

</body>
</html>`;
}
