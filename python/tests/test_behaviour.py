"""SPEC.md section 11 Conformance list, items 1-14, for the sync client (async parity is in test_async.py)."""

from __future__ import annotations

import pickle
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterator, List

import httpx
import pytest

import nulldull
from nulldull import NullDull, NullDullError
from nulldull._core import parse_filename, parse_retry_after
from support import PRIVATE_KEY, PUBLIC_KEY, WORKSPACE_ID, Mock, client_for, fixture, json_response

if sys.version_info >= (3, 11):
    import tomllib
else:  # pragma: no cover
    tomllib = None


def failure(call: Callable[[], Any]) -> NullDullError:
    with pytest.raises(NullDullError) as info:
        result = call()
        if isinstance(result, Iterator):
            list(result)
    return info.value


def make(**options: Any) -> NullDull:
    options.setdefault("api_key", PUBLIC_KEY)
    options.setdefault("transport", Mock().transport)
    return NullDull(**options)


# --------------------------------------------------------------------------- 1. construction


class TestConstruction:
    @pytest.mark.parametrize(
        "api_key",
        [None, "", "nd_pub_123", f"nd_xyz_{'a' * 64}", f"nd_pub_{'A' * 64}", f"ndm_{'a' * 64}", f"nd_pub_{'a' * 64}\n"],
    )
    def test_rejects_malformed_keys(self, api_key: Any) -> None:
        error = failure(lambda: make(api_key=api_key))
        assert (error.code, error.status) == ("INVALID_ARGUMENT", 0)

    @pytest.mark.parametrize(
        "base_url",
        [
            "ftp://nulldull.com",
            "nulldull.com",
            "https://user:pass@nulldull.com",
            "https://nulldull.com/?x=1",
            "https://nulldull.com/#top",
            "https://nulldull.com?",
            "",
            42,
        ],
    )
    def test_rejects_bad_base_urls(self, base_url: Any) -> None:
        assert failure(lambda: make(base_url=base_url)).code == "INVALID_ARGUMENT"

    @pytest.mark.parametrize(
        "options",
        [
            {"workspace_id": "../etc"},
            {"workspace_id": "a" * 129},
            {"workspace_id": ""},
            {"timeout": -1},
            {"timeout": True},
            {"max_retries": 1.5},
            {"max_retries": -1},
            {"transport": httpx.MockTransport(lambda r: httpx.Response(200)), "http_client": httpx.Client()},
        ],
    )
    def test_rejects_bad_options(self, options: Any) -> None:
        assert failure(lambda: make(**options)).code == "INVALID_ARGUMENT"

    def test_strips_a_trailing_slash_and_keeps_a_path_prefix(self) -> None:
        mock = Mock([json_response(fixture("grid/page-list-last.json")) for _ in range(2)])
        staging = NullDull(PUBLIC_KEY, base_url="https://staging.nulldull.com/", transport=mock.transport)
        assert staging.base_url == "https://staging.nulldull.com"
        staging.grid.list_pages("nulldull-blog")
        NullDull(PUBLIC_KEY, base_url="http://localhost:8787/proxy/", transport=mock.transport).grid.list_pages(
            "nulldull-blog"
        )
        assert (
            str(mock.requests[0].url) == "https://staging.nulldull.com/api/grid/v1/pools/nulldull-blog/pages?locale=en"
        )
        assert (
            str(mock.requests[1].url) == "http://localhost:8787/proxy/api/grid/v1/pools/nulldull-blog/pages?locale=en"
        )

    def test_defaults_and_key_kind(self) -> None:
        client = NullDull(PRIVATE_KEY)
        assert client.base_url == "https://nulldull.com"
        assert client.key_kind == "private"
        assert client.workspace_id is None
        assert PRIVATE_KEY not in repr(client)
        client.close()
        with NullDull(PUBLIC_KEY) as public:
            assert public.key_kind == "public"


# --------------------------------------------------------------------------- 2. headers


