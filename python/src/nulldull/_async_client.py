"""The asynchronous client."""

from __future__ import annotations

import asyncio
import time
from types import TracebackType
from typing import Any, AsyncIterator, Awaitable, Callable, List, Mapping, Optional, Sequence, Type, Union, cast

import httpx

from ._client import Raw, finish, headers_for, timeout_extension, transport_error
from ._core import (
    DEFAULT_MAX_RETRIES,
    DEFAULT_TIMEOUT,
    MAX_RETRY_AFTER_SECONDS,
    RETRYABLE,
    UNSET,
    Builder,
    Call,
    Config,
    backoff,
    check_page,
    error_from,
    make_config,
    repeated_cursor,
)
from ._errors import NullDullError, invalid_argument
from .types import (
    Asset,
    AssetPage,
    AssetVersion,
    AssetVersionPage,
    Document,
    DocumentPage,
    DocumentSummary,
    Download,
    Folder,
    FolderList,
    FolderSummary,
    GridPage,
    GridPageList,
    GridPageSummary,
    LinkResolution,
    LocaleExport,
    LocaleFormatList,
    Scope,
    ScopePage,
    SearchPage,
    SearchResult,
    TagCount,
    TagPage,
)

__all__ = ["AsyncGrid", "AsyncLocale", "AsyncMemory", "AsyncNullDull"]

Sleep = Callable[[float], Awaitable[None]]


class _AsyncTransport:
    def __init__(
        self,
        config: Config,
        transport: Optional[httpx.AsyncBaseTransport],
        http_client: Optional[httpx.AsyncClient],
        sleep: Optional[Sleep],
    ) -> None:
        self.config = config
        self._owns_client = http_client is None
        self.client = http_client if http_client is not None else httpx.AsyncClient(transport=transport)
        self._sleep: Sleep = sleep if sleep is not None else asyncio.sleep

    async def close(self) -> None:
        if self._owns_client:
            await self.client.aclose()

    async def run(self, call: Call) -> Any:
        return finish(call, await self._send(call))

    async def _send(self, call: Call) -> Raw:
        headers = headers_for(self.config, call)
        retry = 0
        while True:
            try:
                status, response_headers, data = await self._attempt(call.url, headers)
            except NullDullError as failure:
                if failure.code == "NETWORK_ERROR" and retry < self.config.max_retries:
                    retry += 1
                    await self._sleep(backoff(retry))
                    continue
                raise
            if 200 <= status < 300:
                return status, response_headers, data
            error = error_from(status, response_headers, data)
            # A paused allowance lasts until the month renews or an upgrade: never retried.
            if status not in RETRYABLE or retry >= self.config.max_retries or error.public_requests_paused:
                raise error
            if error.retry_after is not None and error.retry_after > MAX_RETRY_AFTER_SECONDS:
                raise error
            retry += 1
            await self._sleep(float(error.retry_after) if error.retry_after is not None else backoff(retry))

    async def _attempt(self, url: str, headers: Mapping[str, str]) -> Raw:
        """One attempt: send and read the whole body within the timeout. Redirects are not followed."""
        timeout = self.config.timeout
        request = httpx.Request("GET", url, headers=headers, extensions={"timeout": timeout_extension(timeout)})
        deadline = time.monotonic() + timeout if timeout else None
        try:
            response = await self.client.send(request, stream=True, follow_redirects=False, auth=None)
            try:
                chunks: List[bytes] = []
                async for chunk in response.aiter_bytes():
                    chunks.append(chunk)
                    if deadline is not None and time.monotonic() > deadline:
                        raise httpx.ReadTimeout("The response body took too long.", request=request)
                if deadline is not None and time.monotonic() > deadline:
                    raise httpx.ReadTimeout("The response took too long.", request=request)
            finally:
                await response.aclose()
        except httpx.TransportError as error:
            raise transport_error(error, timeout) from error
        return response.status_code, response.headers, b"".join(chunks)


async def _paginate(load: Callable[[Optional[str]], Awaitable[Any]], start: Optional[str]) -> AsyncIterator[Any]:
    """Yields items across pages, following ``nextCursor`` until it is ``None`` (SPEC.md section 7)."""
    after = start
    while True:
        items, cursor = check_page(await load(after))
        for item in items:
            yield item
        if cursor is None:
            return
        if cursor == after:
            raise repeated_cursor()
        after = cursor


