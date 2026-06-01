/**
 * Minimal Resend API wrapper.
 *
 * Uses native Deno fetch — no SDK dependency.
 * Handles error mapping per plan §3.4:
 *   200       → { id }
 *   422       → throws with code "tenant_no_email"  (Resend rejected address)
 *   429       → throws with code "quota_exceeded"
 *   401/403   → throws with code "email_send_failed" (key revoked / domain unverified)
 *   4xx other → throws with code "email_send_failed"
 *   5xx       → throws with code "email_send_failed" (retry-eligible but no retry at MVP)
 */

import type { EmailAttachment } from "./types.ts";

const RESEND_API_URL = "https://api.resend.com/emails";

export class ResendError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly httpStatus?: number,
  ) {
    super(message);
    this.name = "ResendError";
  }
}

export interface SendEmailParams {
  to: string;
  subject: string;
  html: string;
  attachments: EmailAttachment[];
}

/**
 * Sends an email via the Resend REST API.
 *
 * Reads secrets from environment:
 *   RESEND_API_KEY      — Bearer token (required)
 *   RESEND_FROM_EMAIL   — Sender address e.g. "EasyRent <noreply@easyrent.app>" (required)
 *
 * @returns { id: string } — Resend message ID on success.
 * @throws ResendError on any failure.
 */
export async function sendEmailViaResend(
  params: SendEmailParams,
): Promise<{ id: string }> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL");

  if (!apiKey || !fromEmail) {
    throw new ResendError(
      "email_config_missing",
      "RESEND_API_KEY or RESEND_FROM_EMAIL environment variable is not set",
    );
  }

  const payload = {
    from: fromEmail,
    to: [params.to],
    subject: params.subject,
    html: params.html,
    attachments: params.attachments,
  };

  let res: Response;
  try {
    res = await fetch(RESEND_API_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });
  } catch (err) {
    throw new ResendError(
      "email_send_failed",
      `Network error calling Resend: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

  if (res.status === 200 || res.status === 201) {
    let body: { id?: string };
    try {
      body = await res.json();
    } catch {
      throw new ResendError(
        "email_send_failed",
        `Resend returned ${res.status} but body was not valid JSON`,
        res.status,
      );
    }
    if (!body.id) {
      throw new ResendError(
        "email_send_failed",
        "Resend returned success but response had no id field",
        res.status,
      );
    }
    return { id: body.id };
  }

  // Read error body for logging (no PII — just the Resend error message)
  let errorDetail = "(unreadable)";
  try {
    const errBody = await res.json();
    errorDetail = JSON.stringify(errBody);
  } catch {
    // ignore
  }

  if (res.status === 429) {
    throw new ResendError(
      "quota_exceeded",
      "Resend quota exceeded (429)",
      429,
    );
  }

  if (res.status === 422) {
    // Resend rejected the email address — treated as tenant_no_email
    // Do NOT log errorDetail: it may contain the tenant's email address (PII).
    console.error(
      `[send-receipt] resend_422 — address rejected, status=${res.status}`,
    );
    throw new ResendError(
      "tenant_no_email",
      "Resend rejected the recipient address (422)",
      422,
    );
  }

  if (res.status === 401 || res.status === 403) {
    console.error(
      `[send-receipt] resend_auth_failure status=${res.status} — API key revoked or domain not verified`,
    );
    throw new ResendError(
      "email_send_failed",
      `Resend auth failure (${res.status}) — check RESEND_API_KEY and domain verification`,
      res.status,
    );
  }

  // All other 4xx / 5xx — log status only, do NOT include errorDetail (may contain PII).
  console.error(
    `[send-receipt] resend_error status=${res.status}`,
  );
  throw new ResendError(
    "email_send_failed",
    `Resend returned HTTP ${res.status}`,
    res.status,
  );
}