class TestHeaders:
    def test_sends_authorization_accept_and_user_agent(self) -> None:
        mock = Mock([json_response(fixture("memory/scopes.json")), httpx.Response(200, content=b"x")])
        client, _ = client_for("private", mock, user_agent="my-app/2.0")
        client.memory.list_scopes()
        client.memory.download_asset("asset_1")
        first, second = mock.requests
        assert first.method == "GET"
        assert first.headers["authorization"] == f"Bearer {PRIVATE_KEY}"
        assert first.headers["accept"] == "application/json"
        assert first.headers["user-agent"] == "nulldull-sdk-python/0.4.0 my-app/2.0"
        assert second.headers["accept"] == "*/*"
        assert second.headers["authorization"] == f"Bearer {PRIVATE_KEY}"
        assert "cookie" not in first.headers

    def test_default_user_agent(self) -> None:
        mock = Mock([json_response(fixture("grid/page-list-last.json"))])
        client, _ = client_for("public", mock)
        client.grid.list_pages("nulldull-blog")
        assert mock.requests[0].headers["user-agent"] == "nulldull-sdk-python/0.4.0"

    def test_sends_no_cookies_and_no_extra_headers(self) -> None:
        set_cookie = json_response(fixture("memory/scopes.json"), headers={"set-cookie": "session=abc; Path=/"})
        mock = Mock([set_cookie, json_response(fixture("memory/scopes.json"))])
        client, _ = client_for("private", mock)
        client.memory.list_scopes()
        client.memory.list_scopes()
        assert "cookie" not in mock.requests[1].headers
        assert set(mock.requests[1].headers.keys()) <= {"host", "accept", "authorization", "user-agent"}

    def test_version_matches_pyproject(self) -> None:
        assert nulldull.__version__ == nulldull.VERSION == "0.4.0"
        if tomllib is not None:
            data = tomllib.loads((Path(__file__).parents[1] / "pyproject.toml").read_text())
            assert data["project"]["version"] == nulldull.__version__


# --------------------------------------------------------------------------- 3. Memory and Locale preconditions


class TestPreconditions:
    def test_needs_workspace_id_without_a_request(self) -> None:
        mock = Mock()
        client = NullDull(PRIVATE_KEY, transport=mock.transport)
        assert failure(lambda: client.memory.list_documents()).code == "WORKSPACE_REQUIRED"
        assert failure(lambda: client.locale.export(WORKSPACE_ID)).code == "WORKSPACE_REQUIRED"
        assert failure(lambda: client.locale.list_formats()).code == "WORKSPACE_REQUIRED"
        iterator = client.memory.iterate_documents()
        assert failure(lambda: next(iterator)).code == "WORKSPACE_REQUIRED"
        assert mock.requests == []

    def test_needs_a_private_key_without_a_request(self) -> None:
        mock = Mock()
        client, _ = client_for("public", mock)
        error = failure(lambda: client.memory.get_document("doc"))
        assert (error.code, error.status) == ("PRIVATE_KEY_REQUIRED", 0)
        assert failure(lambda: client.locale.list_formats()).code == "PRIVATE_KEY_REQUIRED"
        assert failure(lambda: client.memory.iterate_scopes()).code == "PRIVATE_KEY_REQUIRED"
        assert mock.requests == []

    def test_percent_encodes_path_segments_and_rejects_empty_ids(self) -> None:
        mock = Mock([json_response({})])
        client, _ = client_for("private", mock)
        client.memory.get_document("a/b c")
        assert mock.requests[0].url.raw_path.decode() == f"/api/platform/workspaces/{WORKSPACE_ID}/documents/a%2Fb%20c"
        assert failure(lambda: client.memory.get_document("")).code == "INVALID_ARGUMENT"
        assert failure(lambda: client.memory.get_folder(None)).code == "INVALID_ARGUMENT"  # type: ignore[arg-type]
        assert failure(lambda: client.memory.resolve_link("doc", None)).code == "INVALID_ARGUMENT"  # type: ignore[arg-type]
        assert failure(lambda: client.locale.export("")).code == "INVALID_ARGUMENT"
        assert len(mock.requests) == 1


# --------------------------------------------------------------------------- 4. Grid validation


class TestGridValidation:
    @pytest.mark.parametrize(
        "call",
        [
            lambda g: g.list_pages("Bad_Pool"),
            lambda g: g.list_pages("pool", locale="EN"),
            lambda g: g.list_pages("pool", locale="en_US"),
            lambda g: g.list_pages("pool", limit=0),
            lambda g: g.list_pages("pool", limit=51),
            lambda g: g.list_pages("pool", limit=2.5),
            lambda g: g.list_pages("pool", limit=True),
            lambda g: g.list_pages("pool", folder_id=""),
            lambda g: g.list_pages("pool\n"),
            lambda g: g.get_page("pool", "a--b"),
            lambda g: g.get_page("pool", "x" * 97),
            lambda g: g.get_page("pool", "slug", locale="x" * 36),
            lambda g: g.iterate_pages("Bad_Pool"),
            lambda g: g.download_asset(""),
            lambda g: g.download_asset({"id": "no-url"}),
        ],
    )
    def test_validates_before_any_request(self, call: Callable[[Any], Any]) -> None:
        mock = Mock()
        client, _ = client_for("public", mock)
        assert failure(lambda: call(client.grid)).code == "INVALID_ARGUMENT"
        assert mock.requests == []

    def test_always_sends_locale_and_omits_an_empty_q(self) -> None:
        mock = Mock([json_response(fixture("grid/page-list-last.json")), json_response(fixture("grid/page.json"))])
        client, _ = client_for("public", mock)
        client.grid.list_pages("nulldull-blog", q="", after="")
        client.grid.get_page("nulldull-blog", "hello", locale="pt-br")
        assert mock.requests[0].url.query == b"locale=en"
        assert mock.requests[1].url.query == b"locale=pt-br"

    def test_accepts_96_character_keys(self) -> None:
        mock = Mock([json_response(fixture("grid/page.json"))])
        client, _ = client_for("public", mock)
        client.grid.get_page("a" * 96, "b" * 96)
        assert len(mock.requests) == 1


