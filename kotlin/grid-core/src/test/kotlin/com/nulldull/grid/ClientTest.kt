package com.nulldull.grid

import com.nulldull.grid.client.GridClient
import com.nulldull.grid.client.GridHttpEngine
import com.nulldull.grid.client.GridHttpRequest
import com.nulldull.grid.client.GridHttpResponse
import com.nulldull.grid.client.GridNetworkException
import com.nulldull.grid.client.GridPublicException
import com.nulldull.grid.client.GridResponseException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ClientTest {
    private val publicKey = "nd_pub_" + "a".repeat(64)
    private val privateKey = "nd_sec_" + "b".repeat(64)
    private val base = "https://example.com/api/grid/v1"

    private class Recorder(val respond: (GridHttpRequest) -> GridHttpResponse) : GridHttpEngine {
        val calls = mutableListOf<GridHttpRequest>()
        override suspend fun get(request: GridHttpRequest): GridHttpResponse { calls += request; return respond(request) }
    }

    private fun ok(path: String) = GridHttpResponse(200, mapOf("content-type" to "application/json"), Fixtures.text(path).toByteArray())

    @Test
    fun getPageDecodesTheApiResponseAndResolvesAssets() = runTest {
        val engine = Recorder { ok("delivery/page.json") }
        val page = GridClient(base, publicKey, engine).getPage("example-pool", "showcase", locale = "pt-br")
        val call = engine.calls.single()
        assertEquals("$base/pools/example-pool/pages/showcase?locale=pt-br", call.url)
        assertEquals("Bearer $publicKey", call.headers["Authorization"])
        assertEquals("application/json", call.headers["Accept"])
        assertFalse(call.headers.keys.any { it.equals("cookie", true) })
        assertEquals("Showcase", page.title)
        assertEquals(2, page.version)
        assertEquals(7, page.sourceVersion)
        assertEquals("folder-a", page.folderId)
        assertEquals(
            "https://example.com/api/grid/v1/pools/example-pool/pages/showcase/assets/photo?version=1&key=$publicKey",
            page.cover!!.url,
        )
        assertEquals(page.cover!!.url, page.assetUrl("photo"))
        assertEquals("A coastline at dusk", page.cover!!.alt)
        assertTrue(page.document.nodes.isNotEmpty())
        assertNull(page.assetUrl("missing"))
    }

    @Test
    fun listPagesEncodesQueriesLikeUrlSearchParams() = runTest {
        val engine = Recorder { ok("delivery/list.json") }
        val list = GridClient(base, engine = engine).listPages("example-pool", q = "space & word", after = "a+b==", limit = 2, folderId = "folder_a")
        val url = engine.calls.single().url
        assertEquals("$base/pools/example-pool/pages?locale=en&after=a%2Bb%3D%3D&q=space+%26+word&folderId=folder_a&limit=2", url)
        assertNull(engine.calls.single().headers["Authorization"])
        assertEquals("opaque-cursor+/=", list.nextCursor)
        assertEquals(3, list.items.size)
        assertNull(list.items[1].cover)
        assertNull(list.items[1].folderId)
        // Anonymous clients never add a key to asset URLs.
        assertEquals("https://example.com/api/grid/v1/pools/example-pool/pages/showcase/assets/photo?version=1", list.items[0].cover!!.url)
    }

    @Test
    fun rejectsUnsafeInputsBeforeAnyRequest() = runTest {
        val engine = Recorder { error("no request expected") }
        val client = GridClient(base, engine = engine)
        assertFailsWith<IllegalArgumentException> { client.getPage("../private", "x") }
        assertFailsWith<IllegalArgumentException> { client.getPage("pool", "Upper") }
        assertFailsWith<IllegalArgumentException> { client.listPages("pool", folderId = "../private") }
        assertFailsWith<IllegalArgumentException> { client.listPages("pool", locale = "EN") }
        assertFailsWith<IllegalArgumentException> { client.listPages("pool", limit = 51) }
        assertFailsWith<IllegalArgumentException> { GridClient("ftp://example.com", engine = engine) }
        assertFailsWith<IllegalArgumentException> { GridClient("https://user:pw@example.com/api", engine = engine) }
        assertFailsWith<IllegalArgumentException> { GridClient("$base?x=1", engine = engine) }
        assertFailsWith<IllegalArgumentException> { GridClient(base, "nd_pub_short", engine) }
        assertTrue(engine.calls.isEmpty())
    }

    @Test
    fun privateKeysAreServerOnlyAndNeverEnterUrls() = runTest {
        assertFailsWith<IllegalArgumentException> { GridClient(base, privateKey) }
        val engine = Recorder { ok("delivery/page.json") }
        val page = GridClient(base, privateKey, engine, allowPrivateKey = true).getPage("example-pool", "showcase")
        assertEquals("Bearer $privateKey", engine.calls.single().headers["Authorization"])
        assertFalse(page.assets.any { "key=" in it.url })
        assertFalse(page.cover!!.url.contains(privateKey))
    }

    @Test
    fun publicKeysAreOnlyAddedToSameOriginAssets() {
        val client = GridClient(base, publicKey, Recorder { error("unused") })
        assertEquals("https://example.com/a.png?key=$publicKey", client.assetUrl("/a.png"))
        assertEquals("https://example.com/a.png?key=existing", client.assetUrl("/a.png?key=existing"))
        assertEquals("https://cdn.example/a.png", client.assetUrl("https://cdn.example/a.png"))
    }

    @Test
    fun errorsCarryStatusAndCode() = runTest {
        val notFound = GridClient(base, engine = Recorder { GridHttpResponse(404, emptyMap(), Fixtures.text("delivery/error.json").toByteArray()) })
        val error = assertFailsWith<GridPublicException> { notFound.getPage("example-pool", "missing") }
        assertEquals(404, error.status)
        assertEquals("NOT_FOUND", error.code)
        val opaque = GridClient(base, engine = Recorder { GridHttpResponse(502, emptyMap(), "<html>".toByteArray()) })
        assertEquals("REQUEST_FAILED", assertFailsWith<GridPublicException> { opaque.getPage("a", "b") }.code)
        val redirect = GridClient(base, engine = Recorder { GridHttpResponse(302, mapOf("location" to "https://evil.example"), ByteArray(0)) })
        assertFailsWith<GridNetworkException> { redirect.getPage("a", "b") }
        val offline = GridClient(base, engine = { throw IOException("offline") })
        assertFailsWith<GridNetworkException> { offline.getPage("a", "b") }
        val garbage = GridClient(base, engine = Recorder { GridHttpResponse(200, emptyMap(), "{\"id\":1}".toByteArray()) })
        assertFailsWith<GridResponseException> { garbage.getPage("a", "b") }
        val invalidDocument = Fixtures.text("delivery/page.json").replace("\"direction\": \"vertical\"", "\"direction\": \"diagonal\"")
        val invalid = GridClient(base, engine = Recorder { GridHttpResponse(200, emptyMap(), invalidDocument.toByteArray()) })
        assertTrue(assertFailsWith<GridResponseException> { invalid.getPage("a", "b") }.message!!.contains("Invalid option."))
    }

    @Test
    fun cancellationPropagatesToTheEngine() = runTest {
        val started = CompletableDeferred<Unit>()
        val cancelled = CompletableDeferred<Unit>()
        val client = GridClient(base, engine = {
            started.complete(Unit)
            try { awaitCancellation() } finally { cancelled.complete(Unit) }
        })
        val request = async { client.getPage("example-pool", "showcase") }
        started.await()
        request.cancel()
        yield()
        cancelled.await()
        assertTrue(request.isCancelled)
    }
}
