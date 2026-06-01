// ---------------------------------------------------------------------------
// Domain types used by the generate-receipt Edge Function
// ---------------------------------------------------------------------------

export interface Landlord {
  id: string;
  full_name: string;
  address: string;
}

export interface Tenant {
  id: string;
  first_name: string;
  last_name: string;
}

export interface Property {
  id: string;
  address: string;
}

export interface Lease {
  id: string;
  landlord_id: string;
  rent_amount_cents: number;
  charges_amount_cents: number;
  tenant_id: string;
  property_id: string;
  tenants: Tenant;
  properties: Property;
}

export interface Payment {
  id: string;
  lease_id: string;
  landlord_id: string;
  rent_amount_cents: number;
  charges_amount_cents: number;
  period_start: string; // ISO date "YYYY-MM-DD"
  period_end: string;   // ISO date "YYYY-MM-DD"
  paid_at: string;      // ISO timestamp
  deleted_at: string | null;
}

// ---------------------------------------------------------------------------
// Request / response shapes
// ---------------------------------------------------------------------------

export interface RequestByPaymentIds {
  payment_ids: string[];
  lease_id?: never;
  period_start?: never;
  period_end?: never;
  /** Target DB schema. Accepted values: "public" (default) or "dev". */
  schema?: string;
}

export interface RequestByPeriod {
  payment_ids?: never;
  lease_id: string;
  period_start: string; // "YYYY-MM-DD"
  period_end: string;   // "YYYY-MM-DD"
  /** Target DB schema. Accepted values: "public" (default) or "dev". */
  schema?: string;
}

export type GenerateReceiptRequest = RequestByPaymentIds | RequestByPeriod;

export type DocumentType = "quittance" | "recu";

export interface SuccessResponse {
  receipt_id: string;
  document_type: DocumentType;
  total_cents: number;
  pdf_url: string;
  pdf_url_expires_at: string;
  /** ISO date "YYYY-MM-DD" — earliest period_start across included payments */
  period_start: string;
  /** ISO date "YYYY-MM-DD" — latest period_end across included payments */
  period_end: string;
}

export interface ErrorResponse {
  error: string;
  missing?: string[];
}

// ---------------------------------------------------------------------------
// Data passed to the PDF builder
// ---------------------------------------------------------------------------

export interface ReceiptData {
  receipt_id: string;
  document_type: DocumentType;
  landlord: Landlord;
  tenant: Tenant;
  property: Property;
  period_start: string; // "YYYY-MM-DD"
  period_end: string;   // "YYYY-MM-DD"
  rent_cents: number;
  charges_cents: number;
  total_cents: number;
  /** Latest paid_at timestamp across all included payments */
  last_paid_at: string;
  generated_at: Date;
}