# --------------------------------------------------------------------------- 5. grid.asset_url


class TestAssetUrl:
    pub = NullDull(PUBLIC_KEY, transport=Mock().transport).grid
    sec = NullDull(PRIVATE_KEY, transport=Mock().transport).grid

    def test_resolves_relative_urls_and_adds_a_public_key_on_the_api_origin(self) -> None:
        assert self.pub.asset_url("/api/grid/v1/pools/p/pages/s/assets/a?locale=en&version=3") == (
            f"https://nulldull.com/api/grid/v1/pools/p/pages/s/assets/a?locale=en&version=3&key={PUBLIC_KEY}"
        )
        assert self.pub.asset_url("https://NULLDULL.com:443/x") == f"https://nulldull.com/x?key={PUBLIC_KEY}"
        assert self.pub.asset_url("x/y") == f"https://nulldull.com/x/y?key={PUBLIC_KEY}"

    def test_keeps_an_existing_key(self) -> None:
        assert self.pub.asset_url("/x?key=nd_pub_existing") == "https://nulldull.com/x?key=nd_pub_existing"

    @pytest.mark.parametrize(
        "url",
        [
            "https://cdn.example.com/a.png",
            "//evil.example/a.png",
            "https://nulldull.com.evil.example/a.png",
            "http://nulldull.com/a.png",
            "https://nulldull.com:8443/a.png",
            "/\\evil.example/a.png",
            "\\\\evil.example/a.png",
            " //evil.example/a.png",
            "https://nulldull.com@evil.example/a.png",
            "data:image/png;base64,AAAA",
        ],
    )
    def test_never_adds_a_key_to_another_origin(self, url: str) -> None:
        assert "key=" not in self.pub.asset_url(url)

    def test_never_adds_a_private_key(self) -> None:
        assert self.sec.asset_url("/api/grid/v1/pools/p/pages/s/assets/a?version=1") == (
            "https://nulldull.com/api/grid/v1/pools/p/pages/s/assets/a?version=1"
        )
        assert PRIVATE_KEY not in self.sec.asset_url("https://nulldull.com/x")

    def test_uses_the_base_url_origin_not_its_path(self) -> None:
        grid = NullDull(PUBLIC_KEY, base_url="https://staging.nulldull.com/proxy", transport=Mock().transport).grid
        assert grid.asset_url("/a") == f"https://staging.nulldull.com/a?key={PUBLIC_KEY}"
        assert "key=" not in grid.asset_url("https://nulldull.com/a")

    def test_rejects_non_strings(self) -> None:
        assert failure(lambda: self.pub.asset_url(None)).code == "INVALID_ARGUMENT"  # type: ignore[arg-type]


# --------------------------------------------------------------------------- 6. grid.download_asset


class TestGridDownload:
    def test_sends_authorization_only_to_the_api_origin(self) -> None:
        def body() -> httpx.Response:
            headers = {"content-type": "image/png", "content-disposition": "inline; filename*=UTF-8''cover.png"}
            return httpx.Response(200, headers=headers, content=b"\x01\x02\x03")

        mock = Mock([body(), body(), body()])
        client, _ = client_for("private", mock)
        page = fixture("grid/page.json")
        own = client.grid.download_asset(page["assets"][0])
        client.grid.download_asset("https://cdn.example.com/cover.png")
        client.grid.download_asset("//nulldull.com.evil.example/cover.png")
        assert (own.content_type, own.filename, own.size, own.bytes) == ("image/png", "cover.png", 3, b"\x01\x02\x03")
        assert mock.requests[0].url.host == "nulldull.com"
        assert mock.requests[0].headers["authorization"] == f"Bearer {PRIVATE_KEY}"
        assert mock.requests[0].headers["accept"] == "*/*"
        assert "authorization" not in mock.requests[1].headers
        assert "authorization" not in mock.requests[2].headers

    def test_public_key_rides_in_the_url_for_same_origin_assets(self) -> None:
        mock = Mock([httpx.Response(200, content=b"x")])
        client, _ = client_for("public", mock)
        client.grid.download_asset({"url": "/api/grid/v1/pools/p/pages/s/assets/a?version=1"})
        assert mock.requests[0].url.params["key"] == PUBLIC_KEY
        assert mock.requests[0].headers["authorization"] == f"Bearer {PUBLIC_KEY}"


