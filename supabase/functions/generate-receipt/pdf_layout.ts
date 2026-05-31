/**
 * PDF builder for rent receipts (quittances / recus).
 * Compliant with loi du 6 juillet 1989, art. 21.
 *
 * Generates an A4 portrait PDF using pdf-lib StandardFonts.
 * StandardFonts.Helvetica uses WinAnsiEncoding which covers Latin-1:
 *   e/e accent acute, e grave, a grave, c cedilla, euro sign — OK.
 * Characters outside Latin-1 (oe ligature, French guillemets) are replaced
 * with ASCII equivalents to avoid encoding errors.
 */
import { PDFDocument, StandardFonts, rgb } from "./deps.ts";
import type { PDFFont, PDFPage } from "./deps.ts";
import { formatEurosFromCents, formatDateFr, formatMonthYearFr } from "../_shared/money_format.ts";
import type { ReceiptData } from "./types.ts";

// A4 dimensions in PDF points (1 pt = 1/72 inch)
const PAGE_WIDTH = 595.28;
const PAGE_HEIGHT = 841.89;
const MARGIN = 50;
const CONTENT_WIDTH = PAGE_WIDTH - 2 * MARGIN;

// Colours
const BLACK = rgb(0, 0, 0);
const DARK_GRAY = rgb(0.3, 0.3, 0.3);
const LIGHT_GRAY = rgb(0.6, 0.6, 0.6);
const RED = rgb(0.8, 0.1, 0.1);

/**
 * Sanitizes a string to ensure it only contains WinAnsi-safe characters.
 * Replaces known problematic French characters with ASCII equivalents.
 */
function sanitize(text: string): string {
  return text
    .replace(/Œ/g, "OE") // Oe ligature (uppercase)
    .replace(/œ/g, "oe") // oe ligature (lowercase)
    .replace(/«/g, '"')  // guillemet gauche
    .replace(/»/g, '"')  // guillemet droit
    .replace(/’/g, "'")  // apostrophe typographique
    .replace(/–/g, "-")  // tiret demi-cadratin
    .replace(/—/g, "-")  // tiret cadratin
    .replace(/ /g, " ")  // espace insecable -> espace normal pour pdf-lib
    // Keep euro sign (U+20AC) — covered by WinAnsi via Helvetica
    ;
}

/**
 * Wraps text to fit within maxWidth points using the given font and size.
 * Returns an array of lines.
 */
function wrapText(
  text: string,
  font: PDFFont,
  size: number,
  maxWidth: number,
): string[] {
  const words = text.split(" ");
  const lines: string[] = [];
  let current = "";

  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    const w = font.widthOfTextAtSize(candidate, size);
    if (w > maxWidth && current) {
      lines.push(current);
      current = word;
    } else {
      current = candidate;
    }
  }
  if (current) lines.push(current);
  return lines;
}

/**
 * Draws a line of text and returns the new Y position (y decreases downward).
 */
function drawText(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  font: PDFFont,
  size: number,
  color = BLACK,
): number {
  page.drawText(sanitize(text), { x, y, size, font, color });
  return y - size * 1.4; // line height = 1.4x font size
}

/**
 * Draws a horizontal rule from MARGIN to PAGE_WIDTH - MARGIN.
 */
function drawRule(page: PDFPage, y: number, color = LIGHT_GRAY): void {
  page.drawLine({
    start: { x: MARGIN, y },
    end: { x: PAGE_WIDTH - MARGIN, y },
    thickness: 0.5,
    color,
  });
}

/**
 * Draws a label + value pair aligned left/right, returns new y.
 */
function drawLabelValue(
  page: PDFPage,
  label: string,
  value: string,
  y: number,
  labelFont: PDFFont,
  valueFont: PDFFont,
  size: number,
): number {
  page.drawText(sanitize(label), {
    x: MARGIN,
    y,
    size,
    font: labelFont,
    color: DARK_GRAY,
  });
  const valueWidth = valueFont.widthOfTextAtSize(sanitize(value), size);
  page.drawText(sanitize(value), {
    x: PAGE_WIDTH - MARGIN - valueWidth,
    y,
    size,
    font: valueFont,
    color: BLACK,
  });
  return y - size * 1.4;
}

// ---------------------------------------------------------------------------
// Main export
// ---------------------------------------------------------------------------

