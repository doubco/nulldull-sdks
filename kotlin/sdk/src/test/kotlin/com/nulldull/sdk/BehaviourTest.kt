package com.nulldull.sdk

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import okio.Buffer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit
import kotlin.time.Duration.Companion.milliseconds

/** The behaviours SPEC.md section 11 lists beyond the manifest, numbered as there. */
class BehaviourTest {
    private lateinit var server: MockWebServer

    @BeforeEach
    fun start() {
        server = MockWebServer().apply { start() }
    }

    @AfterEach
    fun stop() {
        server.shutdown()
    }

    private val emptyPage = """{"items":[],"nextCursor":null}"""

    @Nested
    inner class `1 construction` {
        private fun make(
            apiKey: String = PUBLIC_KEY,
            baseUrl: String = DEFAULT_BASE_URL,
            workspaceId: String? = null,
        ) = NullDullClient(apiKey = apiKey, baseUrl = baseUrl, workspaceId = workspaceId)

        @Test
        fun `rejects malformed keys`() {
            for (key in listOf("", "nd_pub_123", "nd_xyz_${"a".repeat(64)}", "nd_pub_${"A".repeat(64)}", "ndm_${"a".repeat(64)}", " $PUBLIC_KEY")) {
                val error = failure { make(apiKey = key) }
                assertCode("INVALID_ARGUMENT", error)
                assertEquals(0, error.status)
            }
        }

        @Test
        fun `rejects bad base URLs`() {
            for (url in listOf("ftp://nulldull.com", "nulldull.com", "https://user:pass@nulldull.com", "https://user@nulldull.com", "https://nulldull.com/?x=1", "https://nulldull.com/?", "https://nulldull.com/#top")) {
                assertCode("INVALID_ARGUMENT", failure { make(baseUrl = url) })
            }
        }

        @Test
        fun `rejects malformed workspace IDs, timeouts and retries`() {
            assertCode("INVALID_ARGUMENT", failure { make(workspaceId = "../etc") })
            assertCode("INVALID_ARGUMENT", failure { make(workspaceId = "a".repeat(129)) })
            assertCode("INVALID_ARGUMENT", failure { make(workspaceId = "") })
            assertCode("INVALID_ARGUMENT", failure { NullDullClient(PUBLIC_KEY, timeout = (-1).milliseconds) })
            assertCode("INVALID_ARGUMENT", failure { NullDullClient(PUBLIC_KEY, maxRetries = -1) })
            make(workspaceId = "a".repeat(128))
        }

        @Test
        fun `strips a trailing slash and keeps a path prefix`() = runBlocking<Unit> {
            assertEquals("https://staging.nulldull.com", make(baseUrl = "https://staging.nulldull.com/").baseUrl)
            assertEquals("https://nulldull.com", make(baseUrl = "https://NULLDULL.com:443").baseUrl)
            server.enqueue(jsonFixture("grid/page-list-last.json"))
            val prefix = server.url("/proxy/").toString()
            val client = NullDullClient(PUBLIC_KEY, baseUrl = prefix)
            assertEquals(prefix.removeSuffix("/"), client.baseUrl)
            client.grid.listPages("nulldull-blog")
            assertEquals("/proxy/api/grid/v1/pools/nulldull-blog/pages?locale=en", server.takeRequest().path)
        }

        @Test
        fun `defaults to https nulldull com and exposes the key kind`() {
            val client = NullDullClient(PRIVATE_KEY)
            assertEquals("https://nulldull.com", client.baseUrl)
            assertEquals(KeyKind.PRIVATE, client.keyKind)
            assertEquals(KeyKind.PUBLIC, NullDullClient(PUBLIC_KEY).keyKind)
            assertFalse(client.toString().contains(PRIVATE_KEY))
        }
    }