# --------------------------------------------------------------------------- 7. URL normalization


def test_normalizes_list_covers_and_page_covers_and_assets_only() -> None:
    mock = Mock([json_response(fixture("grid/page-list.json")), json_response(fixture("grid/page.json"))])
    client, _ = client_for("public", mock)
    listed = client.grid.list_pages("nulldull-blog")
    page = client.grid.get_page("nulldull-blog", "context-that-survives-the-chat")
    cover = listed["items"][0].get("cover")
    assert cover is not None and cover["url"].startswith("https://nulldull.com/api/grid/v1/")
    assert all(asset["url"].startswith("https://nulldull.com/") for asset in page["assets"])
    page_cover = page.get("cover")
    assert page_cover is not None and page_cover["url"].startswith("https://nulldull.com/")
    assert page["document"] == fixture("grid/page.json")["document"]
    assert listed["pool"] == {"key": "nulldull-blog", "name": "The Void"}
    raw = fixture("grid/page.json")
    for field in raw:
        if field not in ("cover", "assets"):
            assert page[field] == raw[field]  # type: ignore[literal-required]


def test_tolerates_unknown_fields_and_enum_values() -> None:
    body = {"items": [{"id": "s", "kind": "galaxy", "brandNew": {"x": 1}}], "nextCursor": None, "extra": True}
    mock = Mock([json_response(body)])
    client, _ = client_for("private", mock)
    assert client.memory.list_scopes() == body


# --------------------------------------------------------------------------- 8. pagination


class TestPagination:
    def test_continues_through_an_empty_page_with_a_cursor(self) -> None:
        mock = Mock(
            [
                json_response({"pool": {}, "items": [], "nextCursor": "c1"}),
                json_response({"pool": {}, "items": [], "nextCursor": "c2"}),
                json_response(fixture("grid/page-list-last.json")),
            ]
        )
        client, _ = client_for("public", mock)
        items = list(client.grid.iterate_pages("nulldull-blog", q="agents"))
        assert len(items) == len(fixture("grid/page-list-last.json")["items"])
        assert [r.url.params.get("after") for r in mock.requests] == [None, "c1", "c2"]
        assert all(r.url.params["q"] == "agents" for r in mock.requests)

    def test_starts_from_after_and_stops_at_a_null_cursor(self) -> None:
        mock = Mock([json_response(fixture("memory/documents-page-2.json"))])
        client, _ = client_for("private", mock)
        items = list(client.memory.iterate_documents(after="cursor-1", scope_id="s"))
        assert len(items) == 1
        assert mock.requests[0].url.params["after"] == "cursor-1"
        assert mock.requests[0].url.params["scopeId"] == "s"

    def test_raises_invalid_response_when_a_cursor_repeats(self) -> None:
        page = {"items": [{"id": "a"}], "nextCursor": "same"}
        mock = Mock([json_response(page), json_response(page)])
        client, _ = client_for("private", mock)
        seen: List[Any] = []
        with pytest.raises(NullDullError) as info:
            for item in client.memory.iterate_scopes():
                seen.append(item)
        assert info.value.code == "INVALID_RESPONSE"
        assert len(seen) == 2

    def test_is_lazy_and_stops_early(self) -> None:
        mock = Mock([json_response(fixture("memory/tags-page-1.json"))])
        client, _ = client_for("private", mock)
        iterator = client.memory.iterate_tags()
        assert mock.requests == []
        for tag in iterator:
            assert tag["tag"] == "maintained"
            break
        assert len(mock.requests) == 1

    def test_every_iterator_follows_cursors(self) -> None:
        def pages() -> List[httpx.Response]:
            return [
                json_response({"items": [{"id": 1}], "nextCursor": "n"}),
                json_response({"items": [{"id": 2}], "nextCursor": None}),
            ]

        mock = Mock()
        client, _ = client_for("private", mock)
        calls: List[Callable[[], Iterator[Any]]] = [
            lambda: client.memory.iterate_scopes(),
            lambda: client.memory.iterate_folders(parent_id=None),
            lambda: client.memory.iterate_documents(tags=["a"]),
            lambda: client.memory.iterate_search("query"),
            lambda: client.memory.iterate_tags(q="r"),
            lambda: client.memory.iterate_assets(folder_id="f"),
            lambda: client.memory.iterate_asset_versions("asset"),
        ]
        for call in calls:
            mock.queue.extend(pages())
            assert [item["id"] for item in call()] == [1, 2]
            assert mock.requests[-1].url.params["after"] == "n"

    def test_rejects_a_page_without_items(self) -> None:
        mock = Mock([json_response({"nextCursor": None})])
        client, _ = client_for("private", mock)
        assert failure(lambda: client.memory.iterate_scopes()).code == "INVALID_RESPONSE"


