/**
 * Formats an integer amount in cents to the French locale currency format.
 * Example: 123456 -> "1 234,56 €"
 * Uses non-breaking space (U+00A0) as thousands separator per fr-FR convention.
 */
export function formatEurosFromCents(cents: number): string {
  const euros = cents / 100;
  // Manually format to guarantee fr-FR style (space as thousands sep, comma as decimal)
  const [intPart, decPart] = euros.toFixed(2).split(".");
  const formattedInt = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return `${formattedInt},${decPart} €`;
}

/**
 * Formats a Date (or ISO string) to DD/MM/YYYY.
 */
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
 * Returns the French month name + year for a given ISO date string.
 * Example: "2026-05-01" -> "mai 2026"
 * Note: uses ASCII-safe month names to avoid pdf-lib WinAnsi encoding issues.
 */
export function formatMonthYearFr(isoDate: string): string {
  const d = new Date(isoDate);
  return `${MONTHS_FR[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}