    @Nested
    inner class `2 request headers` {
        @Test
        fun `sends Authorization, Accept and User-Agent`() = runBlocking<Unit> {
            server.enqueue(jsonFixture("memory/scopes.json"))
            server.enqueue(MockResponse().setBody("x"))
            val h = Harness(server, PRIVATE_KEY, userAgent = "my-app/2.0")
            h.client.memory.listScopes()
            h.client.memory.downloadAsset("asset_1")
            val first = h.take()
            val second = h.take()
            assertEquals("GET", first.method)
            assertEquals("Bearer $PRIVATE_KEY", first.getHeader("Authorization"))
            assertEquals("application/json", first.getHeader("Accept"))
            assertEquals("nulldull-sdk-kotlin/0.1.0 my-app/2.0", first.getHeader("User-Agent"))
            assertEquals("*/*", second.getHeader("Accept"))
            assertEquals("Bearer $PRIVATE_KEY", second.getHeader("Authorization"))
        }

        @Test
        fun `sends the bare User-Agent without a suffix`() = runBlocking<Unit> {
            server.enqueue(jsonFixture("grid/page-list-last.json"))
            Harness(server, PUBLIC_KEY).client.grid.listPages("nulldull-blog")
            assertEquals("nulldull-sdk-kotlin/0.1.0", server.takeRequest().getHeader("User-Agent"))
        }

        @Test
        fun `keeps SDK_VERSION in sync with the build`() {
            assertEquals(System.getProperty("nulldull.version"), SDK_VERSION)
        }

        @Test
        fun `never sends cookies, even with a cookie jar on the caller's client`() = runBlocking<Unit> {
            val jar = object : CookieJar {
                override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) = Unit
                override fun loadForRequest(url: HttpUrl) = listOf(Cookie.Builder().name("session").value("secret").domain(url.host).build())
            }
            server.enqueue(jsonFixture("memory/scopes.json").setHeader("Set-Cookie", "a=b"))
            server.enqueue(jsonFixture("memory/scopes.json"))
            val client = NullDullClient(PRIVATE_KEY, WORKSPACE_ID, baseUrl = server.url("/").toString(), httpClient = OkHttpClient.Builder().cookieJar(jar).build())
            client.memory.listScopes()
            client.memory.listScopes()
            assertNull(server.takeRequest().getHeader("Cookie"))
            assertNull(server.takeRequest().getHeader("Cookie"))
        }
    }

    @Nested
    inner class `3 Memory and Locale preconditions` {
        @Test
        fun `needs workspaceId, without sending a request`() {
            val client = Harness(server, PRIVATE_KEY, workspaceId = null).client
            assertCode("WORKSPACE_REQUIRED", failure { client.memory.listDocuments() })
            assertCode("WORKSPACE_REQUIRED", failure { client.memory.downloadAsset("a") })
            assertCode("WORKSPACE_REQUIRED", failure { client.locale.export(WORKSPACE_ID) })
            assertCode("WORKSPACE_REQUIRED", failure { client.memory.iterateDocuments().toList() })
            assertEquals(0, server.requestCount)
        }

        @Test
        fun `needs a private key, without sending a request`() {
            val client = Harness(server, PUBLIC_KEY).client
            assertCode("PRIVATE_KEY_REQUIRED", failure { client.memory.getDocument("doc") })
            assertCode("PRIVATE_KEY_REQUIRED", failure { client.locale.listFormats() })
            assertCode("PRIVATE_KEY_REQUIRED", failure { client.memory.iterateTags().toList() })
            val noWorkspace = Harness(server, PUBLIC_KEY, workspaceId = null).client
            assertCode("PRIVATE_KEY_REQUIRED", failure { noWorkspace.memory.listScopes() })
            assertEquals(0, server.requestCount)
        }

        @Test
        fun `percent-encodes path segments and rejects empty IDs`() = runBlocking<Unit> {
            server.enqueue(json("{}"))
            val h = privateHarness(server)
            h.client.memory.getDocument("a/b c")
            assertEquals("/api/platform/workspaces/$WORKSPACE_ID/documents/a%2Fb%20c", h.take().requestUrl!!.encodedPath)
            assertCode("INVALID_ARGUMENT", failure { h.client.memory.getDocument("") })
            assertCode("INVALID_ARGUMENT", failure { h.client.memory.getFolder("") })
            assertCode("INVALID_ARGUMENT", failure { h.client.locale.export("") })
            assertEquals(1, server.requestCount)
        }
    }

    @Nested
    inner class `4 Grid validation` {
        @Test
        fun `validates pool, slug, locale and limit before any request`() {
            val grid = publicHarness(server).client.grid
            val calls: List<suspend () -> Any> = listOf(
                { grid.listPages("Bad_Pool") },
                { grid.listPages("pool", locale = "EN") },
                { grid.listPages("pool", locale = "") },
                { grid.listPages("pool", locale = "e") },
                { grid.listPages("pool", limit = 0) },
                { grid.listPages("pool", limit = 51) },
                { grid.listPages("pool", folderId = "") },
                { grid.listPages("x".repeat(97)) },
                { grid.getPage("pool", "a--b") },
                { grid.getPage("pool", "-a") },
                { grid.getPage("pool", "x".repeat(97)) },
                { grid.getPage("pool", "slug", locale = "pt_BR") },
                { grid.iteratePages("pool", limit = 100).toList() },
            )
            for (call in calls) assertCode("INVALID_ARGUMENT", failure { call() })
            assertEquals(0, server.requestCount)
        }

        @Test
        fun `always sends locale, defaulting to en, and omits an empty q and after`() = runBlocking<Unit> {
            server.enqueue(jsonFixture("grid/page-list-last.json"))
            server.enqueue(jsonFixture("grid/page.json"))
            server.enqueue(jsonFixture("grid/page-list-last.json"))
            val h = publicHarness(server)
            h.client.grid.listPages("nulldull-blog", q = "", after = "")
            h.client.grid.getPage("nulldull-blog", "hello", locale = "pt-br")
            h.client.grid.listPages("x".repeat(96), limit = 50)
            assertEquals("locale=en", h.take().requestUrl!!.encodedQuery)
            assertEquals("locale=pt-br", h.take().requestUrl!!.encodedQuery)
            assertEquals("locale=en&limit=50", h.take().requestUrl!!.encodedQuery)
        }
    }

    @Nested
    inner class `5 grid assetUrl` {
        private val pub get() = NullDullClient(PUBLIC_KEY).grid
        private val sec get() = NullDullClient(PRIVATE_KEY).grid

        @Test
        fun `resolves relative URLs and adds a public key on the API origin`() {
            assertEquals(
                "https://nulldull.com/api/grid/v1/pools/p/pages/s/assets/a?locale=en&version=3&key=$PUBLIC_KEY",
                pub.assetUrl("/api/grid/v1/pools/p/pages/s/assets/a?locale=en&version=3"),
            )
            assertEquals("https://nulldull.com/x?key=$PUBLIC_KEY", pub.assetUrl("https://NULLDULL.com:443/x"))
            assertEquals("https://nulldull.com/x?key=$PUBLIC_KEY", pub.assetUrl("https://nulldull.com/x"))
        }

        @Test
        fun `resolves against the origin, not the base path`() {
            val grid = NullDullClient(PUBLIC_KEY, baseUrl = "https://nulldull.com/proxy").grid
            assertEquals("https://nulldull.com/api/x?key=$PUBLIC_KEY", grid.assetUrl("/api/x"))
        }

        @Test
        fun `keeps an existing key`() {
            assertEquals("https://nulldull.com/x?key=nd_pub_existing", pub.assetUrl("/x?key=nd_pub_existing"))
        }

        @Test
        fun `never adds a key to another origin`() {
            for (url in listOf(
                "https://cdn.example.com/a.png",
                "//evil.example/a.png",
                "https://nulldull.com.evil.example/a.png",
                "http://nulldull.com/a.png",
                "https://nulldull.com:8443/a.png",
                "https://evil.example/?u=https://nulldull.com",
            )) {
                assertFalse(pub.assetUrl(url).contains("key="), url)
            }
            assertEquals("https://evil.example/a.png", pub.assetUrl("//evil.example/a.png"))
        }

        @Test
        fun `never adds a private key`() {
            assertEquals(
                "https://nulldull.com/api/grid/v1/pools/p/pages/s/assets/a?version=1",
                sec.assetUrl("/api/grid/v1/pools/p/pages/s/assets/a?version=1"),
            )
        }

        @Test
        fun `rejects URLs that cannot be resolved`() {
            assertCode("INVALID_ARGUMENT", failure { pub.assetUrl("http://") })
        }
    }

    @Nested
    inner class `6 grid downloadAsset` {
        @Test
        fun `sends Authorization only to the API origin`() = runBlocking<Unit> {
            val other = MockWebServer().apply { start() }
            try {
                val bytes = { MockResponse().setHeader("Content-Type", "image/png").setHeader("Content-Disposition", "inline; filename*=UTF-8''cover.png").setBody(Buffer().write(byteArrayOf(1, 2, 3))) }
                server.enqueue(bytes())
                other.enqueue(bytes())
                other.enqueue(bytes())
                val base = server.url("/").toString()
                val priv = NullDullClient(PRIVATE_KEY, baseUrl = base).grid
                val page = GridPage(fixture("grid/page.json").jsonObject)
                val own = priv.downloadAsset(page.assets[0])
                assertEquals("image/png", own.contentType)
                assertEquals("cover.png", own.filename)
                assertEquals(3, own.size)
                priv.downloadAsset(other.url("/cover.png").toString())
                val pub = NullDullClient(PUBLIC_KEY, baseUrl = base).grid
                pub.downloadAsset(other.url("/cover.png").toString())

                val first = server.takeRequest()
                assertTrue(first.path!!.startsWith("/api/grid/v1/pools/nulldull-blog/pages/"))
                assertEquals("Bearer $PRIVATE_KEY", first.getHeader("Authorization"))
                assertEquals("*/*", first.getHeader("Accept"))
                val foreign = other.takeRequest()
                assertNull(foreign.getHeader("Authorization"))
                val foreignPublic = other.takeRequest()
                assertNull(foreignPublic.getHeader("Authorization"))
                assertEquals("/cover.png", foreignPublic.path)
            } finally {
                other.shutdown()
            }
        }

        @Test
        fun `rejects an empty URL`() {
            assertCode("INVALID_ARGUMENT", failure { NullDullClient(PUBLIC_KEY).grid.downloadAsset("") })
        }
    }

    @Nested
    inner class `7 URL normalization` {
        @Test
        fun `normalizes list covers and page covers and assets, leaving the rest untouched`() = runBlocking<Unit> {
            server.enqueue(jsonFixture("grid/page-list.json"))
            server.enqueue(jsonFixture("grid/page.json"))
            val client = publicHarness(server).client
            val list = client.grid.listPages("nulldull-blog")
            val page = client.grid.getPage("nulldull-blog", "context-that-survives-the-chat")
            assertTrue(list.items[0].cover!!.url.startsWith("https://nulldull.com/api/grid/v1/"))
            assertNull(list.items[1].cover)
            assertTrue(page.assets.isNotEmpty())
            assertTrue(page.assets.all { it.url.startsWith("https://nulldull.com/") })
            assertTrue(page.cover!!.url.startsWith("https://nulldull.com/"))
            assertEquals(fixture("grid/page.json").jsonObject["document"], page.document)
            assertEquals("nulldull-blog", list.pool.key)
            assertEquals("The Void", list.pool.name)
            assertEquals(list.items, list.json["items"]!!.jsonArray.map { GridPageSummary(it.jsonObject) })
        }

        @Test
        fun `fills a missing assets array`() = runBlocking<Unit> {
            server.enqueue(json("""{"id":"p","slug":"s","document":{"nodes":[]}}"""))
            val page = publicHarness(server).client.grid.getPage("nulldull-blog", "s")
            assertEquals(emptyList<GridAssetRef>(), page.assets)
            assertNull(page.cover)
        }
    }

    @Nested
    inner class `8 pagination` {
        @Test
        fun `starts from after and stops at a null cursor`() = runBlocking<Unit> {
            server.enqueue(jsonFixture("memory/documents-page-2.json"))
            val h = privateHarness(server)
            val items = h.client.memory.iterateDocuments(scopeId = "s", after = "cursor-1").toList()
            assertEquals(1, items.size)
            val query = h.take().queryMap()
            assertEquals(listOf("cursor-1"), query["after"])
            assertEquals(listOf("s"), query["scopeId"])
            assertEquals(1, server.requestCount)
        }

        @Test
        fun `continues through an empty page with a cursor`() = runBlocking<Unit> {
            server.enqueue(json("""{"items":[{"tag":"a","count":2}],"nextCursor":"c1"}"""))
            server.enqueue(json("""{"items":[],"nextCursor":"c2"}"""))
            server.enqueue(json("""{"items":[{"tag":"b","count":1}],"nextCursor":null}"""))
            val tags = privateHarness(server).client.memory.iterateTags().toList()
            assertEquals(listOf("a", "b"), tags.map { it.tag })
            assertEquals(3, server.requestCount)
        }

        @Test
        fun `raises INVALID_RESPONSE when a cursor repeats`() = runBlocking<Unit> {
            val page = """{"items":[{"id":"a"}],"nextCursor":"same"}"""
            server.enqueue(json(page))
            server.enqueue(json(page))
            val seen = mutableListOf<Scope>()
            val error = failure { privateHarness(server).client.memory.iterateScopes().collect { seen += it } }
            assertCode("INVALID_RESPONSE", error)
            assertEquals(2, seen.size)
        }

        @Test
        fun `is lazy - no request until collected, and stops early`() = runBlocking<Unit> {
            server.enqueue(jsonFixture("memory/tags-page-1.json"))
            val flow = privateHarness(server).client.memory.iterateTags()
            assertEquals(0, server.requestCount)
            val first = flow.take(1).toList()
            assertEquals("maintained", first.single().tag)
            assertEquals(1, server.requestCount)
        }

        @Test
        fun `single-page methods return extra fields`() = runBlocking<Unit> {
            server.enqueue(jsonFixture("memory/folders.json"))
            val list = privateHarness(server).client.memory.listFolders(scopeId = "s", parentId = FolderFilter.Root)
            assertEquals(fixture("memory/folders.json"), list.json)
            assertEquals(list.json["here"] != null, list.here != null)
        }
    }

    @Nested
    inner class `9 errors` {
        @Test
        fun `fills every field from body and headers`() {
            server.enqueue(jsonFixture("errors/locale-format-unrepresentable.json", 400, "CF-Ray" to "abc-AMS"))
            val error = failure { privateHarness(server).client.locale.export(WORKSPACE_ID, format = "world") }
            assertEquals(400, error.status)
            assertEquals("INVALID_INPUT", error.code)
            assertEquals("LOCALE_FORMAT_UNREPRESENTABLE", error.detail)
            assertEquals("Plural values cannot be written to this format.", error.message)
            assertEquals("abc-AMS", error.requestId)
            assertNull(error.retryAfter)
            assertEquals(JsonPrimitive("cart.items"), error.body!!["key"])
            assertEquals(JsonPrimitive("tr"), error.body!!["language"])
        }

        @Test
        fun `prefers X-Request-Id and builds a default message`() {
            server.enqueue(json("""{"code":"FORBIDDEN"}""", 403, "X-Request-Id" to "req_1", "CF-Ray" to "ray"))
            val error = failure { privateHarness(server).client.memory.listScopes() }
            assertEquals("req_1", error.requestId)
            assertEquals("NullDull request failed (403 FORBIDDEN).", error.message)
        }

        @Test
        fun `reads Retry-After into retryAfter`() {
            server.enqueue(jsonFixture("errors/rate-limited.json", 429, "Retry-After" to "60"))
            val error = failure { privateHarness(server).client.memory.listScopes() }
            assertEquals(60L, error.retryAfter)
            assertEquals("RATE_LIMITED", error.code)
        }

        @Test
        fun `a non-JSON or non-object error body gives REQUEST_FAILED`() {
            server.enqueue(MockResponse().setResponseCode(502).setHeader("Content-Type", "text/html").setBody("<html>Bad gateway</html>"))
            assertCode("REQUEST_FAILED", failure { privateHarness(server, maxRetries = 0).client.memory.listScopes() })
            server.enqueue(json("""["FORBIDDEN"]""", 403))
            val error = failure { privateHarness(server).client.memory.listScopes() }
            assertCode("REQUEST_FAILED", error)
            assertNull(error.body)
            server.enqueue(json("""{"code":42}""", 400))
            assertCode("REQUEST_FAILED", failure { privateHarness(server).client.memory.listScopes() })
        }

        @Test
        fun `reports invalid JSON on success as INVALID_RESPONSE`() {
            server.enqueue(MockResponse().setBody("<html>"))
            val error = failure { privateHarness(server).client.memory.listScopes() }
            assertCode("INVALID_RESPONSE", error)
            assertEquals(200, error.status)
            server.enqueue(MockResponse().setBody(""))
            assertCode("INVALID_RESPONSE", failure { privateHarness(server).client.memory.listScopes() })
        }

        @Test
        fun `reports JSON of the wrong shape as INVALID_RESPONSE`() {
            server.enqueue(json("[]"))
            assertCode("INVALID_RESPONSE", failure { privateHarness(server).client.memory.getDocument("d") })
            server.enqueue(json("""{"nextCursor":null}"""))
            assertCode("INVALID_RESPONSE", failure { privateHarness(server).client.memory.listScopes() })
            server.enqueue(json("""{"items":[1],"nextCursor":null}"""))
            assertCode("INVALID_RESPONSE", failure { publicHarness(server).client.grid.listPages("nulldull-blog") })
        }

        @Test
        fun `treats a redirect as an error instead of following it`() {
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", "https://evil.example/"))
            val error = failure { publicHarness(server).client.grid.listPages("nulldull-blog") }
            assertEquals(302, error.status)
            assertCode("REQUEST_FAILED", error)
            assertEquals(1, server.requestCount)
        }

        @Test
        fun `tolerates unknown fields and enum values`() = runBlocking<Unit> {
            server.enqueue(json("""{"items":[{"id":"s1","name":"New","kind":"galaxy","parentId":null,"brandNew":{"x":1}}],"nextCursor":null,"extra":true}"""))
            val page = privateHarness(server).client.memory.listScopes()
            val scope = page.items.single()
            assertEquals("galaxy", scope.kind)
            assertEquals(JsonObject(mapOf("x" to JsonPrimitive(1))), scope.json["brandNew"])
            assertEquals(JsonPrimitive(true), page.json["extra"])
            assertNull(scope.iconKind)
        }
    }

    @Nested
    inner class `10 retries` {
        @Test
        fun `parses Retry-After as seconds or an HTTP date`() {
            val format = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US).apply { timeZone = TimeZone.getTimeZone("GMT") }
            val now = format.parse("Fri, 20 Nov 2026 10:00:00 GMT").time
            assertEquals(5L, parseRetryAfter("Fri, 20 Nov 2026 10:00:05 GMT", now))
            assertEquals(0L, parseRetryAfter("Fri, 20 Nov 2026 09:00:00 GMT", now))
            assertEquals(7L, parseRetryAfter(" 7 "))
            assertNull(parseRetryAfter("soon"))
            assertNull(parseRetryAfter(null))
        }

        @Test
        fun `retries 504 and 429 without Retry-After with backoff`() = runBlocking<Unit> {
            server.enqueue(json("""{"code":"X"}""", 504))
            server.enqueue(json("""{"code":"RATE_LIMITED"}""", 429))
            server.enqueue(jsonFixture("memory/scopes.json"))
            val h = privateHarness(server)
            h.client.memory.listScopes()
            assertEquals(listOf(500L, 1000L), h.sleeps)
            assertEquals(3, server.requestCount)
        }

        @Test
        fun `accepts Retry-After of exactly 30 seconds, and an HTTP date`() = runBlocking<Unit> {
            server.enqueue(json("""{"code":"RATE_LIMITED"}""", 429, "Retry-After" to "30"))
            server.enqueue(jsonFixture("memory/scopes.json"))
            val h = privateHarness(server)
            h.client.memory.listScopes()
            assertEquals(listOf(30_000L), h.sleeps)

            val format = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US).apply { timeZone = TimeZone.getTimeZone("GMT") }
            server.enqueue(json("""{"code":"SERVICE_UNAVAILABLE"}""", 503, "Retry-After" to format.format(System.currentTimeMillis() + 3_600_000)))
            val error = failure { h.client.memory.listScopes() }
            assertCode("SERVICE_UNAVAILABLE", error)
            assertTrue(error.retryAfter!! > 30)
            assertEquals(listOf(30_000L), h.sleeps)
        }

        @Test
        fun `raises Retry-After above 30 seconds without retrying`() {
            server.enqueue(json("""{"code":"RATE_LIMITED"}""", 429, "Retry-After" to "31"))
            val h = privateHarness(server)
            val error = failure { h.client.memory.listScopes() }
            assertEquals(31L, error.retryAfter)
            assertEquals(emptyList<Long>(), h.sleeps)
            assertEquals(1, server.requestCount)
        }

        @Test
        fun `502, 503 and 504 back off 500 then 1000 ms and raise the last error`() {
            for (status in listOf(502, 503, 504)) {
                server.enqueue(json("""{"code":"A"}""", status))
                server.enqueue(json("""{"code":"B"}""", status))
                server.enqueue(json("""{"code":"C"}""", status))
            }
            for (status in listOf(502, 503, 504)) {
                val h = privateHarness(server)
                val error = failure { h.client.memory.listScopes() }
                assertEquals(status, error.status)
                assertCode("C", error)
                assertEquals(listOf(500L, 1000L), h.sleeps)
            }
            assertEquals(9, server.requestCount)
        }

        @Test
        fun `maxRetries 0 disables retries`() {
            server.enqueue(json("""{"code":"SERVICE_UNAVAILABLE"}""", 503))
            val h = privateHarness(server, maxRetries = 0)
            assertCode("SERVICE_UNAVAILABLE", failure { h.client.memory.listScopes() })
            assertEquals(1, server.requestCount)
            assertEquals(emptyList<Long>(), h.sleeps)
        }

        @Test
        fun `never retries 400, 401, 403, 404 or 500`() {
            for (status in listOf(400, 401, 403, 404, 500)) {
                server.enqueue(json("""{"code":"X"}""", status))
                val h = privateHarness(server)
                assertEquals(status, failure { h.client.memory.listScopes() }.status)
                assertEquals(emptyList<Long>(), h.sleeps)
            }
            assertEquals(5, server.requestCount)
        }

        /** A client whose first [failures] calls fail in the transport, like a reset connection. */
        private fun flaky(failures: Int): Pair<Harness, () -> Int> {
            var calls = 0
            val http = OkHttpClient.Builder().addInterceptor(Interceptor { chain ->
                if (calls++ < failures) throw IOException("connection reset")
                chain.proceed(chain.request())
            }).build()
            return Harness(server, PRIVATE_KEY, viaManifestBaseUrl = false, httpClient = http) to { calls }
        }

        @Test
        fun `retries network errors and reports NETWORK_ERROR when they persist`() {
            val (h, calls) = flaky(3)
            val error = failure { h.client.memory.listScopes() }
            assertCode("NETWORK_ERROR", error)
            assertEquals(0, error.status)
            assertTrue(error.cause is IOException)
            assertEquals(3, calls())
            assertEquals(listOf(500L, 1000L), h.sleeps)
        }

        @Test
        fun `recovers after one network error`() = runBlocking<Unit> {
            server.enqueue(jsonFixture("memory/scopes.json"))
            val (h, calls) = flaky(1)
            assertEquals(3, h.client.memory.listScopes().items.size)
            assertEquals(2, calls())
            assertEquals(listOf(500L), h.sleeps)
        }

        @Test
        fun `reports a refused connection as NETWORK_ERROR`() {
            val port = MockWebServer().run { start(); val p = port; shutdown(); p }
            val sleeps = mutableListOf<Long>()
            val client = NullDullClient(PRIVATE_KEY, WORKSPACE_ID, baseUrl = "http://127.0.0.1:$port", sleep = { sleeps += it })
            assertCode("NETWORK_ERROR", failure { client.memory.listScopes() })
            assertEquals(listOf(500L, 1000L), sleeps)
        }
    }

    @Nested
    inner class `11 timeouts and cancellation` {
        @Test
        fun `raises TIMEOUT and does not retry it`() {
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            val h = Harness(server, PRIVATE_KEY, timeout = 200.milliseconds)
            val error = failure { h.client.memory.listScopes() }
            assertCode("TIMEOUT", error)
            assertEquals(0, error.status)
            assertEquals(1, server.requestCount)
            assertEquals(emptyList<Long>(), h.sleeps)
        }

        @Test
        fun `covers reading the body within the timeout`() {
            server.enqueue(jsonFixture("memory/scopes.json").throttleBody(16, 1, TimeUnit.SECONDS))
            val h = Harness(server, PRIVATE_KEY, timeout = 300.milliseconds)
            assertCode("TIMEOUT", failure { h.client.memory.listScopes() })
            assertEquals(1, server.requestCount)
        }

        @Test
        fun `coroutine cancellation propagates and cancels the HTTP call`() = runBlocking<Unit> {
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            val client = privateHarness(server).client
            val pending = async(Dispatchers.IO) { client.memory.listScopes() }
            withContext(Dispatchers.IO) { server.takeRequest(5, TimeUnit.SECONDS) }
            pending.cancel()
            val thrown = runCatching { pending.await() }.exceptionOrNull()
            assertTrue(thrown is CancellationException, "got $thrown")
            assertEquals(1, server.requestCount)
        }

        @Test
        fun `cancellation during a retry wait stops at once`() = runBlocking<Unit> {
            server.enqueue(json("""{"code":"SERVICE_UNAVAILABLE"}""", 503, "Retry-After" to "30"))
            val client = NullDullClient(PRIVATE_KEY, WORKSPACE_ID, baseUrl = server.url("/").toString())
            val started = System.nanoTime()
            val pending = async(Dispatchers.IO) { client.memory.listScopes() }
            withContext(Dispatchers.IO) { server.takeRequest(5, TimeUnit.SECONDS) }
            Thread.sleep(50)
            pending.cancel()
            assertTrue(runCatching { pending.await() }.exceptionOrNull() is CancellationException)
            assertTrue((System.nanoTime() - started) / 1_000_000 < 5_000)
            assertEquals(1, server.requestCount)
        }

        @Test
        fun `a call cancelled outside the coroutine raises ABORTED without a retry`() = runBlocking<Unit> {
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            val http = OkHttpClient()
            val h = Harness(server, PRIVATE_KEY, viaManifestBaseUrl = false, httpClient = http)
            val pending = async(Dispatchers.IO) { runCatching { h.client.memory.listScopes() }.exceptionOrNull() }
            withContext(Dispatchers.IO) { server.takeRequest(5, TimeUnit.SECONDS) }
            http.dispatcher.cancelAll()
            val error = pending.await() as NullDullException
            assertCode("ABORTED", error)
            assertEquals(0, error.status)
            assertEquals(1, server.requestCount)
        }
    }

    @Nested
    inner class `12 Memory filters` {
        @Test
        fun `sends root for Root, nothing when omitted, and repeated tags`() = runBlocking<Unit> {
            repeat(7) { server.enqueue(json(emptyPage)) }
            val h = privateHarness(server)
            h.client.memory.listAssets(folderId = FolderFilter.Root)
            h.client.memory.listFolders(parentId = FolderFilter.Root)
            h.client.memory.listFolders(parentId = FolderFilter.id("root"))
            h.client.memory.listDocuments()
            h.client.memory.listDocuments(tags = emptyList())
            h.client.memory.listDocuments(folderId = FolderFilter.Id("f1"), tags = listOf("a", "b"))
            h.client.memory.search("release", tags = listOf("x", "y"), kind = FileKind.RULES, lifecycle = FileLifecycle.ONE_TIME)
            assertEquals("folderId=root", h.take().requestUrl!!.encodedQuery)
            assertEquals("parentId=root", h.take().requestUrl!!.encodedQuery)
            assertEquals("parentId=root", h.take().requestUrl!!.encodedQuery)
            assertNull(h.take().requestUrl!!.encodedQuery)
            assertNull(h.take().requestUrl!!.encodedQuery)
            assertEquals("folderId=f1&tag=a&tag=b", h.take().requestUrl!!.encodedQuery)
            assertEquals("q=release&tag=x&tag=y&kind=rules&lifecycle=one-time", h.take().requestUrl!!.encodedQuery)
        }

        @Test
        fun `downloads previews with preview=true and w, and rejects bad widths`() = runBlocking<Unit> {
            server.enqueue(MockResponse().setBody("a"))
            server.enqueue(MockResponse().setBody("b"))
            val h = privateHarness(server)
            h.client.memory.downloadAsset("a1", width = 256)
            h.client.memory.downloadAsset("a1", preview = true)
            assertEquals("preview=true&w=256", h.take().requestUrl!!.encodedQuery)
            assertEquals("preview=true", h.take().requestUrl!!.encodedQuery)
            assertCode("INVALID_ARGUMENT", failure { h.client.memory.downloadAsset("a1", width = 0) })
            assertEquals(2, server.requestCount)
        }

        @Test
        fun `never sends submissionId`() = runBlocking<Unit> {
            server.enqueue(MockResponse().setBody("a"))
            val h = privateHarness(server)
            h.client.memory.downloadAsset("a1", revisionId = "r1", preview = true, width = 64)
            val query = h.take().queryMap()
            assertEquals(setOf("revisionId", "preview", "w"), query.keys)
        }
    }

    @Nested
    inner class `13 Locale export` {
        @Test
        fun `always sends format, comma-joins languages and status, never sends language`() = runBlocking<Unit> {
            repeat(3) { server.enqueue(jsonFixture("locale/export-json.json")) }
            val h = privateHarness(server)
            h.client.locale.export("scope")
            h.client.locale.export("scope", languages = listOf("en", "tr"), status = listOf(LocaleKeyStatus.APPROVED, LocaleKeyStatus.NEEDS_REVIEW), basename = "Localizable")
            h.client.locale.export("scope", format = LocaleFormatId.XCSTRINGS, languages = emptyList(), status = emptyList())
            assertEquals(mapOf("scopeId" to listOf("scope"), "format" to listOf("json")), h.take().queryMap())
            assertEquals(
                mapOf("scopeId" to listOf("scope"), "format" to listOf("json"), "languages" to listOf("en,tr"), "status" to listOf("approved,needs_review"), "basename" to listOf("Localizable")),
                h.take().queryMap(),
            )
            val third = h.take()
            assertEquals(mapOf("scopeId" to listOf("scope"), "format" to listOf("xcstrings")), third.queryMap())
            assertFalse(third.queryMap().containsKey("language"))
        }

        @Test
        fun `rejects list values with commas or empty strings`() {
            val client = privateHarness(server).client
            assertCode("INVALID_ARGUMENT", failure { client.locale.export("scope", languages = listOf("en,tr")) })
            assertCode("INVALID_ARGUMENT", failure { client.locale.export("scope", status = listOf("")) })
            assertEquals(0, server.requestCount)
        }

        @Test
        fun `writes exported files safely`(@TempDir dir: File) = runBlocking<Unit> {
            server.enqueue(jsonFixture("locale/export-android-xml.json"))
            val export = privateHarness(server).client.locale.export("scope", format = LocaleFormatId.ANDROID_XML)
            val written = export.writeTo(dir)
            assertEquals(export.files.size, written.size)
            assertEquals(export.files[0].content, File(dir, export.files[0].path).readText())
            for (bad in listOf("../x.json", "/etc/passwd", "a/../../x", "C:\\x", "")) {
                val unsafe = LocaleExport(Json.parseToJsonElement("""{"files":[{"path":${JsonPrimitive(bad)},"content":"x"}]}""").jsonObject)
                assertCode("INVALID_RESPONSE", failure { unsafe.writeTo(dir) })
            }
        }
    }

    @Nested
    inner class `14 download filenames` {
        @Test
        fun `decodes RFC 5987 filename star and falls back to filename`() {
            assertEquals("brand logo – dark.png", parseFilename("attachment; filename*=UTF-8''brand%20logo%20%E2%80%93%20dark.png"))
            assertEquals("ünï.txt", parseFilename("attachment; filename=\"fallback.txt\"; filename*=UTF-8''%C3%BCn%C3%AF.txt"))
            assertEquals("fallback.txt", parseFilename("attachment; filename*=UTF-8''%E2%80; filename=\"fallback.txt\""))
            assertEquals("fallback.txt", parseFilename("attachment; filename*=UTF-8''%ZZ; filename=\"fallback.txt\""))
            assertEquals("a \"b\".txt", parseFilename("attachment; filename=\"a \\\"b\\\".txt\""))
            assertEquals("plain.txt", parseFilename("attachment; filename=plain.txt"))
            assertEquals("a+b.txt", parseFilename("attachment; filename*=UTF-8''a+b.txt"))
            assertNull(parseFilename("inline"))
            assertNull(parseFilename(""))
            assertNull(parseFilename(null))
        }

        @Test
        fun `downloads report the decoded name, type and size`() = runBlocking<Unit> {
            server.enqueue(
                MockResponse().setHeader("Content-Type", "application/octet-stream")
                    .setHeader("Content-Disposition", "attachment; filename=\"report.pdf\"")
                    .setBody(Buffer().write(ByteArray(10) { it.toByte() })),
            )
            val download = privateHarness(server).client.memory.downloadAsset("a1")
            assertEquals("report.pdf", download.filename)
            assertEquals("application/octet-stream", download.contentType)
            assertEquals(10, download.size)
        }
    }

    @Nested
    inner class `query encoding` {
        @Test
        fun `percent-encodes like encodeURIComponent`() {
            assertEquals("a%20b%2Fc%3F%26%3D%2B%23", encodeUriComponent("a b/c?&=+#"))
            assertEquals("-_.!~*'()", encodeUriComponent("-_.!~*'()"))
            assertEquals("%C3%BC%E2%80%93", encodeUriComponent("ü–"))
            assertEquals("ü– +", decodeUriComponent("%C3%BC%E2%80%93%20+"))
        }

        @Test
        fun `sends special characters intact`() = runBlocking<Unit> {
            server.enqueue(jsonFixture("memory/resolve-link-found.json"))
            val h = privateHarness(server)
            h.client.memory.resolveLink("doc", "a b/c.md?x=1&y=2#frag+ü")
            assertEquals(listOf("a b/c.md?x=1&y=2#frag+ü"), h.take().queryMap()["href"])
        }
    }
}