# --------------------------------------------------------------------------- 9. errors


class TestErrors:
    def test_fills_every_field_from_body_and_headers(self) -> None:
        body = fixture("errors/locale-format-unrepresentable.json")
        mock = Mock([json_response(body, 400, {"cf-ray": "abc-AMS"})])
        client, _ = client_for("private", mock)
        error = failure(lambda: client.locale.export(WORKSPACE_ID, format="world"))
        assert error.status == 400
        assert error.code == "INVALID_INPUT"
        assert error.detail == "LOCALE_FORMAT_UNREPRESENTABLE"
        assert error.message == "Plural values cannot be written to this format."
        assert str(error) == error.message
        assert error.request_id == "abc-AMS"
        assert error.retry_after is None
        assert error.body is not None and error.body["key"] == "cart.items" and error.body["language"] == "tr"
        assert isinstance(error, Exception)

    def test_prefers_x_request_id_and_builds_a_default_message(self) -> None:
        mock = Mock([json_response({"code": "FORBIDDEN"}, 403, {"x-request-id": "req_1", "cf-ray": "ray"})])
        client, _ = client_for("private", mock)
        error = failure(lambda: client.memory.list_scopes())
        assert error.request_id == "req_1"
        assert error.message == "NullDull request failed (403 FORBIDDEN)."
        assert error.detail is None

    def test_retry_after_becomes_retry_after(self) -> None:
        mock = Mock([json_response({"code": "RATE_LIMITED"}, 429, {"retry-after": "120"})])
        client, _ = client_for("private", mock)
        assert failure(lambda: client.memory.list_scopes()).retry_after == 120

    def test_non_json_error_body_gives_request_failed(self) -> None:
        mock = Mock([httpx.Response(502, headers={"content-type": "text/html"}, content=b"<html>bad gateway</html>")])
        client, _ = client_for("private", mock, max_retries=0)
        error = failure(lambda: client.memory.list_scopes())
        assert (error.status, error.code, error.body) == (502, "REQUEST_FAILED", None)
        assert error.message == "NullDull request failed (502 REQUEST_FAILED)."

    def test_json_error_without_a_string_code_gives_request_failed(self) -> None:
        mock = Mock([json_response({"code": 7, "message": "x"}, 400)])
        client, _ = client_for("private", mock)
        error = failure(lambda: client.memory.list_scopes())
        assert (error.code, error.message) == ("REQUEST_FAILED", "x")

    @pytest.mark.parametrize("content", [b"<html>", b"", b"NaN", b"{"])
    def test_invalid_json_on_success_is_invalid_response(self, content: bytes) -> None:
        mock = Mock([httpx.Response(200, headers={"cf-ray": "r"}, content=content)])
        client, _ = client_for("private", mock)
        error = failure(lambda: client.memory.list_scopes())
        assert (error.code, error.status, error.request_id) == ("INVALID_RESPONSE", 200, "r")
        assert len(mock.requests) == 1

    def test_redirects_are_errors_and_not_followed(self) -> None:
        mock = Mock([httpx.Response(302, headers={"location": "https://evil.example/"})])
        client, _ = client_for("public", mock)
        error = failure(lambda: client.grid.list_pages("nulldull-blog"))
        assert (error.status, error.code) == (302, "REQUEST_FAILED")
        assert len(mock.requests) == 1

    def test_redirects_are_not_followed_with_a_caller_client(self) -> None:
        mock = Mock([httpx.Response(307, headers={"location": "https://evil.example/"})])
        http_client = httpx.Client(transport=mock.transport, follow_redirects=True)
        client = NullDull(PUBLIC_KEY, http_client=http_client)
        assert failure(lambda: client.grid.list_pages("nulldull-blog")).status == 307
        assert len(mock.requests) == 1
        client.close()
        assert not http_client.is_closed

    def test_errors_pickle(self) -> None:
        error = NullDullError(
            429, "RATE_LIMITED", "slow down", detail="d", request_id="r", retry_after=60, body={"a": 1}
        )
        copy = pickle.loads(pickle.dumps(error))
        assert (copy.status, copy.code, copy.message, copy.detail, copy.request_id, copy.retry_after, copy.body) == (
            429,
            "RATE_LIMITED",
            "slow down",
            "d",
            "r",
            60,
            {"a": 1},
        )


    def test_paused_public_requests_are_typed_and_not_retried(self) -> None:
        body = fixture("errors/public-requests-paused.json")
        mock = Mock([json_response(body, 429, {"retry-after": "691200"})])
        client, sleeps = client_for("public", mock)
        error = failure(lambda: client.grid.list_pages("nulldull-blog"))
        assert (error.status, error.code, error.detail) == (429, "RATE_LIMITED", "PUBLIC_REQUESTS_PAUSED")
        assert error.reason == nulldull.PUBLIC_REQUESTS_PAUSED == "PUBLIC_REQUESTS_PAUSED"
        assert error.renews_at == "2026-12-01T00:00:00.000Z"
        assert error.retry_after == 691200
        assert error.public_requests_paused
        assert nulldull.is_public_requests_paused(error)
        assert (sleeps, len(mock.requests)) == ([], 1)
        copy = pickle.loads(pickle.dumps(error))
        assert (copy.reason, copy.renews_at, copy.public_requests_paused) == (error.reason, error.renews_at, True)

    def test_paused_public_requests_without_retry_after_are_not_retried(self) -> None:
        mock = Mock([json_response(fixture("errors/public-requests-paused.json"), 429)])
        client, sleeps = client_for("public", mock)
        error = failure(lambda: client.grid.list_pages("nulldull-blog"))
        assert (error.public_requests_paused, error.retry_after, sleeps, len(mock.requests)) == (True, None, [], 1)

    def test_other_errors_are_not_paused(self) -> None:
        mock = Mock([json_response({"code": "RATE_LIMITED"}, 429, {"retry-after": "60"})])
        client, _ = client_for("private", mock)
        error = failure(lambda: client.memory.list_scopes())
        assert (error.reason, error.renews_at, error.public_requests_paused) == (None, None, False)
        assert not nulldull.is_public_requests_paused(error)
        assert not nulldull.is_public_requests_paused(ValueError("x"))
        assert not NullDullError(409, "CONFLICT", body={"reason": "QUOTA_EXCEEDED"}).public_requests_paused


