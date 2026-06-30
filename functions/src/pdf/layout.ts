/**
 * PDF builder pour quittances / reçus EasyRent.
 *
 * Conforme à la loi du 6 juillet 1989, art. 21. A4 portrait via pdf-lib
 * StandardFonts (Helvetica WinAnsi — couvre Latin-1, suffit pour FR sans
 * caractères exotiques).
 *
 * Port verbatim de `supabase/functions/generate-receipt/pdf_layout.ts`
 * (Deno) — seule différence : imports Node (pdf-lib) au lieu de deps.ts.
 *
 * NE PAS modifier le rendu sans tests de régression visuelle — la mise
 * en forme est validée pour conformité légale FR.
 */

import {PDFDocument, StandardFonts, rgb} from "pdf-lib";
import type {PDFFont, PDFPage} from "pdf-lib";

import {
  formatDateFr,
  formatEurosFromCents,
  formatMonthYearFr,
} from "./money_format";

// A4 dimensions en points PDF (1 pt = 1/72 inch)
const PAGE_WIDTH = 595.28;
const PAGE_HEIGHT = 841.89;
const MARGIN = 50;
const CONTENT_WIDTH = PAGE_WIDTH - 2 * MARGIN;

const BLACK = rgb(0, 0, 0);
const DARK_GRAY = rgb(0.3, 0.3, 0.3);
const LIGHT_GRAY = rgb(0.6, 0.6, 0.6);
const RED = rgb(0.8, 0.1, 0.1);

export type DocumentType = "quittance" | "recu";

export interface ReceiptPdfData {
  receiptId: string;
  documentType: DocumentType;
  landlordFullName: string;
  landlordAddress: string;
  tenantFirstName: string;
  tenantLastName: string;
  propertyAddress: string;
  periodStart: string; // YYYY-MM-DD
  periodEnd: string;
  rentCents: number;
  chargesCents: number;
  totalCents: number;
  lastPaidAt: string; // ISO timestamp
  generatedAt: Date;
}

/** Remplace les caractères non-WinAnsi par des équivalents ASCII safe. */
function sanitize(text: string): string {
  return text
    .replace(/Œ/g, "OE")
    .replace(/œ/g, "oe")
    .replace(/«/g, "\"")
    .replace(/»/g, "\"")
    .replace(/’/g, "'")
    .replace(/–/g, "-")
    .replace(/—/g, "-")
    .replace(/\u00A0/g, " ");
}

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

function drawText(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  font: PDFFont,
  size: number,
  color = BLACK,
): number {
  page.drawText(sanitize(text), {x, y, size, font, color});
  return y - size * 1.4;
}

function drawRule(page: PDFPage, y: number, color = LIGHT_GRAY): void {
  page.drawLine({
    start: {x: MARGIN, y},
    end: {x: PAGE_WIDTH - MARGIN, y},
    thickness: 0.5,
    color,
  });
}

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