class AsyncGrid:
    """Published Grid content (``grid:published``). Works with public and private keys."""

    def __init__(self, builder: Builder, transport: _AsyncTransport) -> None:
        self._b = builder
        self._t = transport

    async def list_pages(
        self,
        pool: str,
        *,
        locale: Optional[str] = None,
        q: Optional[str] = None,
        folder_id: Optional[str] = None,
        limit: Optional[int] = None,
        after: Optional[str] = None,
    ) -> GridPageList:
        """One page of a pool's published pages, newest first. ``locale`` defaults to ``en``."""
        return cast(GridPageList, await self._t.run(self._b.grid_list_pages(pool, locale, q, folder_id, limit, after)))

    def iterate_pages(
        self,
        pool: str,
        *,
        locale: Optional[str] = None,
        q: Optional[str] = None,
        folder_id: Optional[str] = None,
        limit: Optional[int] = None,
        after: Optional[str] = None,
    ) -> AsyncIterator[GridPageSummary]:
        """Every published page across all result pages. Empty pages with a cursor are followed."""
        return _paginate(
            lambda cursor: self.list_pages(pool, locale=locale, q=q, folder_id=folder_id, limit=limit, after=cursor),
            after,
        )

    async def get_page(self, pool: str, slug: str, *, locale: Optional[str] = None) -> GridPage:
        """A published page with its document and version-pinned asset manifest."""
        return cast(GridPage, await self._t.run(self._b.grid_get_page(pool, slug, locale)))

    def asset_url(self, url: str) -> str:
        """Resolves an asset or cover URL against the API origin.

        For a public key and a URL on the API's own origin, adds ``key`` so images, fonts and media can
        load without headers. Never adds a private key, and never adds a key to another origin.
        """
        return self._b.asset_url(url)

    async def download_asset(self, target: Union[str, Mapping[str, Any], Any]) -> Download:
        """Downloads an asset or cover (a URL, or anything with a ``url``). Sends the key only to the API origin."""
        return cast(Download, await self._t.run(self._b.grid_download_asset(target)))