# --------------------------------------------------------------------------- 10. retries


class TestRetries:
    def test_parses_retry_after(self) -> None:
        now = datetime(2026, 11, 20, 10, 0, 0, tzinfo=timezone.utc).timestamp()
        assert parse_retry_after("Fri, 20 Nov 2026 10:00:05 GMT", now) == 5
        assert parse_retry_after("Fri, 20 Nov 2026 09:00:00 GMT", now) == 0
        assert parse_retry_after("7") == 7
        assert parse_retry_after(" 7 ") == 7
        assert parse_retry_after("soon") is None
        assert parse_retry_after("-1") is None
        assert parse_retry_after(None) is None

    def test_waits_for_retry_after_up_to_30_seconds(self) -> None:
        mock = Mock(
            [
                json_response({"code": "RATE_LIMITED"}, 429, {"retry-after": "30"}),
                json_response(fixture("memory/scopes.json")),
            ]
        )
        client, sleeps = client_for("private", mock)
        client.memory.list_scopes()
        assert sleeps == [30000]

    def test_raises_retry_after_over_30_seconds_at_once(self) -> None:
        mock = Mock([json_response({"code": "RATE_LIMITED"}, 429, {"retry-after": "31"})])
        client, sleeps = client_for("private", mock)
        error = failure(lambda: client.memory.list_scopes())
        assert (error.code, error.retry_after, sleeps, len(mock.requests)) == ("RATE_LIMITED", 31, [], 1)

    @pytest.mark.parametrize("status", [502, 503, 504])
    def test_backs_off_500_then_1000_ms(self, status: int) -> None:
        mock = Mock([json_response({"code": "X"}, status) for _ in range(3)])
        client, sleeps = client_for("private", mock)
        assert failure(lambda: client.memory.list_scopes()).status == status
        assert sleeps == [500, 1000]
        assert len(mock.requests) == 3

    def test_retries_429_without_retry_after_with_backoff(self) -> None:
        mock = Mock(
            [
                json_response({"code": "X"}, 504),
                json_response({"code": "RATE_LIMITED"}, 429),
                json_response(fixture("memory/scopes.json")),
            ]
        )
        client, sleeps = client_for("private", mock)
        client.memory.list_scopes()
        assert sleeps == [500, 1000]

    def test_max_retries_zero_disables_retries(self) -> None:
        mock = Mock([json_response({"code": "SERVICE_UNAVAILABLE"}, 503)])
        client, sleeps = client_for("private", mock, max_retries=0)
        assert failure(lambda: client.memory.list_scopes()).code == "SERVICE_UNAVAILABLE"
        assert (len(mock.requests), sleeps) == (1, [])

    def test_max_retries_bounds_attempts(self) -> None:
        mock = Mock([json_response({"code": "X"}, 503) for _ in range(5)])
        client, sleeps = client_for("private", mock, max_retries=4)
        failure(lambda: client.memory.list_scopes())
        assert sleeps == [500, 1000, 2000, 4000]
        assert len(mock.requests) == 5

    @pytest.mark.parametrize("status", [400, 401, 403, 404, 409, 500, 501])
    def test_never_retries_other_statuses(self, status: int) -> None:
        mock = Mock([json_response({"code": "X"}, status)])
        client, sleeps = client_for("private", mock)
        assert failure(lambda: client.memory.list_scopes()).status == status
        assert (len(mock.requests), sleeps) == (1, [])

    def test_retries_network_errors_and_reports_network_error(self) -> None:
        mock = Mock([httpx.ConnectError("refused") for _ in range(3)])
        client, sleeps = client_for("private", mock)
        error = failure(lambda: client.memory.list_scopes())
        assert (error.code, error.status) == ("NETWORK_ERROR", 0)
        assert isinstance(error.__cause__, httpx.ConnectError)
        assert len(mock.requests) == 3
        assert sleeps == [500, 1000]

    def test_recovers_after_one_network_error(self) -> None:
        mock = Mock([httpx.RemoteProtocolError("reset"), json_response(fixture("memory/scopes.json"))])
        client, _ = client_for("private", mock)
        assert len(client.memory.list_scopes()["items"]) == 3

    def test_does_not_retry_timeouts(self) -> None:
        mock = Mock([httpx.ReadTimeout("slow"), json_response(fixture("memory/scopes.json"))])
        client, sleeps = client_for("private", mock)
        error = failure(lambda: client.memory.list_scopes())
        assert (error.code, error.status, len(mock.requests), sleeps) == ("TIMEOUT", 0, 1, [])

    def test_does_not_retry_invalid_responses(self) -> None:
        mock = Mock([httpx.Response(200, content=b"<"), json_response({})])
        client, _ = client_for("private", mock)
        failure(lambda: client.memory.list_scopes())
        assert len(mock.requests) == 1


