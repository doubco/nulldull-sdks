"""Transport-independent logic shared by the sync and async clients."""

from __future__ import annotations

import json
import math
import re
import time
from dataclasses import dataclass
from datetime import timezone
from email.utils import parsedate_to_datetime
from typing import Any, Callable, Dict, FrozenSet, List, Mapping, Optional, Sequence, Tuple, Union
from urllib.parse import parse_qsl, quote, unquote, urljoin, urlsplit

from ._errors import NullDullError, client_error, invalid_argument
from ._version import __version__

DEFAULT_BASE_URL = "https://nulldull.com"
DEFAULT_TIMEOUT = 30.0
DEFAULT_MAX_RETRIES = 2
MAX_RETRY_AFTER_SECONDS = 30
"""``Retry-After`` values above this (seconds) are raised instead of waited for (SPEC.md section 6)."""
RETRYABLE = frozenset({429, 502, 503, 504})

_API_KEY = re.compile(r"nd_(pub|sec)_[a-f0-9]{64}")
_WORKSPACE_ID = re.compile(r"[a-zA-Z0-9_-]{1,128}")
_GRID_KEY = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
_LOCALE = re.compile(r"[a-z]{2,3}(?:-[a-z0-9]{2,8})*")
_DEFAULT_PORTS = {"http": 80, "https": 443}
# encodeURIComponent leaves these unescaped besides letters and digits.
_URI_COMPONENT_SAFE = "-_.!~*'()"


class _Unset:
    """Marker for "argument not given", distinct from ``None`` (which means root for folder filters)."""

    _instance: Optional[_Unset] = None

    def __new__(cls) -> _Unset:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __repr__(self) -> str:
        return "UNSET"

    def __bool__(self) -> bool:
        return False


UNSET: Any = _Unset()

QueryValue = Union[str, int, bool, Sequence[str], None]
Query = Mapping[str, QueryValue]


def backoff(retry: int) -> float:
    """Seconds to wait before retry ``retry`` (1-based): 0.5 s, then 1 s, ... No jitter in 0.1.0."""
    return 0.5 * float(2 ** (retry - 1))


def encode_component(value: str) -> str:
    return quote(value, safe=_URI_COMPONENT_SAFE)


def segment(value: str) -> str:
    return encode_component(value)


def query_string(query: Optional[Query] = None) -> str:
    """Percent-encodes a query string. Absent values are omitted and lists repeat the key."""
    parts: List[str] = []
    for name, value in (query or {}).items():
        if value is None:
            continue
        if isinstance(value, bool):
            values: Sequence[str] = ["true" if value else "false"]
        elif isinstance(value, (str, int)):
            values = [str(value)]
        else:
            values = [str(item) for item in value]
        for item in values:
            parts.append(f"{encode_component(name)}={encode_component(item)}")
    return "?" + "&".join(parts) if parts else ""


def _header(headers: Mapping[str, str], name: str) -> Optional[str]:
    value = headers.get(name)
    return None if value is None or value == "" else value


def request_id(headers: Mapping[str, str]) -> Optional[str]:
    return _header(headers, "x-request-id") or _header(headers, "cf-ray")


def parse_retry_after(value: Optional[str], now: Optional[float] = None) -> Optional[int]:
    """Seconds from a ``Retry-After`` header (delta-seconds or HTTP date), or ``None``."""
    if value is None:
        return None
    trimmed = value.strip()
    if re.fullmatch(r"[0-9]+", trimmed):
        return int(trimmed)
    try:
        date = parsedate_to_datetime(trimmed)
    except (TypeError, ValueError, IndexError):
        return None
    if date is None:
        return None  # type: ignore[unreachable]
    if date.tzinfo is None:
        date = date.replace(tzinfo=timezone.utc)
    timestamp = date.timestamp()
    current = time.time() if now is None else now
    return max(0, math.ceil(timestamp - current))


