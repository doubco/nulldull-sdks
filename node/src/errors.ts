/** Error codes raised by the SDK itself, before or without an HTTP response (`status` 0). */
export type ClientErrorCode =
  | "INVALID_ARGUMENT"
  | "WORKSPACE_REQUIRED"
  | "PRIVATE_KEY_REQUIRED"
  | "NETWORK_ERROR"
  | "TIMEOUT"
  | "ABORTED"
  | "INVALID_RESPONSE";

export interface NullDullErrorInit {
  status: number;
  code: string;
  message?: string;
  detail?: string | null;
  requestId?: string | null;
  retryAfter?: number | null;
  body?: Record<string, unknown> | null;
  cause?: unknown;
}

/**
 * The one error type every SDK call raises. `status` is the HTTP status, or 0 for client-side
 * errors. `code` is the API's error code (for example `FORBIDDEN`) or a client code.
 */
export class NullDullError extends Error {
  override readonly name = "NullDullError";
  readonly status: number;
  readonly code: string;
  readonly detail: string | null;
  readonly requestId: string | null;
  /** `Retry-After` in seconds, when the response carried it. */
  readonly retryAfter: number | null;
  /** The decoded JSON error body (Locale errors add `key`, `language` and `issues`). */
  readonly body: Record<string, unknown> | null;

  constructor(init: NullDullErrorInit) {
    super(init.message ?? `NullDull request failed (${init.status} ${init.code}).`, init.cause === undefined ? undefined : { cause: init.cause });
    this.status = init.status;
    this.code = init.code;
    this.detail = init.detail ?? null;
    this.requestId = init.requestId ?? null;
    this.retryAfter = init.retryAfter ?? null;
    this.body = init.body ?? null;
  }
}

export const clientError = (code: ClientErrorCode, message: string, cause?: unknown) =>
  new NullDullError({ status: 0, code, message, cause });

export const invalidArgument = (message: string) => clientError("INVALID_ARGUMENT", message);
