/**
 * Edge Function: generate-receipt
 *
 * Generates a legally compliant rent receipt PDF (quittance or recu) per
 * loi du 6 juillet 1989, art. 21.
 *
 * POST /functions/v1/generate-receipt
 * Headers: Authorization: Bearer <JWT>
 * Body (mode 1 — by payment IDs):
 *   { "payment_ids": ["uuid", ...] }
 * Body (mode 2 — by period):
 *   { "lease_id": "uuid", "period_start": "YYYY-MM-DD", "period_end": "YYYY-MM-DD" }
 *
 * Returns:
 *   { receipt_id, document_type, total_cents, pdf_url, pdf_url_expires_at }
 */

import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { createClientWithJwt } from "../_shared/supabase_client.ts";
import { generateReceiptPdf, computeDocumentType } from "./pdf_layout.ts";
import type {
  GenerateReceiptRequest,
  Payment,
  Lease,
  Landlord,
  Tenant,
  Property,
  ReceiptData,
  DocumentType,
  SuccessResponse,
  ErrorResponse,
} from "./types.ts";

// UUID v4 regex for basic input validation
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function isUuid(s: string): boolean {
  return UUID_RE.test(s);
}

function isIsoDate(s: string): boolean {
  if (!DATE_RE.test(s)) return false;
  const d = new Date(s);
  return !isNaN(d.getTime());
}

