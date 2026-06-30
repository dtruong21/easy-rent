/**
 * Helpers de formatage FR pour les quittances PDF.
 *
 * Port verbatim de `supabase/functions/_shared/money_format.ts` (Deno).
 * Aucune dépendance, fonctions pures — testable unitairement.
 */

/**
 * Formate un montant entier en centimes vers le format monétaire fr-FR.
 * Exemple : 123456 → "1 234,56 €"
 * Espace insécable (U+00A0) en séparateur des milliers, virgule en décimal.
 */
export function formatEurosFromCents(cents: number): string {
  const euros = cents / 100;
  const [intPart, decPart] = euros.toFixed(2).split(".");
  const safeInt = intPart ?? "0";
  const safeDec = decPart ?? "00";
  const formattedInt = safeInt.replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return `${formattedInt},${safeDec} €`;
}

/** Formate une Date (ou ISO string) en DD/MM/YYYY (UTC). */
export function formatDateFr(date: Date | string): string {
  const d = typeof date === "string" ? new Date(date) : date;
  const day = String(d.getUTCDate()).padStart(2, "0");
  const month = String(d.getUTCMonth() + 1).padStart(2, "0");
  const year = d.getUTCFullYear();
  return `${day}/${month}/${year}`;
}

const MONTHS_FR = [
  "janvier",
  "fevrier",
  "mars",
  "avril",
  "mai",
  "juin",
  "juillet",
  "aout",
  "septembre",
  "octobre",
  "novembre",
  "decembre",
];

/**
 * Renvoie le nom du mois + année en français pour une ISO date string.
 * Exemple : "2026-05-01" → "mai 2026"
 * Noms ASCII (sans accents) — compat WinAnsi pdf-lib StandardFonts.
 */
export function formatMonthYearFr(isoDate: string): string {
  const d = new Date(isoDate);
  return `${MONTHS_FR[d.getUTCMonth()] ?? ""} ${d.getUTCFullYear()}`;
}