class AsyncMemory:
    """Read-only Memory (``memory:read``). Needs a private key and ``workspace_id``.

    Folder filters (``folder_id``, ``parent_id``): leave them out for no filter, pass ``None`` (or
    ``"root"``) for the location root, or pass a folder ID.
    """

    def __init__(self, builder: Builder, transport: _AsyncTransport) -> None:
        self._b = builder
        self._t = transport

    async def list_scopes(self, *, after: Optional[str] = None) -> ScopePage:
        """Locations the key's member can see (workspace root, products, projects)."""
        return cast(ScopePage, await self._t.run(self._b.memory_list_scopes(after)))

    def iterate_scopes(self, *, after: Optional[str] = None) -> AsyncIterator[Scope]:
        return _paginate(lambda cursor: self.list_scopes(after=cursor), after)

    async def list_folders(
        self, *, scope_id: Optional[str] = None, parent_id: Optional[str] = UNSET, after: Optional[str] = None
    ) -> FolderList:
        """Readable folders, optionally in one location or under one parent (``None`` = top level)."""
        return cast(FolderList, await self._t.run(self._b.memory_list_folders(scope_id, parent_id, after)))

    def iterate_folders(
        self, *, scope_id: Optional[str] = None, parent_id: Optional[str] = UNSET, after: Optional[str] = None
    ) -> AsyncIterator[FolderSummary]:
        return _paginate(lambda cursor: self.list_folders(scope_id=scope_id, parent_id=parent_id, after=cursor), after)

    async def get_folder(self, folder_id: str) -> Folder:
        """A folder with its ancestors and effective placement."""
        return cast(Folder, await self._t.run(self._b.memory_get_folder(folder_id)))

    async def list_documents(
        self,
        *,
        scope_id: Optional[str] = None,
        folder_id: Optional[str] = UNSET,
        tags: Optional[Sequence[str]] = None,
        kind: Optional[str] = None,
        lifecycle: Optional[str] = None,
        after: Optional[str] = None,
    ) -> DocumentPage:
        """Readable documents (Markdown files) without their content. Every listed tag must match."""
        call = self._b.memory_list_documents(scope_id, folder_id, tags, kind, lifecycle, after)
        return cast(DocumentPage, await self._t.run(call))

    def iterate_documents(
        self,
        *,
        scope_id: Optional[str] = None,
        folder_id: Optional[str] = UNSET,
        tags: Optional[Sequence[str]] = None,
        kind: Optional[str] = None,
        lifecycle: Optional[str] = None,
        after: Optional[str] = None,
    ) -> AsyncIterator[DocumentSummary]:
        return _paginate(
            lambda cursor: self.list_documents(
                scope_id=scope_id, folder_id=folder_id, tags=tags, kind=kind, lifecycle=lifecycle, after=cursor
            ),
            after,
        )

    async def get_document(self, document_id: str) -> Document:
        """A document with its saved Markdown ``content``."""
        return cast(Document, await self._t.run(self._b.memory_get_document(document_id)))

    async def resolve_link(self, document_id: str, href: str) -> LinkResolution:
        """Resolves a relative Markdown link inside a document to another readable document."""
        return cast(LinkResolution, await self._t.run(self._b.memory_resolve_link(document_id, href)))

    async def search(
        self,
        q: str,
        *,
        scope_id: Optional[str] = None,
        tags: Optional[Sequence[str]] = None,
        kind: Optional[str] = None,
        lifecycle: Optional[str] = None,
        after: Optional[str] = None,
    ) -> SearchPage:
        """Literal, case-insensitive search (2-160 characters) over names, content and tags."""
        return cast(SearchPage, await self._t.run(self._b.memory_search(q, scope_id, tags, kind, lifecycle, after)))

    def iterate_search(
        self,
        q: str,
        *,
        scope_id: Optional[str] = None,
        tags: Optional[Sequence[str]] = None,
        kind: Optional[str] = None,
        lifecycle: Optional[str] = None,
        after: Optional[str] = None,
    ) -> AsyncIterator[SearchResult]:
        return _paginate(
            lambda cursor: self.search(q, scope_id=scope_id, tags=tags, kind=kind, lifecycle=lifecycle, after=cursor),
            after,
        )

    async def list_tags(
        self, *, scope_id: Optional[str] = None, q: Optional[str] = None, after: Optional[str] = None
    ) -> TagPage:
        """Tags on readable documents with their counts, most used first."""
        return cast(TagPage, await self._t.run(self._b.memory_list_tags(scope_id, q, after)))

    def iterate_tags(
        self, *, scope_id: Optional[str] = None, q: Optional[str] = None, after: Optional[str] = None
    ) -> AsyncIterator[TagCount]:
        return _paginate(lambda cursor: self.list_tags(scope_id=scope_id, q=q, after=cursor), after)

    async def list_assets(
        self,
        *,
        scope_id: Optional[str] = None,
        folder_id: Optional[str] = UNSET,
        q: Optional[str] = None,
        tags: Optional[Sequence[str]] = None,
        after: Optional[str] = None,
    ) -> AssetPage:
        """Readable Memory assets with metadata."""
        return cast(AssetPage, await self._t.run(self._b.memory_list_assets(scope_id, folder_id, q, tags, after)))

    def iterate_assets(
        self,
        *,
        scope_id: Optional[str] = None,
        folder_id: Optional[str] = UNSET,
        q: Optional[str] = None,
        tags: Optional[Sequence[str]] = None,
        after: Optional[str] = None,
    ) -> AsyncIterator[Asset]:
        return _paginate(
            lambda cursor: self.list_assets(scope_id=scope_id, folder_id=folder_id, q=q, tags=tags, after=cursor),
            after,
        )

    async def get_asset(self, asset_id: str, *, revision_id: Optional[str] = None) -> Asset:
        """An asset's metadata and current object (filename, media type, SHA-256)."""
        return cast(Asset, await self._t.run(self._b.memory_get_asset(asset_id, revision_id)))

    async def list_asset_versions(self, asset_id: str, *, after: Optional[str] = None) -> AssetVersionPage:
        """An asset's immutable versions, newest first."""
        return cast(AssetVersionPage, await self._t.run(self._b.memory_list_asset_versions(asset_id, after)))

    def iterate_asset_versions(self, asset_id: str, *, after: Optional[str] = None) -> AsyncIterator[AssetVersion]:
        return _paginate(lambda cursor: self.list_asset_versions(asset_id, after=cursor), after)

    async def download_asset(
        self,
        asset_id: str,
        *,
        revision_id: Optional[str] = None,
        preview: bool = False,
        width: Optional[int] = None,
    ) -> Download:
        """Downloads an asset's bytes, or a resized WebP preview with ``width`` (implies ``preview``)."""
        return cast(Download, await self._t.run(self._b.memory_download_asset(asset_id, revision_id, preview, width)))