function jsonError(
  status: number,
  error: string,
  extra?: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify({ error, ...extra } as ErrorResponse), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function jsonOk(body: SuccessResponse): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  // CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  // Method check
  if (req.method !== "POST") {
    return jsonError(405, "Method not allowed");
  }

  // Parse body
  let body: GenerateReceiptRequest;
  try {
    body = await req.json();
  } catch {
    return jsonError(400, "Invalid JSON body");
  }

  // Validate input modes
  const hasPaymentIds =
    body.payment_ids !== undefined && body.payment_ids !== null;
  const hasPeriod =
    body.lease_id !== undefined ||
    body.period_start !== undefined ||
    body.period_end !== undefined;

  if (hasPaymentIds && hasPeriod) {
    return jsonError(
      400,
      "Provide either payment_ids or (lease_id + period_start + period_end), not both",
    );
  }
  if (!hasPaymentIds && !hasPeriod) {
    return jsonError(
      400,
      "Provide either payment_ids or (lease_id + period_start + period_end)",
    );
  }

  // Validate payment_ids format
  if (hasPaymentIds) {
    const ids = body.payment_ids!;
    if (!Array.isArray(ids) || ids.length === 0) {
      return jsonError(400, "payment_ids doit contenir au moins un identifiant");
    }
    for (const id of ids) {
      if (!isUuid(id)) {
        return jsonError(400, `payment_ids contient un UUID invalide : ${id}`);
      }
    }
  }

  // Validate period mode
  if (hasPeriod) {
    if (!body.lease_id || !isUuid(body.lease_id)) {
      return jsonError(400, "lease_id invalide ou manquant");
    }
    if (!body.period_start || !isIsoDate(body.period_start)) {
      return jsonError(400, "period_start invalide (attendu : YYYY-MM-DD)");
    }
    if (!body.period_end || !isIsoDate(body.period_end)) {
      return jsonError(400, "period_end invalide (attendu : YYYY-MM-DD)");
    }
    if (body.period_end <= body.period_start) {
      return jsonError(400, "period_end doit etre posterieure a period_start");
    }
  }

  // Build Supabase client with JWT (RLS auto-applied)
  let supabase;
  try {
    supabase = createClientWithJwt(req);
  } catch {
    return jsonError(500, "Configuration serveur manquante");
  }

  // Auth: get landlord_id from JWT
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    // Note: with verify_jwt=true Supabase blocks the request before reaching
    // this handler, but we keep this check as defence-in-depth.
    return jsonError(401, "Non authentifie");
  }
  const landlordId = user.id;

  // Load landlord profile — must have full_name and address for legal compliance
  const { data: landlordRow, error: landlordErr } = await supabase
    .from("landlords")
    .select("id, full_name, address")
    .eq("id", landlordId)
    .maybeSingle();

  if (landlordErr) {
    console.error(`[generate-receipt] landlord load error landlord=${landlordId}`, landlordErr.message);
    return jsonError(500, "Erreur lors du chargement du profil bailleur");
  }
  if (!landlordRow) {
    return jsonError(404, "Profil bailleur introuvable");
  }

  // Validate profile completeness (legal requirement)
  const missingFields: string[] = [];
  if (!landlordRow.full_name || landlordRow.full_name.trim() === "") {
    missingFields.push("full_name");
  }
  if (!landlordRow.address || landlordRow.address.trim() === "") {
    missingFields.push("address");
  }
  if (missingFields.length > 0) {
    return jsonError(422, "profile_incomplete — completez votre profil bailleur avant de generer une quittance", {
      missing: missingFields,
    });
  }

  const landlord: Landlord = {
    id: landlordRow.id,
    full_name: landlordRow.full_name,
    address: landlordRow.address,
  };

  // ---------------------------------------------------------------------------
  // Load payments
  // ---------------------------------------------------------------------------
  let paymentIds: string[];

  if (hasPaymentIds) {
    // Mode 1: explicit payment IDs
    paymentIds = body.payment_ids!;
  } else {
    // Mode 2: derive payment IDs from lease + period
    const { data: periodPayments, error: periodErr } = await supabase
      .from("payments")
      .select("id")
      .eq("lease_id", body.lease_id!)
      .gte("period_start", body.period_start!)
      .lte("period_end", body.period_end!)
      .is("deleted_at", null);

    if (periodErr) {
      console.error(`[generate-receipt] period payments error lease=${body.lease_id}`, periodErr.message);
      return jsonError(500, "Erreur lors de la recherche des paiements");
    }
    if (!periodPayments || periodPayments.length === 0) {
      return jsonError(422, "Aucun paiement actif trouve pour cette periode");
    }
    paymentIds = periodPayments.map((p: { id: string }) => p.id);
  }

  // Load full payment data
  const { data: payments, error: paymentsErr } = await supabase
    .from("payments")
    .select(
      "id, lease_id, landlord_id, rent_amount_cents, charges_amount_cents, period_start, period_end, paid_at, deleted_at",
    )
    .in("id", paymentIds)
    .is("deleted_at", null);

  if (paymentsErr) {
    console.error(`[generate-receipt] payments load error landlord=${landlordId}`, paymentsErr.message);
    return jsonError(500, "Erreur lors du chargement des paiements");
  }

  // Cross-user protection: RLS returns empty if payments belong to another landlord
  // but we also verify count matches to detect cross-user attempts explicitly
  if (!payments || payments.length === 0) {
    return jsonError(404, "Aucun paiement actif trouve pour les identifiants fournis");
  }
  if (payments.length !== paymentIds.length) {
    // Some IDs were filtered by RLS or are soft-deleted — 403 for cross-user, 404 for deleted
    console.warn(`[generate-receipt] payment count mismatch requested=${paymentIds.length} found=${payments.length} landlord=${landlordId}`);
    return jsonError(403, "Un ou plusieurs paiements sont inaccessibles ou appartiennent a un autre compte");
  }

  // Validate all payments belong to the same lease
  const leaseIds = new Set(payments.map((p: Payment) => p.lease_id));
  if (leaseIds.size > 1) {
    return jsonError(422, "Les paiements fournis appartiennent a des baux differents");
  }
  const leaseId = [...leaseIds][0];

  // ---------------------------------------------------------------------------
  // Load lease + property + tenant
  // ---------------------------------------------------------------------------
  const { data: leaseRow, error: leaseErr } = await supabase
    .from("leases")
    .select(
      "id, landlord_id, rent_amount_cents, charges_amount_cents, tenant_id, property_id, tenants(id, first_name, last_name), properties(id, address)",
    )
    .eq("id", leaseId)
    .maybeSingle();

  if (leaseErr) {
    console.error(`[generate-receipt] lease load error lease=${leaseId}`, leaseErr.message);
    return jsonError(500, "Erreur lors du chargement du bail");
  }
  if (!leaseRow) {
    return jsonError(404, "Bail introuvable");
  }

  // Defensive ownership check (should already be enforced by RLS)
  if (leaseRow.landlord_id !== landlordId) {
    return jsonError(403, "Acces refuse");
  }

  const tenant: Tenant = leaseRow.tenants as Tenant;
  const property: Property = leaseRow.properties as Property;

  // Validate tenant and property exist (should never happen with FK constraints, but defensive)
  if (!tenant || !tenant.first_name || !tenant.last_name) {
    return jsonError(422, "Informations locataire incompletes — verifiez la fiche locataire");
  }
  if (!property || !property.address || property.address.trim() === "") {
    return jsonError(422, "Adresse du logement manquante — verifiez la fiche bien");
  }

  // ---------------------------------------------------------------------------
  // Compute totals
  // ---------------------------------------------------------------------------
  let rentCents = 0;
  let chargesCents = 0;
  let lastPaidAt = payments[0].paid_at;

  for (const p of payments as Payment[]) {
    rentCents += p.rent_amount_cents;
    chargesCents += p.charges_amount_cents;
    if (p.paid_at > lastPaidAt) lastPaidAt = p.paid_at;
  }
  const totalCents = rentCents + chargesCents;

  // Compute period bounds from payments
  const sortedStarts = (payments as Payment[]).map((p) => p.period_start).sort();
  const sortedEnds = (payments as Payment[]).map((p) => p.period_end).sort();
  const periodStart = sortedStarts[0];
  const periodEnd = sortedEnds[sortedEnds.length - 1];

  // Determine document type
  const documentType: DocumentType = computeDocumentType(
    totalCents,
    leaseRow.rent_amount_cents,
    leaseRow.charges_amount_cents,
  );

  // ---------------------------------------------------------------------------
  // Generate a UUID for this receipt
  // ---------------------------------------------------------------------------
  const receiptId = crypto.randomUUID();
  const generatedAt = new Date();

  // ---------------------------------------------------------------------------
  // Generate PDF
  // ---------------------------------------------------------------------------
  let pdfBytes: Uint8Array;
  try {
    const receiptData: ReceiptData = {
      receipt_id: receiptId,
      document_type: documentType,
      landlord,
      tenant,
      property,
      period_start: periodStart,
      period_end: periodEnd,
      rent_cents: rentCents,
      charges_cents: chargesCents,
      total_cents: totalCents,
      last_paid_at: lastPaidAt,
      generated_at: generatedAt,
    };
    pdfBytes = await generateReceiptPdf(receiptData);
  } catch (err) {
    console.error(`[generate-receipt] PDF generation failed landlord=${landlordId} receipt=${receiptId}`, err);
    return jsonError(500, "Erreur lors de la generation du PDF");
  }

  // ---------------------------------------------------------------------------
  // Upload PDF to Storage
  // ---------------------------------------------------------------------------
  const pdfPath = `${landlordId}/${receiptId}.pdf`;

  const { error: uploadErr } = await supabase.storage
    .from("receipts")
    .upload(pdfPath, pdfBytes, {
      contentType: "application/pdf",
      upsert: false,
    });

  if (uploadErr) {
    console.error(`[generate-receipt] storage upload failed landlord=${landlordId} path=${pdfPath}`, uploadErr.message);
    return jsonError(500, "Erreur lors du stockage du PDF");
  }

  // ---------------------------------------------------------------------------
  // Insert receipt record in DB
  // ---------------------------------------------------------------------------
  const { error: insertErr } = await supabase.from("receipts").insert({
    id: receiptId,
    landlord_id: landlordId,
    lease_id: leaseId,
    payment_ids: paymentIds,
    period_start: periodStart,
    period_end: periodEnd,
    rent_cents: rentCents,
    charges_cents: chargesCents,
    total_cents: totalCents,
    document_type: documentType,
    pdf_path: pdfPath,
    generated_at: generatedAt.toISOString(),
    generated_by: landlordId,
  });

  if (insertErr) {
    // PDF is already uploaded — log orphan for manual cleanup
    console.error(
      `[orphan-pdf] landlord=${landlordId} path=${pdfPath} — DB insert failed: ${insertErr.message}`,
    );
    return jsonError(500, "Erreur lors de l enregistrement de la quittance");
  }

  // ---------------------------------------------------------------------------
  // Generate signed URL (5 minutes = 300 seconds)
  // ---------------------------------------------------------------------------
  const signedUrlExpiry = 300;
  const { data: signedUrlData, error: signedUrlErr } = await supabase.storage
    .from("receipts")
    .createSignedUrl(pdfPath, signedUrlExpiry);

  if (signedUrlErr || !signedUrlData?.signedUrl) {
    console.error(`[generate-receipt] signed URL failed landlord=${landlordId} path=${pdfPath}`, signedUrlErr?.message);
    return jsonError(500, "Quittance enregistree mais erreur de generation du lien de telechargement");
  }

  const expiresAt = new Date(
    Date.now() + signedUrlExpiry * 1000,
  ).toISOString();

  console.log(`[generate-receipt] success landlord=${landlordId} receipt=${receiptId} type=${documentType} total_cents=${totalCents}`);

  return jsonOk({
    receipt_id: receiptId,
    document_type: documentType,
    total_cents: totalCents,
    pdf_url: signedUrlData.signedUrl,
    pdf_url_expires_at: expiresAt,
  });
});
