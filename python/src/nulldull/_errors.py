from __future__ import annotations

from typing import Any, Dict, Optional, Tuple

__all__ = ["NullDullError"]


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
    ) -> None:
        self.status = status
        self.code = code
        self.message = message if message is not None else f"NullDull request failed ({status} {code})."
        self.detail = detail
        self.request_id = request_id
        self.retry_after = retry_after
        self.body = body
        super().__init__(self.message)

    def __str__(self) -> str:
        return self.message

    def __repr__(self) -> str:
        return f"NullDullError(status={self.status!r}, code={self.code!r}, message={self.message!r})"

    def __reduce__(self) -> Tuple[Any, ...]:
        return (
            _rebuild,
            (self.status, self.code, self.message, self.detail, self.request_id, self.retry_after, self.body),
        )


def _rebuild(
    status: int,
    code: str,
    message: str,
    detail: Optional[str],
    request_id: Optional[str],
    retry_after: Optional[int],
    body: Optional[Dict[str, Any]],
) -> NullDullError:
    return NullDullError(
        status, code, message, detail=detail, request_id=request_id, retry_after=retry_after, body=body
    )


def client_error(code: str, message: str) -> NullDullError:
    return NullDullError(0, code, message)


def invalid_argument(message: str) -> NullDullError:
    return client_error("INVALID_ARGUMENT", message)