class AsyncLocale:
    """Locale catalog export (``locale:read``). Needs a private key and ``workspace_id``."""

    def __init__(self, builder: Builder, transport: _AsyncTransport) -> None:
        self._b = builder
        self._t = transport

    async def list_formats(self) -> LocaleFormatList:
        """Export formats with their capabilities and file roles."""
        return cast(LocaleFormatList, await self._t.run(self._b.locale_list_formats()))

    async def export(
        self,
        scope_id: str,
        *,
        format: Optional[str] = None,
        languages: Optional[Union[Sequence[str], str]] = None,
        status: Optional[Union[Sequence[str], str]] = None,
        basename: Optional[str] = None,
    ) -> LocaleExport:
        """Exports a location's catalog as text files. ``format`` defaults to ``json``. Never an archive."""
        return cast(
            LocaleExport, await self._t.run(self._b.locale_export(scope_id, format, languages, status, basename))
        )


class AsyncNullDull:
    """The asyncio NullDull client, with the same methods as :class:`NullDull`. Safe to share between tasks.

    >>> async with AsyncNullDull(os.environ["NULLDULL_PUBLIC_KEY"]) as nulldull:
    ...     page = await nulldull.grid.get_page("my-blog", "hello-world")

    Args:
        api_key: A workspace API key: public ``nd_pub_...`` or private ``nd_sec_...``.
        base_url: Default ``https://nulldull.com``.
        workspace_id: Needed for ``memory`` and ``locale``; a key cannot look up its own workspace.
        timeout: Seconds per attempt (default 30). ``0`` or ``None`` disables it.
        max_retries: Retries for 429/502/503/504 and network errors (default 2). ``0`` disables them.
        transport: An ``httpx.AsyncBaseTransport`` (for example ``httpx.MockTransport`` in tests).
        http_client: An ``httpx.AsyncClient`` to send requests with. The SDK does not close it.
        user_agent: Appended to ``nulldull-sdk-python/0.1.0``.
        sleep: Replaces the retry wait (an async function receiving seconds), for tests.
    """

    grid: AsyncGrid
    """Published Grid content."""
    memory: AsyncMemory
    """Read-only Memory."""
    locale: AsyncLocale
    """Locale export."""

    def __init__(
        self,
        api_key: str,
        *,
        base_url: Optional[str] = None,
        workspace_id: Optional[str] = None,
        timeout: Optional[float] = DEFAULT_TIMEOUT,
        max_retries: int = DEFAULT_MAX_RETRIES,
        transport: Optional[httpx.AsyncBaseTransport] = None,
        http_client: Optional[httpx.AsyncClient] = None,
        user_agent: Optional[str] = None,
        sleep: Optional[Sleep] = None,
    ) -> None:
        if transport is not None and http_client is not None:
            raise invalid_argument("Pass either transport or http_client, not both.")
        self._config = make_config(api_key, base_url, workspace_id, timeout, max_retries, user_agent)
        builder = Builder(self._config)
        self._transport = _AsyncTransport(self._config, transport, http_client, sleep)
        self.grid = AsyncGrid(builder, self._transport)
        self.memory = AsyncMemory(builder, self._transport)
        self.locale = AsyncLocale(builder, self._transport)

    @property
    def base_url(self) -> str:
        return self._config.base_url

    @property
    def workspace_id(self) -> Optional[str]:
        return self._config.workspace_id

    @property
    def key_kind(self) -> str:
        """``"public"`` or ``"private"``."""
        return self._config.key_kind

    async def aclose(self) -> None:
        """Closes the HTTP connection pool (unless you passed your own ``http_client``)."""
        await self._transport.close()

    async def __aenter__(self) -> AsyncNullDull:
        return self

    async def __aexit__(
        self,
        exc_type: Optional[Type[BaseException]],
        exc: Optional[BaseException],
        tb: Optional[TracebackType],
    ) -> None:
        await self.aclose()

    def __repr__(self) -> str:
        return (
            f"AsyncNullDull(base_url={self.base_url!r}, key_kind={self.key_kind!r}, workspace_id={self.workspace_id!r})"
        )