_EXTENDED_FILENAME = re.compile(r"filename\*\s*=\s*([^']*)'[^']*'([^;]+)", re.IGNORECASE)
_QUOTED_FILENAME = re.compile(r'(?:^|;)\s*filename\s*=\s*"((?:[^"\\]|\\.)*)"', re.IGNORECASE)
_PLAIN_FILENAME = re.compile(r"(?:^|;)\s*filename\s*=\s*([^;]+)", re.IGNORECASE)
_BAD_PERCENT = re.compile(r"%(?![0-9A-Fa-f]{2})")


def parse_filename(value: Optional[str]) -> Optional[str]:
    """File name from ``Content-Disposition``: RFC 5987 ``filename*`` first, then ``filename``."""
    if not value:
        return None
    extended = _EXTENDED_FILENAME.search(value)
    if extended and extended.group(2):
        encoded = extended.group(2).strip()
        if not _BAD_PERCENT.search(encoded):
            try:
                return unquote(encoded, encoding="utf-8", errors="strict")
            except UnicodeDecodeError:
                pass  # fall through to the plain parameter
    quoted = _QUOTED_FILENAME.search(value)
    if quoted:
        return re.sub(r"\\(.)", r"\1", quoted.group(1))
    plain = _PLAIN_FILENAME.search(value)
    return plain.group(1).strip() if plain and plain.group(1) else None


def _reject_constant(name: str) -> Any:
    raise ValueError(f"invalid JSON constant {name}")


def decode_json(data: bytes) -> Any:
    return json.loads(data, parse_constant=_reject_constant)


def error_from(status: int, headers: Mapping[str, str], data: bytes) -> NullDullError:
    body: Optional[Dict[str, Any]] = None
    try:
        parsed = decode_json(data)
        if isinstance(parsed, dict):
            body = parsed
    except ValueError:
        pass  # Not JSON: a router page, a gateway error or an empty body.
    code = body.get("code") if body is not None else None
    message = body.get("message") if body is not None else None
    detail = body.get("detail") if body is not None else None
    return NullDullError(
        status,
        code if isinstance(code, str) else "REQUEST_FAILED",
        message if isinstance(message, str) else None,
        detail=detail if isinstance(detail, str) else None,
        request_id=request_id(headers),
        retry_after=parse_retry_after(headers.get("retry-after")),
        body=body,
    )


def invalid_response(status: int, headers: Mapping[str, str]) -> NullDullError:
    return NullDullError(
        status,
        "INVALID_RESPONSE",
        "NullDull returned a response that is not valid JSON.",
        request_id=request_id(headers),
    )


# --------------------------------------------------------------------------- URLs


@dataclass(frozen=True)
class _Origin:
    scheme: str
    host: str
    port: int

    def __str__(self) -> str:
        host = f"[{self.host}]" if ":" in self.host else self.host
        port = "" if _DEFAULT_PORTS.get(self.scheme) == self.port else f":{self.port}"
        return f"{self.scheme}://{host}{port}"


def _origin_of(url: str) -> Optional[_Origin]:
    """The (scheme, host, port) origin of an absolute HTTP(S) URL, or ``None``."""
    try:
        parts = urlsplit(url)
        scheme = parts.scheme.lower()
        if scheme not in _DEFAULT_PORTS or not parts.hostname:
            return None
        port = parts.port if parts.port is not None else _DEFAULT_PORTS[scheme]
    except ValueError:
        return None
    return _Origin(scheme, parts.hostname.lower(), port)


# WHATWG percent-encode sets for http(s) paths and queries (besides C0 controls and non-ASCII).
_PATH_ENCODE = frozenset(' "#<>?`{}')
_QUERY_ENCODE = frozenset(" \"#<>'")


def _percent_encode(value: str, extra: FrozenSet[str]) -> str:
    out: List[str] = []
    for char in value:
        if char in extra or ord(char) <= 0x20 or ord(char) >= 0x7F:
            out.append("".join(f"%{byte:02X}" for byte in char.encode("utf-8")))
        else:
            out.append(char)
    return "".join(out)


