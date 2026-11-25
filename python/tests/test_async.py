"""AsyncNullDull parity: the same behaviours as the sync client, plus asyncio cancellation."""

from __future__ import annotations

import asyncio
from typing import Any, AsyncIterator, Awaitable, Callable, List, TypeVar

import httpx
import pytest

from nulldull import AsyncNullDull, NullDullError
from support import PRIVATE_KEY, PUBLIC_KEY, WORKSPACE_ID, Mock, async_client_for, fixture, json_response

T = TypeVar("T")


def run(factory: Callable[[], Awaitable[T]]) -> T:
    return asyncio.run(factory())  # type: ignore[arg-type]


def failure(factory: Callable[[], Awaitable[Any]]) -> NullDullError:
    with pytest.raises(NullDullError) as info:
        run(factory)
    return info.value


async def collect(iterator: AsyncIterator[T]) -> List[T]:
    return [item async for item in iterator]


def test_sends_headers_and_downloads() -> None:
    mock = Mock([json_response(fixture("memory/scopes.json")), httpx.Response(200, content=b"x")])
    client, _ = async_client_for("private", mock, user_agent="my-app/2.0")

    async def go() -> None:
        async with client:
            await client.memory.list_scopes()
            download = await client.memory.download_asset("asset_1", width=64)
            assert (download.bytes, download.size) == (b"x", 1)

    run(go)
    first, second = mock.requests
    assert first.headers["authorization"] == f"Bearer {PRIVATE_KEY}"
    assert first.headers["accept"] == "application/json"
    assert first.headers["user-agent"] == "nulldull-sdk-python/0.4.0 my-app/2.0"
    assert second.headers["accept"] == "*/*"
    assert second.url.query == b"preview=true&w=64"


def test_preconditions_without_requests() -> None:
    mock = Mock()
    no_workspace = AsyncNullDull(PRIVATE_KEY, transport=mock.transport)
    public, _ = async_client_for("public", mock)
    assert failure(lambda: no_workspace.memory.list_documents()).code == "WORKSPACE_REQUIRED"
    assert failure(lambda: collect(no_workspace.memory.iterate_documents())).code == "WORKSPACE_REQUIRED"
    assert failure(lambda: public.locale.export(WORKSPACE_ID)).code == "PRIVATE_KEY_REQUIRED"
    assert failure(lambda: public.grid.list_pages("Bad_Pool")).code == "INVALID_ARGUMENT"
    assert mock.requests == []


def test_grid_normalizes_urls_and_download_origin() -> None:
    mock = Mock(
        [
            json_response(fixture("grid/page-list.json")),
            json_response(fixture("grid/page.json")),
            httpx.Response(200, content=b"1"),
            httpx.Response(200, content=b"2"),
        ]
    )
    client, _ = async_client_for("public", mock)

    async def go() -> None:
        listed = await client.grid.list_pages("nulldull-blog")
        page = await client.grid.get_page("nulldull-blog", "context-that-survives-the-chat", locale="en")
        cover = listed["items"][0].get("cover")
        assert cover is not None and cover["url"].startswith("https://nulldull.com/")
        assert all(asset["url"].endswith(f"key={PUBLIC_KEY}") for asset in page["assets"])
        assert client.grid.asset_url("https://cdn.example.com/a.png") == "https://cdn.example.com/a.png"
        await client.grid.download_asset(page["assets"][0])
        await client.grid.download_asset("https://cdn.example.com/a.png")

    run(go)
    assert mock.requests[2].headers["authorization"] == f"Bearer {PUBLIC_KEY}"
    assert "authorization" not in mock.requests[3].headers


def test_pagination() -> None:
    mock = Mock(
        [
            json_response({"pool": {}, "items": [], "nextCursor": "c1"}),
            json_response(fixture("grid/page-list-last.json")),
        ]
    )
    client, _ = async_client_for("public", mock)
    items = run(lambda: collect(client.grid.iterate_pages("nulldull-blog", after="c0")))
    assert len(items) == len(fixture("grid/page-list-last.json")["items"])
    assert [r.url.params.get("after") for r in mock.requests] == ["c0", "c1"]


def test_pagination_loop_guard_and_laziness() -> None:
    page = {"items": [{"id": "a"}], "nextCursor": "same"}
    mock = Mock([json_response(page), json_response(page)])
    client, _ = async_client_for("private", mock)
    iterator = client.memory.iterate_scopes()
    assert mock.requests == []
    assert failure(lambda: collect(iterator)).code == "INVALID_RESPONSE"
    assert len(mock.requests) == 2


