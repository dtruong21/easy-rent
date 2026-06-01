// ---------------------------------------------------------------------------
// Domain types used by the send-receipt Edge Function
// ---------------------------------------------------------------------------

export interface SendReceiptRequest {
  receipt_id: string;
  /** Target DB schema. Accepted values: "public" (default) or "dev". */
  schema?: string;
}

export interface SuccessResponse {
  success: true;
  sent_at: string;       // ISO timestamp
  sent_to_email: string; // email address the receipt was sent to
  resend_id: string;     // Resend message ID
}

export interface ErrorResponse {
  error: string;
  message?: string;
}

// ---------------------------------------------------------------------------
// Internal data shapes
// ---------------------------------------------------------------------------

export interface ReceiptRow {
  id: string;
  landlord_id: string;
  lease_id: string;
  pdf_path: string | null;
  is_voided: boolean;
  is_stale: boolean;
  period_start: string;   // "YYYY-MM-DD"
  period_end: string;     // "YYYY-MM-DD"
  total_cents: number;
  document_type: string;
  leases: {
    tenant_id: string;
    tenants: {
      first_name: string;
      last_name: string;
      email: string | null;
    };
  };
}

export interface EmailAttachment {
  filename: string;
  content: string; // base64-encoded bytes
}

export interface ResendEmailPayload {
  to: string[];
  subject: string;
  html: string;
  attachments: EmailAttachment[];
}
