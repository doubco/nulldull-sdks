"""Test helpers: shared fixtures, a recording httpx.MockTransport and a canonical-method invoker."""

from __future__ import annotations

import base64
import copy
import json
import re
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple, Union

import httpx

from nulldull import AsyncNullDull, NullDull

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"


def fixture(path: str) -> Any:
    return json.loads((FIXTURES / path).read_text(encoding="utf-8"))


MANIFEST: Dict[str, Any] = fixture("manifest.json")
CONFIG: Dict[str, str] = MANIFEST["config"]
PUBLIC_KEY = CONFIG["publicKey"]
PRIVATE_KEY = CONFIG["privateKey"]
WORKSPACE_ID = CONFIG["workspaceId"]
BASE_URL = CONFIG["baseUrl"]

Responder = Union[httpx.Response, Exception, Callable[[httpx.Request], Any]]


def response_from(spec: Dict[str, Any]) -> httpx.Response:
    if "bodyFile" in spec:
        content = (FIXTURES / spec["bodyFile"]).read_bytes()
    elif "bodyBase64" in spec:
        content = base64.b64decode(spec["bodyBase64"])
    else:
        content = spec.get("body", "").encode("utf-8")
    return httpx.Response(spec["status"], headers=spec.get("headers", {}), content=content)


def json_response(body: Any, status: int = 200, headers: Optional[Dict[str, str]] = None) -> httpx.Response:
    return httpx.Response(
        status, headers={"content-type": "application/json", **(headers or {})}, content=json.dumps(body).encode()
    )


class Mock:
    """An httpx.MockTransport that answers with queued responses and records every request."""

    def __init__(self, responses: Optional[List[Responder]] = None) -> None:
        self.queue: List[Responder] = list(responses or [])
        self.requests: List[httpx.Request] = []
        self.transport = httpx.MockTransport(self._handle)

    def _handle(self, request: httpx.Request) -> Any:
        self.requests.append(request)
        if not self.queue:
            raise AssertionError(f"Unexpected request: GET {request.url}")
        nxt = self.queue.pop(0)
        if isinstance(nxt, Exception):
            raise nxt
        if callable(nxt) and not isinstance(nxt, httpx.Response):
            return nxt(request)
        return nxt


def client_for(kind: str, mock: Mock, **extra: Any) -> Tuple[NullDull, List[float]]:
    sleeps: List[float] = []
    options: Dict[str, Any] = {
        "base_url": BASE_URL,
        "workspace_id": WORKSPACE_ID,
        "transport": mock.transport,
        "sleep": lambda seconds: sleeps.append(seconds * 1000),
    }
    options.update(extra)
    return NullDull(PUBLIC_KEY if kind == "public" else PRIVATE_KEY, **options), sleeps


def async_client_for(kind: str, mock: Mock, **extra: Any) -> Tuple[AsyncNullDull, List[float]]:
    sleeps: List[float] = []

    async def sleep(seconds: float) -> None:
        sleeps.append(seconds * 1000)

    options: Dict[str, Any] = {
        "base_url": BASE_URL,
        "workspace_id": WORKSPACE_ID,
        "transport": mock.transport,
        "sleep": sleep,
    }
    options.update(extra)
    return AsyncNullDull(PUBLIC_KEY if kind == "public" else PRIVATE_KEY, **options), sleeps


def multimap(request: httpx.Request) -> Dict[str, List[str]]:
    out: Dict[str, List[str]] = {}
    for name, value in request.url.params.multi_items():
        out.setdefault(name, []).append(value)
    return out


def snake(name: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def split_call(method: str, args: List[Any]) -> Tuple[str, str, List[Any], Dict[str, Any]]:
    """Maps a canonical call (``memory.listDocuments``, camelCase options) to Python names and kwargs."""
    namespace, name = method.split(".")
    args = copy.deepcopy(args)
    kwargs: Dict[str, Any] = {}
    if args and isinstance(args[-1], dict):
        kwargs = {snake(key): value for key, value in args.pop().items()}
    return namespace, snake(name), args, kwargs


def invoke(client: NullDull, method: str, args: List[Any]) -> Any:
    namespace, name, positional, kwargs = split_call(method, args)
    result = getattr(getattr(client, namespace), name)(*positional, **kwargs)
    return list(result) if name.startswith("iterate_") else result


async def invoke_async(client: AsyncNullDull, method: str, args: List[Any]) -> Any:
    namespace, name, positional, kwargs = split_call(method, args)
    target = getattr(getattr(client, namespace), name)
    if name.startswith("iterate_"):
        return [item async for item in target(*positional, **kwargs)]
    return await target(*positional, **kwargs)


def _key(part: str) -> Union[int, str]:
    return int(part) if part.isdigit() else part


def at(value: Any, path: str) -> Any:
    for part in path.split("."):
        if value is None:
            return None
        try:
            value = value[_key(part)]
        except (KeyError, IndexError, TypeError):
            return None
    return value


def without(value: Any, paths: Optional[List[str]] = None) -> Any:
    out = copy.deepcopy(value)
    for path in paths or []:
        parts = path.split(".")
        parent = at(out, ".".join(parts[:-1])) if len(parts) > 1 else out
        if isinstance(parent, dict):
            parent.pop(parts[-1], None)
        elif isinstance(parent, list):
            parent[int(parts[-1])] = None
    return out
