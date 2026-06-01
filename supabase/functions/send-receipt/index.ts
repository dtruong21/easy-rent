/**
 * Edge Function: send-receipt
 *
 * Sends a legally compliant rent receipt PDF (quittance) to the tenant by email
 * via Resend, then persists the send event in the DB via RPC mark_receipt_as_sent.
 *
 * POST /functions/v1/send-receipt
 * Headers: Authorization: Bearer <JWT>
 * Body: { "receipt_id": "<uuid>", "schema": "public" | "dev" }
 *
 * Returns 200:
 *   { "success": true, "sent_at": "<ISO>", "sent_to_email": "<email>", "resend_id": "<id>" }
 *
 * Error codes:
 *   400 invalid_request     — malformed body, invalid UUID, invalid schema
 *   401 (Supabase)          — JWT absent or invalid
 *   404 receipt_not_found   — RLS blocked (cross-user or non-existent)
 *   405 method_not_allowed  — method != POST
 *   422 tenant_no_email     — tenant.email is null or empty
 *   422 receipt_invalid     — receipt is voided or stale
 *   422 pdf_unavailable     — pdf_path is null or signed URL fetch failed
 *   429 quota_exceeded      — Resend returned 429
 *   500 email_config_missing — RESEND_API_KEY or RESEND_FROM_EMAIL not set
 *   500 email_send_failed   — Resend returned non-200 (non-429)
 *   500 internal_error      — unexpected DB / Storage error
 */

import { handleCors, getCorsHeaders } from "../_shared/cors.ts";
import { createClientWithJwt, parseSchema } from "../_shared/supabase_client.ts";
import { subject, htmlBody } from "./email_template.ts";
import { sendEmailViaResend, ResendError } from "./resend_client.ts";
import type {
  SendReceiptRequest,
  SuccessResponse,
  ErrorResponse,
  ReceiptRow,
} from "./types.ts";

// UUID v4 regex — same as generate-receipt
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isUuid(s: string): boolean {
  return UUID_RE.test(s);
}

function jsonError(
  status: number,
  error: string,
  corsH: Record<string, string>,
  message?: string,
): Response {
  const body: ErrorResponse = message ? { error, message } : { error };
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsH, "Content-Type": "application/json" },
  });
}