export async function generateReceiptPdf(
  data: ReceiptData,
): Promise<Uint8Array> {
  const pdfDoc = await PDFDocument.create();
  const page = pdfDoc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);

  // Embed fonts
  const regular = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const bold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

  let y = PAGE_HEIGHT - MARGIN;

  // -------------------------------------------------------------------------
  // 1. Header block: bailleur (top-left) + date generated (top-right)
  // -------------------------------------------------------------------------
  const smallSize = 9;
  const bodySize = 10;

  // Bailleur — top left
  y = drawText(page, data.landlord.full_name, MARGIN, y, bold, bodySize);

  // Wrap address lines
  const landlordAddressLines = wrapText(
    sanitize(data.landlord.address),
    regular,
    bodySize,
    CONTENT_WIDTH * 0.5,
  );
  for (const line of landlordAddressLines) {
    y = drawText(page, line, MARGIN, y, regular, bodySize, DARK_GRAY);
  }

  // Date generated — top right, aligned with landlord block top
  const dateLabel = `Fait le ${formatDateFr(data.generated_at)}`;
  const dateLabelWidth = regular.widthOfTextAtSize(dateLabel, smallSize);
  page.drawText(sanitize(dateLabel), {
    x: PAGE_WIDTH - MARGIN - dateLabelWidth,
    y: PAGE_HEIGHT - MARGIN,
    size: smallSize,
    font: regular,
    color: DARK_GRAY,
  });

  y -= 20; // extra spacing before title

  // -------------------------------------------------------------------------
  // 2. Title (centred, bold, 18pt)
  // -------------------------------------------------------------------------
  const title =
    data.document_type === "quittance"
      ? "QUITTANCE DE LOYER"
      : "RECU DE PAIEMENT";
  const titleSize = 18;
  const titleWidth = bold.widthOfTextAtSize(title, titleSize);
  const titleX = (PAGE_WIDTH - titleWidth) / 2;
  page.drawText(title, { x: titleX, y, size: titleSize, font: bold, color: BLACK });
  y -= titleSize * 1.6;

  // Subtitle: "Loyer de <mois> <annee>"
  const subtitle = `Loyer de ${formatMonthYearFr(data.period_start)}`;
  const subtitleSize = 12;
  const subtitleWidth = regular.widthOfTextAtSize(sanitize(subtitle), subtitleSize);
  page.drawText(sanitize(subtitle), {
    x: (PAGE_WIDTH - subtitleWidth) / 2,
    y,
    size: subtitleSize,
    font: regular,
    color: DARK_GRAY,
  });
  y -= subtitleSize * 2.5;

  drawRule(page, y + 4);
  y -= 16;

  // -------------------------------------------------------------------------
  // 3. Tenant block
  // -------------------------------------------------------------------------
  const sectionSize = 10;
  y = drawText(page, "Locataire :", MARGIN, y, bold, sectionSize);
  const tenantName = `${data.tenant.first_name} ${data.tenant.last_name}`;
  y = drawText(page, tenantName, MARGIN + 10, y, regular, sectionSize);
  y -= 12;

  // -------------------------------------------------------------------------
  // 4. Property address
  // -------------------------------------------------------------------------
  y = drawText(page, "Logement :", MARGIN, y, bold, sectionSize);
  const propertyLines = wrapText(
    sanitize(data.property.address),
    regular,
    sectionSize,
    CONTENT_WIDTH - 10,
  );
  for (const line of propertyLines) {
    y = drawText(page, line, MARGIN + 10, y, regular, sectionSize, DARK_GRAY);
  }
  y -= 12;

  // -------------------------------------------------------------------------
  // 5. Period
  // -------------------------------------------------------------------------
  y = drawText(page, "Periode concernee :", MARGIN, y, bold, sectionSize);
  const periodText = `du ${formatDateFr(data.period_start)} au ${formatDateFr(data.period_end)}`;
  y = drawText(page, periodText, MARGIN + 10, y, regular, sectionSize);
  y -= 16;

  drawRule(page, y + 4);
  y -= 16;

  // -------------------------------------------------------------------------
  // 6. Financial summary
  // -------------------------------------------------------------------------
  y = drawText(page, "Detail du paiement :", MARGIN, y, bold, sectionSize);
  y -= 4;

  // Row: Loyer hors charges
  y = drawLabelValue(
    page,
    "Loyer hors charges",
    formatEurosFromCents(data.rent_cents),
    y,
    regular,
    regular,
    sectionSize,
  );

  // Row: Charges
  y = drawLabelValue(
    page,
    "Charges",
    formatEurosFromCents(data.charges_cents),
    y,
    regular,
    regular,
    sectionSize,
  );

  // Separator line before total
  y -= 4;
  drawRule(page, y + 4, DARK_GRAY);
  y -= 8;

  // Row: Total (bold)
  y = drawLabelValue(
    page,
    "Total recu",
    formatEurosFromCents(data.total_cents),
    y,
    bold,
    bold,
    sectionSize + 1,
  );

  // Payment date
  const paymentDateLabel = `Date du paiement : ${formatDateFr(data.last_paid_at)}`;
  y = drawText(page, paymentDateLabel, MARGIN, y - 4, regular, smallSize, DARK_GRAY);
  y -= 20;

  drawRule(page, y + 4);
  y -= 20;

  // -------------------------------------------------------------------------
  // 7. Legal statement
  // -------------------------------------------------------------------------
  const legalSize = 10;

  if (data.document_type === "quittance") {
    const landlordName = sanitize(data.landlord.full_name);
    const tenantFullName = sanitize(
      `${data.tenant.first_name} ${data.tenant.last_name}`,
    );
    const legalText =
      `Je soussigne(e) ${landlordName}, reconnais avoir recu de ${tenantFullName} ` +
      `la somme indiquee ci-dessus, pour quittance et solde de tout compte pour la periode susvisee.`;
    const legalLines = wrapText(legalText, regular, legalSize, CONTENT_WIDTH);
    for (const line of legalLines) {
      y = drawText(page, line, MARGIN, y, regular, legalSize);
    }
  } else {
    // recu — paiement partiel, mention obligatoire loi 1989
    const landlordName = sanitize(data.landlord.full_name);
    const tenantFullName = sanitize(
      `${data.tenant.first_name} ${data.tenant.last_name}`,
    );
    const legalText =
      `Je soussigne(e) ${landlordName}, reconnais avoir recu de ${tenantFullName} ` +
      `la somme indiquee ci-dessus.`;
    const legalLines = wrapText(legalText, regular, legalSize, CONTENT_WIDTH);
    for (const line of legalLines) {
      y = drawText(page, line, MARGIN, y, regular, legalSize);
    }
    y -= 6;
    // Mandatory warning — loi du 6 juillet 1989, art. 21
    const warningText =
      "Ce recu ne libere pas le locataire du solde du pour la periode concernee.";
    const warningLines = wrapText(warningText, bold, legalSize, CONTENT_WIDTH);
    for (const line of warningLines) {
      y = drawText(page, line, MARGIN, y, bold, legalSize, RED);
    }
  }

  y -= 20;

  // -------------------------------------------------------------------------
  // 8. "Fait a" line + signature placeholder
  // -------------------------------------------------------------------------
  const faitAText = `Fait a ${sanitize(data.landlord.address)}, le ${formatDateFr(data.generated_at)}`;
  const faitALines = wrapText(faitAText, regular, sectionSize, CONTENT_WIDTH);
  for (const line of faitALines) {
    y = drawText(page, line, MARGIN, y, regular, sectionSize);
  }
  y -= 30;

  // Signature block (right-aligned)
  const sigLabel = "Signature du bailleur :";
  const sigLabelWidth = regular.widthOfTextAtSize(sigLabel, smallSize);
  page.drawText(sigLabel, {
    x: PAGE_WIDTH - MARGIN - sigLabelWidth,
    y,
    size: smallSize,
    font: regular,
    color: DARK_GRAY,
  });
  y -= 14;

  const sigName = sanitize(data.landlord.full_name);
  const sigNameWidth = bold.widthOfTextAtSize(sigName, smallSize);
  page.drawText(sigName, {
    x: PAGE_WIDTH - MARGIN - sigNameWidth,
    y,
    size: smallSize,
    font: bold,
    color: BLACK,
  });

  // -------------------------------------------------------------------------
  // 9. Footer (bottom of page, fixed position)
  // -------------------------------------------------------------------------
  const footerY = MARGIN - 10;
  drawRule(page, footerY + 14, LIGHT_GRAY);

  const shortId = data.receipt_id.substring(0, 8).toUpperCase();
  const footerText = `Document genere par EasyRent  -  Ref : ${shortId}  -  ${formatDateFr(data.generated_at)}`;
  const footerWidth = regular.widthOfTextAtSize(sanitize(footerText), 8);
  page.drawText(sanitize(footerText), {
    x: (PAGE_WIDTH - footerWidth) / 2,
    y: footerY,
    size: 8,
    font: regular,
    color: LIGHT_GRAY,
  });

  return pdfDoc.save();
}


// ---------------------------------------------------------------------------
// Pure helper — exported for unit tests
// ---------------------------------------------------------------------------

/**
 * Determines whether a receipt is a "quittance" (full payment) or a "recu"
 * (partial payment).
 *
 * @param totalCents   Sum of all included payments (rent + charges)
 * @param leaseRentCents   lease.rent_amount_cents
 * @param leaseChargesCents  lease.charges_amount_cents
 */
export function computeDocumentType(
  totalCents: number,
  leaseRentCents: number,
  leaseChargesCents: number,
): "quittance" | "recu" {
  const due = leaseRentCents + leaseChargesCents;
  return totalCents >= due ? "quittance" : "recu";
}
