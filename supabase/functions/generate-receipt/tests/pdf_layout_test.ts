/**
 * Unit tests for the PDF builder (generateReceiptPdf).
 *
 * Tests validate:
 * 1. The function returns a non-empty Uint8Array (valid PDF bytes).
 * 2. The PDF is large enough to contain real content (> 1KB).
 * 3. Raw PDF bytes contain required legal text fragments.
 *    Note: pdf-lib encodes text in PDF content streams; we search the raw bytes
 *    for text literals that appear in the PDF object stream. This is a
 *    "content smoke test" rather than a full parse.
 *
 * Run: deno test --allow-net supabase/functions/generate-receipt/tests/pdf_layout_test.ts
 */
import {
  assertEquals,
  assertInstanceOf,
  assert,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { generateReceiptPdf } from "../pdf_layout.ts";
import type { ReceiptData } from "../types.ts";

const BASE_DATA: ReceiptData = {
  receipt_id: "11111111-1111-4111-8111-111111111111",
  document_type: "quittance",
  landlord: {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    full_name: "Marie Dupont",
    address: "12 rue de la Paix, 75001 Paris",
  },
  tenant: {
    id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    first_name: "Jean",
    last_name: "Martin",
  },
  property: {
    id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
    address: "5 avenue de la Republique, 75011 Paris",
  },
  period_start: "2026-05-01",
  period_end: "2026-05-31",
  rent_cents: 100000,
  charges_cents: 20000,
  total_cents: 120000,
  last_paid_at: "2026-05-03T10:00:00Z",
  generated_at: new Date("2026-05-31T12:00:00Z"),
};

/**
 * Extracts text from a pdf-lib generated PDF by:
 * 1. Decompressing the FlateDecode content stream using pako inflate
 * 2. Decoding hex-encoded PDF text strings (e.g. <4D61726965> -> "Marie")
 *
 * pdf-lib encodes all text as hex strings in content streams, so plain
 * text search on the raw bytes never works. We must decompress + decode.
 */
async function pdfToText(bytes: Uint8Array): Promise<string> {
  const { inflate } = await import("https://esm.sh/pako@1.0.11");

  const latin1 = new TextDecoder("latin1");
  const raw = latin1.decode(bytes);

  // Find the start of the FlateDecode stream
  const streamMarker = "stream\n";
  const streamStart = raw.indexOf(streamMarker);
  if (streamStart === -1) {
    // No compressed stream — return raw latin1 decoded content
    return raw;
  }

  const streamBytes = bytes.slice(streamStart + streamMarker.length);

  let decompressedText = "";
  try {
    const decompressed = inflate(streamBytes) as Uint8Array;
    decompressedText = latin1.decode(decompressed);
  } catch {
    // Fallback: return raw decoded bytes
    decompressedText = raw;
  }

  // Decode hex text strings: <hexstring> -> ascii/latin1 text
  const hexDecoded = decompressedText.replace(/<([0-9A-Fa-f]+)>/g, (_, hex: string) => {
    let result = "";
    for (let i = 0; i < hex.length; i += 2) {
      result += String.fromCharCode(parseInt(hex.substring(i, i + 2), 16));
    }
    return result;
  });

  return hexDecoded;
}

Deno.test("generateReceiptPdf: returns Uint8Array", async () => {
  const bytes = await generateReceiptPdf(BASE_DATA);
  assertInstanceOf(bytes, Uint8Array);
});

Deno.test("generateReceiptPdf: PDF size > 1KB (valid compressed PDF)", async () => {
  const bytes = await generateReceiptPdf(BASE_DATA);
  assert(bytes.length > 1000, `PDF too small: ${bytes.length} bytes`);
});

Deno.test("generateReceiptPdf: starts with PDF magic bytes %PDF", async () => {
  const bytes = await generateReceiptPdf(BASE_DATA);
  const magic = new TextDecoder().decode(bytes.slice(0, 4));
  assertEquals(magic, "%PDF");
});

Deno.test("generateReceiptPdf (quittance): title contains QUITTANCE", async () => {
  const bytes = await generateReceiptPdf(BASE_DATA);
  const text = await pdfToText(bytes);
  assert(text.includes("QUITTANCE"), "PDF should contain 'QUITTANCE'");
});

Deno.test("generateReceiptPdf (quittance): contains landlord name", async () => {
  const bytes = await generateReceiptPdf(BASE_DATA);
  const text = await pdfToText(bytes);
  assert(text.includes("Marie Dupont"), "PDF should contain landlord name");
});

Deno.test("generateReceiptPdf (quittance): contains tenant name", async () => {
  const bytes = await generateReceiptPdf(BASE_DATA);
  const text = await pdfToText(bytes);
  assert(
    text.includes("Jean") && text.includes("Martin"),
    "PDF should contain tenant name",
  );
});

Deno.test("generateReceiptPdf (quittance): contains property address fragment", async () => {
  const bytes = await generateReceiptPdf(BASE_DATA);
  const text = await pdfToText(bytes);
  assert(text.includes("Republique"), "PDF should contain property address");
});

Deno.test("generateReceiptPdf (quittance): contains period dates", async () => {
  const bytes = await generateReceiptPdf(BASE_DATA);
  const text = await pdfToText(bytes);
  assert(text.includes("01/05/2026"), "PDF should contain period_start date");
  assert(text.includes("31/05/2026"), "PDF should contain period_end date");
});

Deno.test("generateReceiptPdf (quittance): does NOT contain partial payment warning", async () => {
  const bytes = await generateReceiptPdf(BASE_DATA);
  const text = await pdfToText(bytes);
  assert(
    !text.includes("ne libere pas le locataire"),
    "Quittance should NOT contain partial payment warning",
  );
});

Deno.test("generateReceiptPdf (recu): title contains RECU", async () => {
  const recuData: ReceiptData = {
    ...BASE_DATA,
    document_type: "recu",
    total_cents: 60000, // partial
  };
  const bytes = await generateReceiptPdf(recuData);
  const text = await pdfToText(bytes);
  assert(text.includes("RECU"), "PDF should contain 'RECU'");
});

Deno.test("generateReceiptPdf (recu): contains mandatory partial payment warning", async () => {
  const recuData: ReceiptData = {
    ...BASE_DATA,
    document_type: "recu",
    total_cents: 60000,
  };
  const bytes = await generateReceiptPdf(recuData);
  const text = await pdfToText(bytes);
  // Mandatory mention per loi 6 juillet 1989, art. 21
  assert(
    text.includes("ne libere pas le locataire"),
    "Recu MUST contain 'ne libere pas le locataire' (loi 1989, art. 21)",
  );
});

Deno.test("generateReceiptPdf: contains EasyRent footer reference", async () => {
  const bytes = await generateReceiptPdf(BASE_DATA);
  const text = await pdfToText(bytes);
  assert(text.includes("EasyRent"), "PDF should contain EasyRent branding");
  // Short receipt ID in footer (uppercase, first 8 chars)
  assert(text.includes("11111111"), "PDF footer should contain receipt short ID");
});

Deno.test("generateReceiptPdf: different receipt IDs produce different PDFs", async () => {
  const data1: ReceiptData = {
    ...BASE_DATA,
    receipt_id: "11111111-1111-4111-8111-111111111111",
  };
  const data2: ReceiptData = {
    ...BASE_DATA,
    receipt_id: "22222222-2222-4222-8222-222222222222",
  };
  const bytes1 = await generateReceiptPdf(data1);
  const bytes2 = await generateReceiptPdf(data2);
  // PDFs should differ (different receipt IDs in footer — different bytes even if same size)
  assert(
    bytes1.length !== bytes2.length ||
      !bytes1.every((b, i) => b === bytes2[i]),
    "Different receipt IDs should produce different PDFs",
  );
});
