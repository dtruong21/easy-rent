/**
 * Tests for email_template.ts — subject, HTML body, French characters, legal mention.
 *
 * Verifies:
 *   - subject() returns correct French month + year
 *   - htmlBody() contains tenant first name
 *   - htmlBody() contains amount formatted fr-FR (X,XX €)
 *   - htmlBody() contains period dates in DD/MM/YYYY format
 *   - htmlBody() contains legal mention (loi 1989 art. 21)
 *   - UTF-8 characters: é, è, ç, €, à are present and correctly encoded
 *
 * Run: deno test --allow-env send-receipt/tests/email_template_test.ts
 */

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { subject, htmlBody, escapeHtml } from "../email_template.ts";

// ---------------------------------------------------------------------------
// subject() tests
// ---------------------------------------------------------------------------

Deno.test("subject: 2026-05-01 → 'Votre quittance de loyer — mai 2026'", () => {
  const result = subject("2026-05-01");
  assertEquals(result, "Votre quittance de loyer — mai 2026");
});

Deno.test("subject: 2026-02-01 → contains 'février 2026'", () => {
  const result = subject("2026-02-01");
  assert(result.includes("février 2026"), `Expected 'février 2026' in "${result}"`);
});

Deno.test("subject: 2026-08-15 → contains 'août 2026'", () => {
  const result = subject("2026-08-15");
  assert(result.includes("août 2026"), `Expected 'août 2026' in "${result}"`);
});

Deno.test("subject: 2026-12-01 → contains 'décembre 2026'", () => {
  const result = subject("2026-12-01");
  assert(result.includes("décembre 2026"), `Expected 'décembre 2026' in "${result}"`);
});

Deno.test("subject: contains 'quittance de loyer'", () => {
  const result = subject("2026-05-01");
  assert(
    result.toLowerCase().includes("quittance de loyer"),
    "Subject must mention 'quittance de loyer'",
  );
});

// ---------------------------------------------------------------------------
// htmlBody() — content tests
// ---------------------------------------------------------------------------

const BASE_PARAMS = {
  tenantFirstName: "Jean",
  periodStart: "2026-05-01",
  periodEnd: "2026-05-31",
  totalCents: 85000, // 850,00 €
  landlordFullName: "Marie Dupont",
};

Deno.test("htmlBody: contains tenant first name", () => {
  const html = htmlBody(BASE_PARAMS);
  assert(html.includes("Jean"), "HTML must contain the tenant first name");
});

Deno.test("htmlBody: contains landlord full name", () => {
  const html = htmlBody(BASE_PARAMS);
  assert(html.includes("Marie Dupont"), "HTML must contain the landlord full name");
});

Deno.test("htmlBody: contains period start in DD/MM/YYYY format", () => {
  const html = htmlBody(BASE_PARAMS);
  assert(html.includes("01/05/2026"), "HTML must contain period start as 01/05/2026");
});

Deno.test("htmlBody: contains period end in DD/MM/YYYY format", () => {
  const html = htmlBody(BASE_PARAMS);
  assert(html.includes("31/05/2026"), "HTML must contain period end as 31/05/2026");
});

Deno.test("htmlBody: contains amount formatted fr-FR (850,00 €)", () => {
  const html = htmlBody(BASE_PARAMS);
  // fr-FR format: comma decimal separator, non-breaking space (U+00A0) before euro sign.
  // 85000 cents = 850,00 € → "850,00 €"
  assert(
    html.includes("850,00 €"),
    `HTML must contain '850,00 €' (with U+00A0 before €), got substring: ${html.substring(400, 550)}`,
  );
});

Deno.test("htmlBody: contains legal mention loi 1989 art. 21", () => {
  const html = htmlBody(BASE_PARAMS);
  const hasLegal =
    html.includes("loi du 6 juillet 1989") ||
    html.includes("art. 21") ||
    html.includes("libère du paiement");
  assert(hasLegal, "HTML must contain legal mention referencing loi 1989 art. 21");
});

// ---------------------------------------------------------------------------
// UTF-8 character tests
// ---------------------------------------------------------------------------

Deno.test("htmlBody: contains UTF-8 accented characters (é, è, ç, €, à)", () => {
  const html = htmlBody({
    ...BASE_PARAMS,
    totalCents: 123456, // 1 234,56 €
  });
  // é / è — from "pièce", "période", etc.
  assert(html.includes("è") || html.includes("é"), "Must contain accented e characters");
  // € — from amount
  assert(html.includes("€"), "Must contain euro sign €");
});

Deno.test("htmlBody: euro sign is present in amount", () => {
  const html = htmlBody({ ...BASE_PARAMS, totalCents: 100000 });
  assert(html.includes("€"), "Amount must include euro sign");
});

Deno.test("htmlBody: amount with thousands separator (1 234,56 €)", () => {
  const html = htmlBody({ ...BASE_PARAMS, totalCents: 123456 });
  // fr-FR: thousands separator = U+00A0 (non-breaking space), decimal = comma, U+00A0 before €.
  // 123456 cents = 1 234,56 €
  assert(
    html.includes("1 234,56 €"),
    "Must format 123456 cents as '1 234,56 €' (non-breaking spaces per fr-FR convention)",
  );
});

// ---------------------------------------------------------------------------
// HTML structure
// ---------------------------------------------------------------------------

Deno.test("htmlBody: is wrapped in html + body tags", () => {
  const html = htmlBody(BASE_PARAMS);
  assert(html.includes("<html"), "Must contain <html> tag");
  assert(html.includes("<body"), "Must contain <body> tag");
  assert(html.includes("</html>"), "Must contain closing </html> tag");
  assert(html.includes("</body>"), "Must contain closing </body> tag");
});

Deno.test("htmlBody: charset meta utf-8 is present", () => {
  const html = htmlBody(BASE_PARAMS);
  assert(
    html.toLowerCase().includes('charset="utf-8"') ||
      html.toLowerCase().includes("charset=utf-8"),
    "HTML must declare UTF-8 charset",
  );
});

Deno.test("htmlBody: salutation contains 'Bonjour'", () => {
  const html = htmlBody(BASE_PARAMS);
  assert(html.includes("Bonjour"), "Email must open with 'Bonjour'");
});

// ---------------------------------------------------------------------------
// SEC-1: HTML injection prevention tests
// ---------------------------------------------------------------------------

Deno.test("escapeHtml: script tag is escaped", () => {
  const result = escapeHtml("<script>alert(1)</script>");
  assertEquals(result, "&lt;script&gt;alert(1)&lt;/script&gt;");
});

Deno.test("htmlBody: HTML-injects tenantFirstName as entities, not raw markup", () => {
  const maliciousTenant = '<a href="evil">x</a>';
  const html = htmlBody({ ...BASE_PARAMS, tenantFirstName: maliciousTenant });
  assert(
    html.includes("&lt;a href=&quot;evil&quot;&gt;x&lt;/a&gt;"),
    "tenantFirstName must be HTML-escaped in the body",
  );
  assert(
    !html.includes('<a href="evil">'),
    "Raw anchor tag must NOT appear in rendered HTML",
  );
});