def _normalize_absolute(url: str) -> str:
    """Lowercases scheme and host, drops default ports and adds an empty path, like WHATWG ``URL.href``."""
    parts = urlsplit(url)
    origin = _origin_of(url)
    if origin is None:
        return url
    userinfo = parts.netloc.rpartition("@")[0]
    authority = str(origin)[len(origin.scheme) + 3 :]
    netloc = f"{userinfo}@{authority}" if userinfo else authority
    path = _percent_encode(parts.path or "/", _PATH_ENCODE)
    result = f"{origin.scheme}://{netloc}{path}"
    if parts.query or url.split("#", 1)[0].endswith("?"):
        result += f"?{_percent_encode(parts.query, _QUERY_ENCODE)}"
    if parts.fragment or "#" in url:
        result += f"#{parts.fragment}"
    return result


def _clean_url_input(url: str) -> str:
    # WHATWG URL parsing strips leading/trailing C0 controls and spaces, removes tabs and newlines,
    # and treats "\" like "/" in the scheme, authority and path of http(s) and relative URLs.
    cleaned = url.strip("".join(chr(c) for c in range(0x21)))
    cleaned = re.sub(r"[\t\n\r]", "", cleaned)
    scheme = re.match(r"([A-Za-z][A-Za-z0-9+.-]*):", cleaned)
    if scheme is None or scheme.group(1).lower() in _DEFAULT_PORTS:
        head, sep, tail = _split_head(cleaned)
        cleaned = head.replace("\\", "/") + sep + tail
    return cleaned


def _split_head(url: str) -> Tuple[str, str, str]:
    match = re.search(r"[?#]", url)
    if match is None:
        return url, "", ""
    return url[: match.start()], match.group(0), url[match.end() :]


def normalize_base_url(value: Any) -> Tuple[str, str]:
    """Validates ``base_url`` and returns ``(base_url, origin)``."""
    message = "base_url must be an HTTP(S) URL without credentials, query or fragment."
    if not isinstance(value, str) or "?" in value or "#" in value:
        raise invalid_argument(message)
    try:
        parts = urlsplit(value.strip())
    except ValueError:
        raise invalid_argument(message) from None
    origin = _origin_of(value.strip())
    if origin is None or "@" in parts.netloc or parts.query or parts.fragment:
        raise invalid_argument(message)
    path = parts.path or "/"
    base_url = f"{origin}{path}"
    if base_url.endswith("/"):
        base_url = base_url[:-1]
    return base_url, str(origin)


# --------------------------------------------------------------------------- Validation


def check_api_key(value: Any) -> str:
    if not isinstance(value, str) or not _API_KEY.fullmatch(value):
        raise invalid_argument("api_key must be a NullDull workspace API key (nd_pub_... or nd_sec_...).")
    return value


def check_workspace_id(value: Any) -> Optional[str]:
    if value is None:
        return None
    if not isinstance(value, str) or not _WORKSPACE_ID.fullmatch(value):
        raise invalid_argument("workspace_id must be 1-128 letters, numbers, hyphens or underscores.")
    return value


def check_timeout(value: Any) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        raise invalid_argument("timeout must be None, zero or a positive number of seconds.")
    return float(value) if value > 0 else None