# --------------------------------------------------------------------------- 11. timeouts


class _SlowBody(httpx.SyncByteStream):
    def __iter__(self) -> Iterator[bytes]:
        for _ in range(20):
            time.sleep(0.02)
            yield b"{"


class TestTimeouts:
    def test_connect_and_read_timeouts_raise_timeout(self) -> None:
        for exc in (httpx.ConnectTimeout("c"), httpx.ReadTimeout("r"), httpx.PoolTimeout("p")):
            mock = Mock([exc])
            client, _ = client_for("private", mock, timeout=5)
            assert failure(client.memory.list_scopes).code == "TIMEOUT"

    def test_reading_the_body_counts_toward_the_timeout(self) -> None:
        mock = Mock([lambda request: httpx.Response(200, stream=_SlowBody())])
        client, sleeps = client_for("private", mock, timeout=0.05)
        error = failure(lambda: client.memory.list_scopes())
        assert (error.code, len(mock.requests), sleeps) == ("TIMEOUT", 1, [])

    def test_sets_the_httpx_timeout_per_attempt(self) -> None:
        mock = Mock(
            [json_response({"items": [], "nextCursor": None}), json_response({"items": [], "nextCursor": None})]
        )
        client, _ = client_for("private", mock, timeout=7)
        client.memory.list_scopes()
        assert mock.requests[0].extensions["timeout"] == {"connect": 7.0, "read": 7.0, "write": 7.0, "pool": 7.0}
        client, _ = client_for("private", mock, timeout=0)
        client.memory.list_scopes()
        assert mock.requests[1].extensions["timeout"] == {"connect": None, "read": None, "write": None, "pool": None}

    def test_real_server_timeout(self) -> None:
        """A real socket that accepts and never answers: the per-attempt timeout fires once."""
        import socket

        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        try:
            port = server.getsockname()[1]
            client = NullDull(PUBLIC_KEY, base_url=f"http://127.0.0.1:{port}", timeout=0.2, sleep=lambda s: None)
            started = time.monotonic()
            assert failure(lambda: client.grid.list_pages("nulldull-blog")).code == "TIMEOUT"
            assert time.monotonic() - started < 2
            client.close()
        finally:
            server.close()


# --------------------------------------------------------------------------- 12. Memory filters


