"""Optional live tests against a real NullDull API. Skipped unless the variables are set:

    NULLDULL_PUBLIC_KEY + NULLDULL_GRID_POOL         Grid delivery
    NULLDULL_PRIVATE_KEY + NULLDULL_WORKSPACE_ID     Memory and Locale
    NULLDULL_LOCALE_SCOPE_ID (optional)              Locale export location (default: workspace root)
    NULLDULL_BASE_URL (optional)                     Default https://nulldull.com

Never print key values.
"""

from __future__ import annotations

import asyncio
import os
from typing import Any, Callable, Optional, TypeVar

import pytest

from nulldull import AsyncNullDull, NullDull, NullDullError

T = TypeVar("T")
env = os.environ
BASE_URL = env.get("NULLDULL_BASE_URL") or None
GRID = bool(env.get("NULLDULL_PUBLIC_KEY") and env.get("NULLDULL_GRID_POOL"))
PLATFORM = bool(env.get("NULLDULL_PRIVATE_KEY") and env.get("NULLDULL_WORKSPACE_ID"))

grid_only = pytest.mark.skipif(not GRID, reason="set NULLDULL_PUBLIC_KEY and NULLDULL_GRID_POOL")
platform_only = pytest.mark.skipif(not PLATFORM, reason="set NULLDULL_PRIVATE_KEY and NULLDULL_WORKSPACE_ID")


def public_client() -> NullDull:
    return NullDull(env["NULLDULL_PUBLIC_KEY"], base_url=BASE_URL)


def private_client() -> NullDull:
    return NullDull(env["NULLDULL_PRIVATE_KEY"], workspace_id=env["NULLDULL_WORKSPACE_ID"], base_url=BASE_URL)


@grid_only
def test_grid_lists_iterates_and_reads_published_pages() -> None:
    pool = env["NULLDULL_GRID_POOL"]
    with public_client() as client:
        listed = client.grid.list_pages(pool, limit=2)
        assert listed["pool"]["key"] == pool
        assert isinstance(listed["items"], list)
        for count, summary in enumerate(client.grid.iterate_pages(pool, limit=2), 1):
            assert isinstance(summary["slug"], str)
            if count >= 5:
                break
        if not listed["items"]:
            return
        first = listed["items"][0]
        page = client.grid.get_page(pool, first["slug"], locale=first["locale"])
        assert page["id"] == first["id"]
        assert isinstance(page["document"]["nodes"], list)
        origin = (BASE_URL or "https://nulldull.com").rstrip("/")
        for asset in page["assets"]:
            assert asset["url"].startswith("http")
            if asset["url"].startswith(origin):
                assert "key=" in asset["url"]
        covered = next((s for s in client.grid.iterate_pages(pool) if s.get("cover")), None)
        target: Any = covered["cover"] if covered else (page["assets"][0] if page["assets"] else None)
        if target is not None:
            download = client.grid.download_asset(target)
            assert download.size == len(download.bytes) > 0
            assert download.content_type


@grid_only
def test_grid_async_client() -> None:
    pool = env["NULLDULL_GRID_POOL"]

    async def go() -> int:
        async with AsyncNullDull(env["NULLDULL_PUBLIC_KEY"], base_url=BASE_URL) as client:
            listed = await client.grid.list_pages(pool, limit=1)
            assert listed["pool"]["key"] == pool
            count = 0
            async for _ in client.grid.iterate_pages(pool, limit=2):
                count += 1
                if count >= 3:
                    break
            return count

    assert asyncio.run(go()) >= 0


@grid_only
def test_grid_raises_not_found_for_a_missing_page() -> None:
    with public_client() as client, pytest.raises(NullDullError) as info:
        client.grid.get_page(env["NULLDULL_GRID_POOL"], "nulldull-sdk-live-test-missing-page")
    assert (info.value.status, info.value.code) == (404, "NOT_FOUND")
    assert info.value.request_id


@grid_only
def test_grid_refuses_the_platform_api_for_a_public_key() -> None:
    client = NullDull(env["NULLDULL_PUBLIC_KEY"], base_url=BASE_URL, workspace_id="w")
    with pytest.raises(NullDullError) as info:
        client.memory.list_scopes()
    assert info.value.code == "PRIVATE_KEY_REQUIRED"


def tolerate_forbidden(call: Callable[[], T]) -> Optional[T]:
    try:
        return call()
    except NullDullError as error:
        # A key without memory:read or locale:read gets 403; that is a configuration, not an SDK, failure.
        if error.code == "FORBIDDEN":
            return None
        raise


@platform_only
def test_memory_lists_scopes_documents_and_tags() -> None:
    with private_client() as client:
        scopes = tolerate_forbidden(client.memory.list_scopes)
        if scopes is None:
            pytest.skip("key lacks memory:read")
        assert any(scope["id"] == env["NULLDULL_WORKSPACE_ID"] for scope in scopes["items"])
        documents = client.memory.list_documents()
        assert isinstance(documents["items"], list)
        if documents["items"]:
            first: Any = documents["items"][0]
            assert client.memory.get_document(first["id"])["id"] == first["id"]
        assert isinstance(client.memory.list_tags()["items"], list)
        assert isinstance(client.memory.search("the")["items"], list)


@platform_only
def test_locale_lists_formats_and_exports() -> None:
    with private_client() as client:
        formats = tolerate_forbidden(client.locale.list_formats)
        if formats is None:
            pytest.skip("key lacks locale:read")
        assert "json" in [item["id"] for item in formats["items"]]
        scope = env.get("NULLDULL_LOCALE_SCOPE_ID") or env["NULLDULL_WORKSPACE_ID"]
        exported = tolerate_forbidden(lambda: client.locale.export(scope))
        if exported is not None:
            assert exported["format"] == "json"
            assert isinstance(exported["files"], list)