def check_max_retries(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise invalid_argument("max_retries must be a whole number, zero or more.")
    return value


def _grid_key(value: Any, name: str) -> str:
    if not isinstance(value, str) or len(value) > 96 or not _GRID_KEY.fullmatch(value):
        raise invalid_argument(f"{name} must be 1-96 lowercase letters, numbers and single hyphens.")
    return value


def _locale(value: Any) -> str:
    if value is None:
        value = "en"
    if not isinstance(value, str) or len(value) > 35 or not _LOCALE.fullmatch(value):
        raise invalid_argument("locale must be a lowercase language tag, such as en or pt-br.")
    return value


def _id(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise invalid_argument(f"{name} must be a non-empty string.")
    return segment(value)


def _folder(value: Any) -> Optional[str]:
    """``UNSET`` sends nothing; ``None`` (or ``"root"``) sends ``root``; a string is sent as given."""
    if value is UNSET:
        return None
    if value is None:
        return "root"
    if not isinstance(value, str) or not value:
        raise invalid_argument("Folder filters must be a non-empty string, or None for the location root.")
    return value


def _tags(value: Any) -> Optional[List[str]]:
    if value is None:
        return None
    items = [value] if isinstance(value, str) else list(value)
    return items or None


def _joined(value: Any, name: str) -> Optional[str]:
    if value is None:
        return None
    items = [value] if isinstance(value, str) else value
    if not isinstance(items, (list, tuple)) or any(not isinstance(i, str) or not i or "," in i for i in items):
        raise invalid_argument(f"{name} must be a list of non-empty strings without commas.")
    return ",".join(items) if items else None


# --------------------------------------------------------------------------- Calls


@dataclass(frozen=True)
class Call:
    """One SDK request: a GET of ``url``, plus how to treat the response."""

    url: str
    download: bool = False
    authorize: bool = True
    transform: Optional[Callable[[Any], Any]] = None

    @property
    def accept(self) -> str:
        return "*/*" if self.download else "application/json"


@dataclass(frozen=True)
class Config:
    api_key: str
    base_url: str
    origin: str
    workspace_id: Optional[str]
    timeout: Optional[float]
    max_retries: int
    user_agent: str

    @property
    def key_kind(self) -> str:
        return "public" if self.api_key.startswith("nd_pub_") else "private"

    @property
    def headers(self) -> Dict[str, str]:
        return {"Authorization": f"Bearer {self.api_key}", "User-Agent": self.user_agent}


def make_config(
    api_key: Any,
    base_url: Any,
    workspace_id: Any,
    timeout: Any,
    max_retries: Any,
    user_agent: Optional[str],
) -> Config:
    key = check_api_key(api_key)
    workspace = check_workspace_id(workspace_id)
    seconds = check_timeout(timeout)
    retries = check_max_retries(max_retries)
    if user_agent is not None and not isinstance(user_agent, str):
        raise invalid_argument("user_agent must be a string.")
    url, origin = normalize_base_url(DEFAULT_BASE_URL if base_url is None else base_url)
    agent = f"nulldull-sdk-python/{__version__}" + (f" {user_agent}" if user_agent else "")
    return Config(key, url, origin, workspace, seconds, retries, agent)


class Builder:
    """Builds :class:`Call` objects for every SDK method. Shared by the sync and async clients."""

    def __init__(self, config: Config) -> None:
        self.config = config
        self._origin = _origin_of(config.origin)
        self._public_key = config.api_key if config.key_kind == "public" else None

    # ---------------------------------------------------------------- Grid

    def asset_url(self, url: Any) -> str:
        if not isinstance(url, str):
            raise invalid_argument("Provide a valid asset URL.")
        try:
            resolved = _normalize_absolute(urljoin(self.config.origin + "/", _clean_url_input(url)))
        except ValueError:
            raise invalid_argument("Provide a valid asset URL.") from None
        if self._public_key and self._same_origin(resolved):
            head, hash_sign, fragment = resolved.partition("#")
            base, _question, query = head.partition("?")
            names = {name for name, _ in parse_qsl(query, keep_blank_values=True)}
            if "key" not in names:
                pair = f"key={encode_component(self._public_key)}"
                query = f"{query}&{pair}" if query else pair
                resolved = f"{base}?{query}{hash_sign}{fragment}"
        return resolved

    def _same_origin(self, url: str) -> bool:
        return self._origin is not None and _origin_of(url) == self._origin

    def _cover(self, item: Any) -> Any:
        if not isinstance(item, dict):
            return item
        cover = item.get("cover")
        if not cover or not isinstance(cover, dict) or not isinstance(cover.get("url"), str):
            return item
        return {**item, "cover": {**cover, "url": self.asset_url(cover["url"])}}

    def _page_list(self, data: Any) -> Any:
        if not isinstance(data, dict) or not isinstance(data.get("items"), list):
            return data
        return {**data, "items": [self._cover(item) for item in data["items"]]}

    def _page(self, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        assets = data.get("assets") or []
        return {
            **self._cover(data),
            "assets": [
                {**asset, "url": self.asset_url(asset["url"])}
                if isinstance(asset, dict) and isinstance(asset.get("url"), str)
                else asset
                for asset in assets
            ],
        }

    def grid_list_pages(
        self,
        pool: Any,
        locale: Any = None,
        q: Any = None,
        folder_id: Any = None,
        limit: Any = None,
        after: Any = None,
    ) -> Call:
        path = f"/api/grid/v1/pools/{segment(_grid_key(pool, 'pool'))}/pages"
        if limit is not None and (isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 50):
            raise invalid_argument("limit must be a whole number from 1 to 50.")
        if folder_id is not None and (not isinstance(folder_id, str) or not folder_id):
            raise invalid_argument("folder_id must be a non-empty string.")
        query: Dict[str, QueryValue] = {
            "locale": _locale(locale),
            "q": q if q else None,
            "folderId": folder_id,
            "limit": limit,
            "after": after if after else None,
        }
        return Call(self.config.base_url + path + query_string(query), transform=self._page_list)

    def grid_get_page(self, pool: Any, slug: Any, locale: Any = None) -> Call:
        path = f"/api/grid/v1/pools/{segment(_grid_key(pool, 'pool'))}/pages/{segment(_grid_key(slug, 'slug'))}"
        return Call(self.config.base_url + path + query_string({"locale": _locale(locale)}), transform=self._page)

    def grid_download_asset(self, target: Any) -> Call:
        raw = target if isinstance(target, str) else _url_of(target)
        if not isinstance(raw, str) or not raw:
            raise invalid_argument("Provide an asset URL or an object with a url.")
        url = self.asset_url(raw)
        return Call(url, download=True, authorize=self._same_origin(url))

    # ---------------------------------------------------------------- Memory and Locale

    def _root(self) -> str:
        if self.config.key_kind == "public":
            raise client_error(
                "PRIVATE_KEY_REQUIRED", "Memory and Locale need a private key (nd_sec_...) with the matching scope."
            )
        if not self.config.workspace_id:
            raise client_error(
                "WORKSPACE_REQUIRED", "Memory and Locale need workspace_id: a key cannot look up its own workspace."
            )
        return f"{self.config.base_url}/api/platform/workspaces/{segment(self.config.workspace_id)}"

    def _platform(self, path: str, query: Optional[Query] = None, download: bool = False) -> Call:
        return Call(self._root() + path + query_string(query), download=download)

    def memory_list_scopes(self, after: Any = None) -> Call:
        return self._platform("/scopes", {"after": after})

    def memory_list_folders(self, scope_id: Any = None, parent_id: Any = UNSET, after: Any = None) -> Call:
        return self._platform("/folders", {"scopeId": scope_id, "parentId": _folder(parent_id), "after": after})

    def memory_get_folder(self, folder_id: Any) -> Call:
        return self._platform(f"/folders/{_id(folder_id, 'folder_id')}")

    def memory_list_documents(
        self,
        scope_id: Any = None,
        folder_id: Any = UNSET,
        tags: Any = None,
        kind: Any = None,
        lifecycle: Any = None,
        after: Any = None,
    ) -> Call:
        query = {
            "scopeId": scope_id,
            "folderId": _folder(folder_id),
            "tag": _tags(tags),
            "kind": kind,
            "lifecycle": lifecycle,
            "after": after,
        }
        return self._platform("/documents", query)

    def memory_get_document(self, document_id: Any) -> Call:
        return self._platform(f"/documents/{_id(document_id, 'document_id')}")

    def memory_resolve_link(self, document_id: Any, href: Any) -> Call:
        path = f"/documents/{_id(document_id, 'document_id')}/resolve-link"
        if not isinstance(href, str):
            raise invalid_argument("href must be a string.")
        return self._platform(path, {"href": href})

    def memory_search(
        self,
        q: Any,
        scope_id: Any = None,
        tags: Any = None,
        kind: Any = None,
        lifecycle: Any = None,
        after: Any = None,
    ) -> Call:
        if not isinstance(q, str):
            raise invalid_argument("q must be a string.")
        query = {"q": q, "scopeId": scope_id, "tag": _tags(tags), "kind": kind, "lifecycle": lifecycle, "after": after}
        return self._platform("/search", query)

    def memory_list_tags(self, scope_id: Any = None, q: Any = None, after: Any = None) -> Call:
        return self._platform("/tags", {"scopeId": scope_id, "q": q, "after": after})

    def memory_list_assets(
        self,
        scope_id: Any = None,
        folder_id: Any = UNSET,
        q: Any = None,
        tags: Any = None,
        after: Any = None,
    ) -> Call:
        query = {"scopeId": scope_id, "folderId": _folder(folder_id), "q": q, "tag": _tags(tags), "after": after}
        return self._platform("/assets", query)

    def memory_get_asset(self, asset_id: Any, revision_id: Any = None) -> Call:
        return self._platform(f"/assets/{_id(asset_id, 'asset_id')}", {"revisionId": revision_id})

    def memory_list_asset_versions(self, asset_id: Any, after: Any = None) -> Call:
        return self._platform(f"/assets/{_id(asset_id, 'asset_id')}/versions", {"after": after})

    def memory_download_asset(
        self, asset_id: Any, revision_id: Any = None, preview: Any = False, width: Any = None
    ) -> Call:
        if width is not None and (isinstance(width, bool) or not isinstance(width, int) or width < 1):
            raise invalid_argument("width must be a positive whole number of pixels.")
        path = f"/assets/{_id(asset_id, 'asset_id')}/download"
        # Never send submissionId: keys are refused when it is present.
        query = {"revisionId": revision_id, "preview": "true" if preview or width is not None else None, "w": width}
        return self._platform(path, query, download=True)

    def locale_list_formats(self) -> Call:
        return self._platform("/locale/formats")

    def locale_export(
        self,
        scope_id: Any,
        format: Any = None,
        languages: Any = None,
        status: Any = None,
        basename: Any = None,
    ) -> Call:
        if not isinstance(scope_id, str) or not scope_id:
            raise invalid_argument("scope_id must be a non-empty string.")
        # Never send the legacy single `language` parameter: it changes the response shape.
        query = {
            "scopeId": scope_id,
            "format": "json" if format is None else format,
            "languages": _joined(languages, "languages"),
            "status": _joined(status, "status"),
            "basename": basename,
        }
        return self._platform("/locale/export", query)


def _url_of(target: Any) -> Any:
    if isinstance(target, Mapping):
        return target.get("url")
    return getattr(target, "url", None)


def check_page(page: Any) -> Tuple[List[Any], Optional[str]]:
    """Validates one page during iteration and returns ``(items, next_cursor)``."""
    if not isinstance(page, dict) or not isinstance(page.get("items"), list):
        raise client_error("INVALID_RESPONSE", "NullDull returned a page without an items list.")
    cursor = page.get("nextCursor")
    if cursor is not None and not isinstance(cursor, str):
        raise client_error("INVALID_RESPONSE", "NullDull returned a page with an invalid nextCursor.")
    return page["items"], cursor


def repeated_cursor() -> NullDullError:
    return client_error("INVALID_RESPONSE", "Pagination did not advance: the API returned the same cursor again.")