export async function generateReceiptPdf(
  data: ReceiptPdfData,
): Promise<Uint8Array> {
  const pdfDoc = await PDFDocument.create();
  const page = pdfDoc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);

  const regular = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const bold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

  let y = PAGE_HEIGHT - MARGIN;

  // 1. Header — bailleur (top-left) + date generated (top-right)
  const smallSize = 9;
  const bodySize = 10;

  y = drawText(page, data.landlordFullName, MARGIN, y, bold, bodySize);

  const landlordAddressLines = wrapText(
    sanitize(data.landlordAddress),
    regular,
    bodySize,
    CONTENT_WIDTH * 0.5,
  );
  for (const line of landlordAddressLines) {
    y = drawText(page, line, MARGIN, y, regular, bodySize, DARK_GRAY);
  }

  const dateLabel = `Fait le ${formatDateFr(data.generatedAt)}`;
  const dateLabelWidth = regular.widthOfTextAtSize(dateLabel, smallSize);
  page.drawText(sanitize(dateLabel), {
    x: PAGE_WIDTH - MARGIN - dateLabelWidth,
    y: PAGE_HEIGHT - MARGIN,
    size: smallSize,
    font: regular,
    color: DARK_GRAY,
  });

  y -= 20;

  // 2. Title centred
  const title =
    data.documentType === "quittance"
      ? "QUITTANCE DE LOYER"
      : "RECU DE PAIEMENT";
  const titleSize = 18;
  const titleWidth = bold.widthOfTextAtSize(title, titleSize);
  const titleX = (PAGE_WIDTH - titleWidth) / 2;
  page.drawText(title, {x: titleX, y, size: titleSize, font: bold, color: BLACK});
  y -= titleSize * 1.6;

  const subtitle = `Loyer de ${formatMonthYearFr(data.periodStart)}`;
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

  // 3. Tenant block
  const sectionSize = 10;
  y = drawText(page, "Locataire :", MARGIN, y, bold, sectionSize);
  const tenantName = `${data.tenantFirstName} ${data.tenantLastName}`;
  y = drawText(page, tenantName, MARGIN + 10, y, regular, sectionSize);
  y -= 12;

  // 4. Property
  y = drawText(page, "Logement :", MARGIN, y, bold, sectionSize);
  const propertyLines = wrapText(
    sanitize(data.propertyAddress),
    regular,
    sectionSize,
    CONTENT_WIDTH - 10,
  );
  for (const line of propertyLines) {
    y = drawText(page, line, MARGIN + 10, y, regular, sectionSize, DARK_GRAY);
  }
  y -= 12;

  // 5. Period
  y = drawText(page, "Periode concernee :", MARGIN, y, bold, sectionSize);
  const periodText =
    `du ${formatDateFr(data.periodStart)} au ${formatDateFr(data.periodEnd)}`;
  y = drawText(page, periodText, MARGIN + 10, y, regular, sectionSize);
  y -= 16;

  drawRule(page, y + 4);
  y -= 16;

  // 6. Financial summary
  y = drawText(page, "Detail du paiement :", MARGIN, y, bold, sectionSize);
  y -= 4;

  y = drawLabelValue(
    page,
    "Loyer hors charges",
    formatEurosFromCents(data.rentCents),
    y,
    regular,
    regular,
    sectionSize,
  );

  y = drawLabelValue(
    page,
    "Charges",
    formatEurosFromCents(data.chargesCents),
    y,
    regular,
    regular,
    sectionSize,
  );

  y -= 4;
  drawRule(page, y + 4, DARK_GRAY);
  y -= 8;

  y = drawLabelValue(
    page,
    "Total recu",
    formatEurosFromCents(data.totalCents),
    y,
    bold,
    bold,
    sectionSize + 1,
  );

  const paymentDateLabel = `Date du paiement : ${formatDateFr(data.lastPaidAt)}`;
  y = drawText(page, paymentDateLabel, MARGIN, y - 4, regular, smallSize, DARK_GRAY);
  y -= 20;

  drawRule(page, y + 4);
  y -= 20;

  // 7. Legal statement
  const legalSize = 10;
  const landlordName = sanitize(data.landlordFullName);
  const tenantFullName = sanitize(
    `${data.tenantFirstName} ${data.tenantLastName}`,
  );

  if (data.documentType === "quittance") {
    const legalText =
      `Je soussigne(e) ${landlordName}, reconnais avoir recu de ${tenantFullName} ` +
      "la somme indiquee ci-dessus, pour quittance et solde de tout compte pour la periode susvisee.";
    const legalLines = wrapText(legalText, regular, legalSize, CONTENT_WIDTH);
    for (const line of legalLines) {
      y = drawText(page, line, MARGIN, y, regular, legalSize);
    }
  } else {
    const legalText =
      `Je soussigne(e) ${landlordName}, reconnais avoir recu de ${tenantFullName} ` +
      "la somme indiquee ci-dessus.";
    const legalLines = wrapText(legalText, regular, legalSize, CONTENT_WIDTH);
    for (const line of legalLines) {
      y = drawText(page, line, MARGIN, y, regular, legalSize);
    }
    y -= 6;
    const warningText =
      "Ce recu ne libere pas le locataire du solde du pour la periode concernee.";
    const warningLines = wrapText(warningText, bold, legalSize, CONTENT_WIDTH);
    for (const line of warningLines) {
      y = drawText(page, line, MARGIN, y, bold, legalSize, RED);
    }
  }

  y -= 20;

  // 8. "Fait le" + signature
  const faitLeText = `Fait le ${formatDateFr(data.generatedAt)}`;
  const faitLeLines = wrapText(faitLeText, regular, sectionSize, CONTENT_WIDTH);
  for (const line of faitLeLines) {
    y = drawText(page, line, MARGIN, y, regular, sectionSize);
  }
  y -= 30;

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

  const sigNameWidth = bold.widthOfTextAtSize(landlordName, smallSize);
  page.drawText(landlordName, {
    x: PAGE_WIDTH - MARGIN - sigNameWidth,
    y,
    size: smallSize,
    font: bold,
    color: BLACK,
  });

  // 9. Footer
  const footerY = MARGIN - 10;
  drawRule(page, footerY + 14, LIGHT_GRAY);

  const shortId = data.receiptId.substring(0, 8).toUpperCase();
  const footerText =
    `Document genere par EasyRent  -  Ref : ${shortId}  -  ${formatDateFr(data.generatedAt)}`;
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

/**
 * Détermine si un paiement constitue une quittance (paiement intégral du
 * loyer dû) ou un reçu (paiement partiel — mention obligatoire loi 1989).
 */
export function computeDocumentType(
  totalCents: number,
  leaseRentCents: number,
  leaseChargesCents: number,
): DocumentType {
  const due = leaseRentCents + leaseChargesCents;
  return totalCents >= due ? "quittance" : "recu";
}