class TestMemoryFilters:
    def empty(self, n: int) -> Mock:
        return Mock([json_response({"items": [], "nextCursor": None}) for _ in range(n)])

    def test_root_for_none_literal_root_and_nothing_when_omitted(self) -> None:
        mock = self.empty(6)
        client, _ = client_for("private", mock)
        client.memory.list_assets(folder_id=None)
        client.memory.list_folders(parent_id="root")
        client.memory.list_documents()
        client.memory.list_documents(tags=[])
        client.memory.list_folders(parent_id=None, scope_id=None, after=None)
        client.memory.list_documents(folder_id=None)
        queries = [r.url.query.decode() for r in mock.requests]
        assert queries == ["folderId=root", "parentId=root", "", "", "parentId=root", "folderId=root"]

    def test_tags_are_repeated(self) -> None:
        mock = self.empty(3)
        client, _ = client_for("private", mock)
        client.memory.list_documents(tags=["a", "b"], kind="rules", lifecycle="one-time")
        client.memory.search("query", tags=("x", "y"))
        client.memory.list_assets(tags=["brand"], q="logo")
        assert mock.requests[0].url.query == b"tag=a&tag=b&kind=rules&lifecycle=one-time"
        assert mock.requests[1].url.params.get_list("tag") == ["x", "y"]
        assert mock.requests[2].url.query == b"q=logo&tag=brand"

    def test_download_previews_send_preview_true_and_w(self) -> None:
        mock = Mock([httpx.Response(200, content=b"a") for _ in range(3)])
        client, _ = client_for("private", mock)
        client.memory.download_asset("a1", width=256)
        client.memory.download_asset("a1", preview=True)
        client.memory.download_asset("a1", revision_id="r1")
        assert mock.requests[0].url.query == b"preview=true&w=256"
        assert mock.requests[1].url.query == b"preview=true"
        assert mock.requests[2].url.query == b"revisionId=r1"
        assert all("submissionId" not in r.url.params for r in mock.requests)

    @pytest.mark.parametrize("width", [0, -1, 2.5, True])
    def test_rejects_bad_widths(self, width: Any) -> None:
        mock = Mock()
        client, _ = client_for("private", mock)
        assert failure(lambda: client.memory.download_asset("a1", width=width)).code == "INVALID_ARGUMENT"
        assert mock.requests == []

    def test_query_values_are_percent_encoded(self) -> None:
        mock = self.empty(2)
        client, _ = client_for("private", mock)
        client.memory.search("a&b c/é")
        client.memory.resolve_link("doc", "../x y.md#frag")
        assert mock.requests[0].url.query == b"q=a%26b%20c%2F%C3%A9"
        assert mock.requests[1].url.query == b"href=..%2Fx%20y.md%23frag"


# --------------------------------------------------------------------------- 13. Locale export


class TestLocaleExport:
    def test_always_sends_format_comma_joins_and_never_sends_language(self) -> None:
        mock = Mock([json_response(fixture("locale/export-json.json")) for _ in range(4)])
        client, _ = client_for("private", mock)
        client.locale.export("scope")
        client.locale.export("scope", languages=["en", "tr"], status=["approved", "needs_review"], basename="App")
        client.locale.export("scope", format="xcstrings", languages="en", status="draft")
        client.locale.export("scope", languages=[], status=[])
        queries = [r.url.query.decode() for r in mock.requests]
        assert queries == [
            "scopeId=scope&format=json",
            "scopeId=scope&format=json&languages=en%2Ctr&status=approved%2Cneeds_review&basename=App",
            "scopeId=scope&format=xcstrings&languages=en&status=draft",
            "scopeId=scope&format=json",
        ]
        assert all("language" not in r.url.params for r in mock.requests)

    @pytest.mark.parametrize("languages", [["en,tr"], [""], [1], "a,b", {"en": 1}])
    def test_rejects_bad_lists(self, languages: Any) -> None:
        mock = Mock()
        client, _ = client_for("private", mock)
        assert failure(lambda: client.locale.export("scope", languages=languages)).code == "INVALID_ARGUMENT"
        assert mock.requests == []

    def test_sends_unknown_formats_anyway(self) -> None:
        mock = Mock([json_response(fixture("errors/locale-format-unrepresentable.json"), 400)])
        client, _ = client_for("private", mock)
        failure(lambda: client.locale.export("scope", format="future-format"))
        assert mock.requests[0].url.params["format"] == "future-format"


# --------------------------------------------------------------------------- 14. downloads


class TestFilenames:
    @pytest.mark.parametrize(
        ("header", "expected"),
        [
            ("attachment; filename*=UTF-8''brand%20logo%20%E2%80%93%20dark.png", "brand logo \u2013 dark.png"),
            ("attachment; filename=\"fallback.png\"; filename*=UTF-8''real%20name.png", "real name.png"),
            ('attachment; filename="quoted \\"name\\".txt"', 'quoted "name".txt'),
            ("attachment; filename=plain.txt", "plain.txt"),
            ("attachment; filename*=UTF-8''bad%ZZ; filename=\"safe.txt\"", "safe.txt"),
            ("attachment; filename*=UTF-8''bad%FF; filename=\"safe.txt\"", "safe.txt"),
            ("inline", None),
            ("", None),
            (None, None),
        ],
    )
    def test_parse_filename(self, header: Any, expected: Any) -> None:
        assert parse_filename(header) == expected

    def test_download_without_content_type_or_filename(self) -> None:
        mock = Mock([httpx.Response(200, content=b"abc")])
        client, _ = client_for("private", mock)
        download = client.memory.download_asset("a1")
        assert (download.bytes, download.content_type, download.filename, download.size) == (b"abc", None, None, 3)