function jsonOk(body: SuccessResponse, corsH: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { ...corsH, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  // CORS check: validates Origin and handles preflight.
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  // Per-request CORS headers (never "*")
  const corsH = getCorsHeaders(req);

  // Method check
  if (req.method !== "POST") {
    return jsonError(405, "method_not_allowed", corsH, "Seules les requêtes POST sont acceptées");
  }

  // Parse body
  let body: SendReceiptRequest;
  try {
    body = await req.json();
  } catch {
    return jsonError(400, "invalid_request", corsH, "Corps JSON invalide");
  }

  // Validate receipt_id
  if (!body.receipt_id || typeof body.receipt_id !== "string") {
    return jsonError(400, "invalid_request", corsH, "receipt_id est requis");
  }
  if (!isUuid(body.receipt_id)) {
    return jsonError(400, "invalid_request", corsH, "receipt_id n'est pas un UUID valide");
  }

  // Validate schema
  let schemaName: "public" | "dev";
  try {
    schemaName = parseSchema((body as Record<string, unknown>).schema);
  } catch {
    return jsonError(
      400,
      "invalid_request",
      corsH,
      'schema invalide — valeurs acceptées : "public", "dev"',
    );
  }

  // Build Supabase client with JWT (RLS auto-applied)
  let supabase;
  try {
    supabase = createClientWithJwt(req);
  } catch {
    return jsonError(500, "internal_error", corsH, "Configuration serveur manquante");
  }

  // Auth: verify landlord identity
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return jsonError(401, "unauthorized", corsH, "Non authentifié");
  }
  const landlordId = user.id;

  console.log(
    `[send-receipt] start landlord=${landlordId} receipt=${body.receipt_id}`,
  );

  // ---------------------------------------------------------------------------
  // Load receipt with nested lease + tenant via single JOIN query
  // RLS filters receipts WHERE landlord_id = auth.uid() automatically.
  // ---------------------------------------------------------------------------
  const { data: receiptRow, error: receiptErr } = await supabase
    .schema(schemaName)
    .from("receipts")
    .select(
      "id, landlord_id, lease_id, pdf_path, is_voided, is_stale, period_start, period_end, total_cents, document_type, leases(tenant_id, tenants(first_name, last_name, email))",
    )
    .eq("id", body.receipt_id)
    .maybeSingle() as {
    data: ReceiptRow | null;
    error: unknown;
  };

  if (receiptErr) {
    console.error(
      `[send-receipt] receipt load error landlord=${landlordId} receipt=${body.receipt_id}`,
      receiptErr instanceof Error ? receiptErr.message : String(receiptErr),
    );
    return jsonError(500, "internal_error", corsH, "Erreur lors du chargement de la quittance");
  }

  // RLS returns null for cross-user or non-existent — unified 404 (no account leak)
  if (!receiptRow) {
    return jsonError(404, "receipt_not_found", corsH, "Quittance introuvable");
  }

  // ---------------------------------------------------------------------------
  // Validate receipt state
  // ---------------------------------------------------------------------------
  if (receiptRow.is_voided) {
    return jsonError(422, "receipt_invalid", corsH, "La quittance est annulée — impossible à envoyer");
  }
  if (receiptRow.is_stale) {
    return jsonError(422, "receipt_invalid", corsH, "La quittance est périmée — impossible à envoyer");
  }
  if (!receiptRow.pdf_path || receiptRow.pdf_path.trim() === "") {
    return jsonError(422, "pdf_unavailable", corsH, "PDF indisponible pour cette quittance. Régénérez-la.");
  }

  // ---------------------------------------------------------------------------
  // Validate tenant email
  // ---------------------------------------------------------------------------
  const tenantData = receiptRow.leases?.tenants;
  if (!tenantData || !tenantData.email || tenantData.email.trim() === "") {
    return jsonError(
      422,
      "tenant_no_email",
      corsH,
      "Impossible d'envoyer : le locataire n'a pas d'adresse email. Mettez à jour sa fiche.",
    );
  }

  const tenantEmail = tenantData.email.trim();
  const tenantFirstName = tenantData.first_name ?? "";

  // ---------------------------------------------------------------------------
  // Load landlord full_name for email signature
  // ---------------------------------------------------------------------------
  const { data: landlordRow, error: landlordErr } = await supabase
    .schema(schemaName)
    .from("landlords")
    .select("full_name")
    .eq("id", landlordId)
    .maybeSingle();

  if (landlordErr || !landlordRow || !landlordRow.full_name) {
    console.error(
      `[send-receipt] landlord load error landlord=${landlordId}`,
      landlordErr instanceof Error ? landlordErr.message : String(landlordErr),
    );
    return jsonError(500, "internal_error", corsH, "Erreur lors du chargement du profil bailleur");
  }

  // ---------------------------------------------------------------------------
  // Retrieve PDF: create signed URL then fetch bytes
  // ---------------------------------------------------------------------------
  const { data: signedData, error: signedErr } = await supabase.storage
    .from("receipts")
    .createSignedUrl(receiptRow.pdf_path, 60); // 60s — fetch is immediate

  if (signedErr || !signedData?.signedUrl) {
    console.error(
      `[send-receipt] signed URL failed landlord=${landlordId} path=${receiptRow.pdf_path}`,
      signedErr instanceof Error ? signedErr.message : String(signedErr),
    );
    return jsonError(422, "pdf_unavailable", corsH, "Impossible de récupérer le PDF de la quittance. Régénérez-la.");
  }

  let pdfBase64: string;
  try {
    const pdfResponse = await fetch(signedData.signedUrl);
    if (!pdfResponse.ok) {
      throw new Error(`Storage fetch returned HTTP ${pdfResponse.status}`);
    }
    const pdfBytes = new Uint8Array(await pdfResponse.arrayBuffer());
    // MVP : OK car quittances < 100KB. Pour PDFs plus gros (FEAT-009?), chunked encoder requis pour éviter stack overflow.
    pdfBase64 = btoa(String.fromCharCode(...pdfBytes));
  } catch (err) {
    console.error(
      `[send-receipt] pdf fetch failed landlord=${landlordId} receipt=${body.receipt_id}`,
      err instanceof Error ? err.message : String(err),
    );
    return jsonError(422, "pdf_unavailable", corsH, "Erreur lors de la récupération du PDF. Régénérez-la.");
  }

  // ---------------------------------------------------------------------------
  // Build email
  // ---------------------------------------------------------------------------
  // Filename format: "quittance_mai_2026.pdf"
  const monthSlug = receiptRow.period_start
    ? receiptRow.period_start.slice(0, 7).replace("-", "_") // "2026_05"
    : "receipt";
  const attachmentFilename = `quittance_${monthSlug}.pdf`;

  const emailSubject = subject(receiptRow.period_start);
  const emailHtml = htmlBody({
    tenantFirstName,
    periodStart: receiptRow.period_start,
    periodEnd: receiptRow.period_end,
    totalCents: receiptRow.total_cents,
    landlordFullName: landlordRow.full_name,
  });

  // ---------------------------------------------------------------------------
  // Send via Resend
  // ---------------------------------------------------------------------------
  let resendId: string;
  try {
    const resendResult = await sendEmailViaResend({
      to: tenantEmail,
      subject: emailSubject,
      html: emailHtml,
      attachments: [{ filename: attachmentFilename, content: pdfBase64 }],
    });
    resendId = resendResult.id;
  } catch (err) {
    if (err instanceof ResendError) {
      if (err.code === "quota_exceeded") {
        console.log(
          `[send-receipt] resend_429 landlord=${landlordId} receipt=${body.receipt_id}`,
        );
        return jsonError(429, "quota_exceeded", corsH, "Quota d'envoi dépassé. Réessayez le mois prochain.");
      }
      if (err.code === "tenant_no_email") {
        return jsonError(422, "tenant_no_email", corsH, "L'adresse email du locataire n'a pas pu être utilisée. Vérifiez la fiche locataire.");
      }
      if (err.code === "email_config_missing") {
        console.error(
          `[send-receipt] email_config_missing landlord=${landlordId}`,
        );
        return jsonError(500, "email_config_missing", corsH, "Configuration email manquante côté serveur");
      }
      // email_send_failed and others
      console.error(
        `[send-receipt] resend_error code=${err.code} landlord=${landlordId} receipt=${body.receipt_id}`,
        err.message,
      );
      return jsonError(500, "email_send_failed", corsH, "Échec de l'envoi de l'email. Réessayez plus tard.");
    }
    // Unknown error
    console.error(
      `[send-receipt] unexpected error landlord=${landlordId} receipt=${body.receipt_id}`,
      err instanceof Error ? err.message : String(err),
    );
    return jsonError(500, "email_send_failed", corsH, "Échec de l'envoi de l'email. Réessayez plus tard.");
  }

  // ---------------------------------------------------------------------------
  // Persist send event via RPC mark_receipt_as_sent
  // RPC failure after successful Resend call: log critical + return 200.
  // Rationale: the email was sent; returning 500 would cause retry → double email.
  // ---------------------------------------------------------------------------
  const { data: updatedReceipt, error: rpcErr } = await supabase
    .schema(schemaName)
    .rpc("mark_receipt_as_sent", {
      p_receipt_id: body.receipt_id,
      p_sent_to_email: tenantEmail,
    });

  let sentAt: string;

  if (rpcErr) {
    // Critical: email sent but not persisted in DB
    console.error(
      `[email-sent-not-persisted] receipt=${body.receipt_id} resend_id=${resendId}`,
      rpcErr instanceof Error ? rpcErr.message : String(rpcErr),
    );
    // Return 200 anyway — email IS delivered, audit trail missing is lesser harm
    sentAt = new Date().toISOString();
  } else {
    sentAt = updatedReceipt?.sent_at ?? new Date().toISOString();
  }

  console.log(
    `[send-receipt] success landlord=${landlordId} receipt=${body.receipt_id} resend_id=${resendId}`,
  );

  return jsonOk(
    {
      success: true,
      sent_at: sentAt,
      sent_to_email: tenantEmail,
      resend_id: resendId,
    },
    corsH,
  );
});