def test_retries_and_errors() -> None:
    mock = Mock(
        [
            httpx.ConnectError("refused"),
            json_response({"code": "RATE_LIMITED"}, 429, {"retry-after": "3"}),
            json_response({"code": "X"}, 503),
            json_response(fixture("memory/scopes.json")),
        ]
    )
    client, sleeps = async_client_for("private", mock, max_retries=3)
    result = run(lambda: client.memory.list_scopes())
    assert len(result["items"]) == 3
    assert sleeps == [500, 3000, 2000]

    mock = Mock([json_response({"code": "RATE_LIMITED"}, 429, {"retry-after": "60", "cf-ray": "ray-1"})])
    client, sleeps = async_client_for("private", mock)
    error = failure(lambda: client.memory.list_scopes())
    assert (error.code, error.retry_after, error.request_id, sleeps) == ("RATE_LIMITED", 60, "ray-1", [])

    mock = Mock([json_response(fixture("errors/public-requests-paused.json"), 429, {"retry-after": "691200"})])
    client, sleeps = async_client_for("public", mock)
    error = failure(lambda: client.grid.list_pages("nulldull-blog"))
    assert (error.reason, error.renews_at, error.retry_after, error.public_requests_paused, sleeps) == (
        "PUBLIC_REQUESTS_PAUSED",
        "2026-12-01T00:00:00.000Z",
        691200,
        True,
        [],
    )
    assert len(mock.requests) == 1

    mock = Mock([json_response(fixture("errors/public-requests-paused.json"), 429)])
    client, sleeps = async_client_for("public", mock)
    error = failure(lambda: client.grid.list_pages("nulldull-blog"))
    assert (error.public_requests_paused, error.retry_after, sleeps, len(mock.requests)) == (True, None, [], 1)

    mock = Mock([httpx.Response(301, headers={"location": "https://evil.example/"})])
    client, _ = async_client_for("public", mock)
    assert failure(lambda: client.grid.list_pages("nulldull-blog")).code == "REQUEST_FAILED"
    assert len(mock.requests) == 1


def test_timeouts_are_not_retried() -> None:
    mock = Mock([httpx.ReadTimeout("slow"), json_response({})])
    client, sleeps = async_client_for("private", mock)
    error = failure(lambda: client.memory.list_scopes())
    assert (error.code, len(mock.requests), sleeps) == ("TIMEOUT", 1, [])


class _SlowBody(httpx.AsyncByteStream):
    async def __aiter__(self) -> AsyncIterator[bytes]:
        for _ in range(20):
            await asyncio.sleep(0.02)
            yield b"{"


def test_reading_the_body_counts_toward_the_timeout() -> None:
    mock = Mock([lambda request: httpx.Response(200, stream=_SlowBody())])
    client, _ = async_client_for("private", mock, timeout=0.05)
    assert failure(lambda: client.memory.list_scopes()).code == "TIMEOUT"
    assert len(mock.requests) == 1


def test_cancellation_propagates() -> None:
    async def hang(request: httpx.Request) -> httpx.Response:
        await asyncio.sleep(3600)
        raise AssertionError("unreachable")

    mock = Mock([hang])
    client, _ = async_client_for("private", mock)

    async def go() -> None:
        task = asyncio.ensure_future(client.memory.list_scopes())
        await asyncio.sleep(0.01)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task

    run(go)


def test_cancellation_while_waiting_to_retry() -> None:
    mock = Mock([json_response({"code": "SERVICE_UNAVAILABLE"}, 503)])
    client = AsyncNullDull(PRIVATE_KEY, workspace_id=WORKSPACE_ID, transport=mock.transport)

    async def go() -> None:
        with pytest.raises(asyncio.TimeoutError):
            await asyncio.wait_for(client.memory.list_scopes(), 0.05)

    run(go)
    assert len(mock.requests) == 1


def test_caller_http_client_is_not_closed() -> None:
    mock = Mock([json_response(fixture("locale/formats.json"))])

    async def go() -> None:
        async with httpx.AsyncClient(transport=mock.transport) as http_client:
            async with AsyncNullDull(PRIVATE_KEY, workspace_id=WORKSPACE_ID, http_client=http_client) as client:
                formats = await client.locale.list_formats()
                assert formats == fixture("locale/formats.json")
            assert not http_client.is_closed

    run(go)
