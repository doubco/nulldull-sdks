from __future__ import annotations

from typing import Any, Dict, Optional, Tuple

__all__ = ["PUBLIC_REQUESTS_PAUSED", "NullDullError", "is_public_requests_paused"]

PUBLIC_REQUESTS_PAUSED = "PUBLIC_REQUESTS_PAUSED"
"""The ``reason`` of the ``429`` public Grid delivery answers while a Free workspace has used its
monthly public requests. It lifts when the allowance renews (``renews_at``) or soon after an upgrade."""


class NullDullError(Exception):
    """The one error type every SDK call raises.

    ``status`` is the HTTP status, or ``0`` for client-side errors. ``code`` is the API's error
    code (for example ``FORBIDDEN``) or a client code such as ``INVALID_ARGUMENT``, ``TIMEOUT`` or
    ``NETWORK_ERROR``. ``str(error)`` is ``message``.
    """

    status: int
    code: str
    message: str
    detail: Optional[str]
    request_id: Optional[str]
    retry_after: Optional[int]
    """``Retry-After`` in seconds, when the response carried it."""
    reason: Optional[str]
    """The body's ``reason`` (for example ``PUBLIC_REQUESTS_PAUSED`` or ``QUOTA_EXCEEDED``)."""
    renews_at: Optional[str]
    """The body's ``renewsAt``, an ISO 8601 UTC time as sent (on ``PUBLIC_REQUESTS_PAUSED``)."""
    body: Optional[Dict[str, Any]]
    """The decoded JSON error body (Locale errors add ``key``, ``language`` and ``issues``)."""

    def __init__(
        self,
        status: int,
        code: str,
        message: Optional[str] = None,
        *,
        detail: Optional[str] = None,
        request_id: Optional[str] = None,
        retry_after: Optional[int] = None,
        body: Optional[Dict[str, Any]] = None,
        reason: Optional[str] = None,
        renews_at: Optional[str] = None,
    ) -> None:
        self.status = status
        self.code = code
        self.message = message if message is not None else f"NullDull request failed ({status} {code})."
        self.detail = detail
        self.request_id = request_id
        self.retry_after = retry_after
        self.body = body
        self.reason = reason
        self.renews_at = renews_at
        super().__init__(self.message)

    @property
    def public_requests_paused(self) -> bool:
        """True for the ``429`` of a workspace whose monthly public requests are used up.

        It is not retried: wait until ``renews_at`` (``retry_after`` seconds) or an upgrade.
        """
        return self.status == 429 and self.reason == PUBLIC_REQUESTS_PAUSED

    def __str__(self) -> str:
        return self.message

    def __repr__(self) -> str:
        return f"NullDullError(status={self.status!r}, code={self.code!r}, message={self.message!r})"

    def __reduce__(self) -> Tuple[Any, ...]:
        return (
            _rebuild,
            (
                self.status,
                self.code,
                self.message,
                self.detail,
                self.request_id,
                self.retry_after,
                self.body,
                self.reason,
                self.renews_at,
            ),
        )


def _rebuild(
    status: int,
    code: str,
    message: str,
    detail: Optional[str],
    request_id: Optional[str],
    retry_after: Optional[int],
    body: Optional[Dict[str, Any]],
    reason: Optional[str] = None,
    renews_at: Optional[str] = None,
) -> NullDullError:
    return NullDullError(
        status,
        code,
        message,
        detail=detail,
        request_id=request_id,
        retry_after=retry_after,
        body=body,
        reason=reason,
        renews_at=renews_at,
    )


def is_public_requests_paused(error: object) -> bool:
    """True when ``error`` is a :class:`NullDullError` for paused public requests."""
    return isinstance(error, NullDullError) and error.public_requests_paused


def client_error(code: str, message: str) -> NullDullError:
    return NullDullError(0, code, message)


def invalid_argument(message: str) -> NullDullError:
    return client_error("INVALID_ARGUMENT", message)
