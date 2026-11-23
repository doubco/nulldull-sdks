package com.nulldull.sdk

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The one exception type every SDK call throws.
 *
 * Server errors carry the HTTP [status] and the API's [code] (for example `FORBIDDEN` or
 * `RATE_LIMITED`). Errors raised by the SDK itself have [status] `0` and one of the client codes in
 * the companion object, such as [INVALID_ARGUMENT] or [TIMEOUT].
 *
 * ```kotlin
 * try {
 *     client.grid.getPage("my-blog", "hello-world")
 * } catch (e: NullDullException) {
 *     if (e.status == 404) showNotFound() else throw e
 * }
 * ```
 *
 * @property status HTTP status, or `0` when there was no response.
 * @property code The error body's `code`, `REQUEST_FAILED` for a non-JSON error body, or a client code.
 * @property detail The error body's `detail`, for example `LOCALE_EXPORT_TOO_LARGE`.
 * @property requestId The `X-Request-Id` response header, or else `CF-Ray`. Quote it in support requests.
 * @property retryAfter `Retry-After` in seconds when the response had one. A `429` with more than 30
 *   seconds is thrown at once instead of retried, so you can decide when to try again.
 * @property body The whole decoded JSON error body. Locale errors put `key`, `language` and `issues` here.
 *
 * A Free workspace that has used its monthly public requests gets `429 RATE_LIMITED` from Grid delivery
 * with [reason] [PUBLIC_REQUESTS_PAUSED] ([isPublicRequestsPaused]), [renewsAt] and a [retryAfter] of
 * days, so it is never retried. Show a calm "temporarily unavailable" state until [renewsAt].
 */
public class NullDullException(
    public val status: Int,
    public val code: String,
    message: String? = null,
    public val detail: String? = null,
    public val requestId: String? = null,
    public val retryAfter: Long? = null,
    public val body: JsonObject? = null,
    cause: Throwable? = null,
) : Exception(message ?: "NullDull request failed ($status $code).", cause) {

    /** Always the error's message: the body's `message`, or a generated one. */
    override val message: String get() = super.message!!

    /** The error body's `reason` when it is a string, for example [PUBLIC_REQUESTS_PAUSED]. */
    public val reason: String? get() = stringField("reason")

    /**
     * The error body's `renewsAt` when it is a string: an ISO 8601 UTC time, as the API sends it.
     * For [PUBLIC_REQUESTS_PAUSED] it is the first instant of the next UTC month.
     */
    public val renewsAt: String? get() = stringField("renewsAt")

    /** True for a `429` whose [reason] is [PUBLIC_REQUESTS_PAUSED]: the workspace's public requests are paused. */
    public val isPublicRequestsPaused: Boolean get() = status == 429 && reason == PUBLIC_REQUESTS_PAUSED

    private fun stringField(name: String): String? =
        (body?.get(name) as? JsonPrimitive)?.takeIf { it.isString }?.content

    override fun toString(): String = buildString {
        append("NullDullException(status=").append(status).append(", code=").append(code)
        if (detail != null) append(", detail=").append(detail)
        reason?.let { append(", reason=").append(it) }
        renewsAt?.let { append(", renewsAt=").append(it) }
        if (requestId != null) append(", requestId=").append(requestId)
        if (retryAfter != null) append(", retryAfter=").append(retryAfter)
        append("): ").append(message)
    }

    public companion object {
        /** Bad client options or method arguments, found before any request. */
        public const val INVALID_ARGUMENT: String = "INVALID_ARGUMENT"

        /** A `memory` or `locale` call on a client without `workspaceId`. */
        public const val WORKSPACE_REQUIRED: String = "WORKSPACE_REQUIRED"

        /** A `memory` or `locale` call with a public key. No request is sent. */
        public const val PRIVATE_KEY_REQUIRED: String = "PRIVATE_KEY_REQUIRED"

        /** The transport failed (DNS, TLS, connection reset). Retried automatically. */
        public const val NETWORK_ERROR: String = "NETWORK_ERROR"

        /** One attempt took longer than the client's `timeout`. Not retried. */
        public const val TIMEOUT: String = "TIMEOUT"

        /** The HTTP call was cancelled outside the coroutine (for example `Dispatcher.cancelAll()`). */
        public const val ABORTED: String = "ABORTED"

        /** A `2xx` body was not the expected JSON, or a cursor did not advance during iteration. */
        public const val INVALID_RESPONSE: String = "INVALID_RESPONSE"

        /**
         * The `reason` of a `429` from Grid delivery when a Free workspace has used its monthly
         * public requests. Delivery resumes when the allowance renews ([renewsAt]) or soon after an upgrade.
         */
        public const val PUBLIC_REQUESTS_PAUSED: String = "PUBLIC_REQUESTS_PAUSED"

        /** An error response without a JSON body, or a redirect (redirects are never followed). */
        public const val REQUEST_FAILED: String = "REQUEST_FAILED"

        internal fun client(code: String, message: String, cause: Throwable? = null) =
            NullDullException(status = 0, code = code, message = message, cause = cause)

        internal fun invalidArgument(message: String) = client(INVALID_ARGUMENT, message)
    }
}
