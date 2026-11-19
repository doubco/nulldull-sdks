"""Shared conformance fixtures (fixtures/manifest.json), run against both the sync and async clients."""

from __future__ import annotations

import asyncio
import base64
from typing import Any, Dict, List

import pytest

from nulldull import Download, NullDullError
from support import (
    BASE_URL,
    MANIFEST,
    PRIVATE_KEY,
    PUBLIC_KEY,
    Mock,
    async_client_for,
    at,
    client_for,
    fixture,
    invoke,
    invoke_async,
    multimap,
    response_from,
    without,
)

CASES: List[Dict[str, Any]] = MANIFEST["cases"]


def run(case: Dict[str, Any], mode: str) -> Any:
    mock = Mock([response_from(exchange["response"]) for exchange in case["exchanges"]])
    result: Any = None
    failure: Any = None
    if mode == "sync":
        client, sleeps = client_for(case["key"], mock)
        try:
            result = invoke(client, case["call"]["method"], case["call"]["args"])
        except NullDullError as error:
            failure = error
    else:
        aclient, sleeps = async_client_for(case["key"], mock)

        async def call() -> Any:
            return await invoke_async(aclient, case["call"]["method"], case["call"]["args"])

        try:
            result = asyncio.run(call())
        except NullDullError as error:
            failure = error
    return mock, sleeps, result, failure


@pytest.mark.parametrize("mode", ["sync", "async"])
@pytest.mark.parametrize("case", CASES, ids=[case["id"] for case in CASES])
def test_manifest_case(case: Dict[str, Any], mode: str) -> None:
    mock, sleeps, result, failure = run(case, mode)
    expect = case["expect"]

    attempts = expect.get("attempts", len(case["exchanges"]))
    assert len(mock.requests) == attempts
    key = PUBLIC_KEY if case["key"] == "public" else PRIVATE_KEY
    for request, exchange in zip(mock.requests, case["exchanges"]):
        wanted = exchange["request"]
        assert request.method == wanted["method"]
        assert f"{request.url.scheme}://{request.url.host}" == BASE_URL
        assert request.url.path == wanted["path"]
        assert multimap(request) == wanted["query"]
        assert request.headers["authorization"] == f"Bearer {key}"
        assert "submissionId" not in request.url.params
        assert "language" not in request.url.params
    if "sleeps" in expect:
        assert sleeps == expect["sleeps"]

    if "error" in expect:
        assert isinstance(failure, NullDullError), "expected the call to fail"
        fields = {
            "status": "status",
            "code": "code",
            "message": "message",
            "detail": "detail",
            "requestId": "request_id",
            "retryAfter": "retry_after",
        }
        for field, value in expect["error"].items():
            if field == "body":
                assert failure.body is not None
                assert {k: failure.body.get(k) for k in value} == value
            else:
                assert getattr(failure, fields[field]) == value, field
        return
    if failure is not None:
        raise failure

    if "resultFile" in expect:
        excepted = expect.get("except")
        assert without(result, excepted) == without(fixture(expect["resultFile"]), excepted)
    if "itemCount" in expect:
        assert len(result) == expect["itemCount"]
    for check in expect.get("checks", []):
        assert at(result, check["path"]) == check["equals"], check["path"]
    if "download" in expect:
        download = expect["download"]
        assert isinstance(result, Download)
        assert result.content_type == download["contentType"]
        assert result.filename == download["filename"]
        assert result.size == download["size"]
        assert isinstance(result.bytes, bytes)
        assert base64.b64encode(result.bytes).decode() == download["bytesBase64"]
