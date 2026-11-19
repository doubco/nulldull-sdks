package com.nulldull.sdk

import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

/**
 * Optional live tests against a real NullDull API, skipped unless the variables are set:
 *
 * - `NULLDULL_PUBLIC_KEY` + `NULLDULL_GRID_POOL`: Grid delivery
 * - `NULLDULL_PRIVATE_KEY` + `NULLDULL_WORKSPACE_ID`: Memory and Locale
 * - `NULLDULL_LOCALE_SCOPE_ID` (optional): Locale export location, default the workspace root
 * - `NULLDULL_BASE_URL` (optional): default https://nulldull.com
 *
 * Never print key values: assertion messages below never include them.
 */
class LiveTest {
    private fun env(name: String): String? = System.getenv(name)?.takeIf { it.isNotBlank() }
    private val baseUrl get() = env("NULLDULL_BASE_URL") ?: DEFAULT_BASE_URL

    @Nested
    inner class Grid {
        private fun client(): NullDullClient {
            assumeTrue(env("NULLDULL_PUBLIC_KEY") != null && env("NULLDULL_GRID_POOL") != null, "NULLDULL_PUBLIC_KEY and NULLDULL_GRID_POOL not set")
            return NullDullClient(apiKey = env("NULLDULL_PUBLIC_KEY")!!, baseUrl = baseUrl, userAgent = "live-test")
        }
        private val pool get() = env("NULLDULL_GRID_POOL")!!

        @Test
        fun `lists, iterates and reads published pages`() = runBlocking<Unit> {
            val client = client()
            val list = client.grid.listPages(pool, limit = 2)
            assertEquals(pool, list.pool.key)
            assertTrue(list.items.size <= 2)
            val iterated = client.grid.iteratePages(pool, limit = 2).take(5).toList()
            assertTrue(iterated.all { it.slug.isNotEmpty() })
            val first = list.items.firstOrNull() ?: return@runBlocking
            val page = client.grid.getPage(pool, first.slug, locale = first.locale)
            assertEquals(first.id, page.id)
            assertTrue((page.document as JsonObject)["nodes"] is JsonArray)
            for (asset in page.assets) {
                assertTrue(asset.url.startsWith("http"))
                assertTrue(asset.url.contains("key="), "public-key asset URLs on the API origin carry key=")
            }
            page.cover?.let { cover ->
                val download = client.grid.downloadAsset(cover)
                assertEquals(cover.byteSize, download.size.toLong())
            }
        }

        @Test
        fun `raises NOT_FOUND for a missing page`() {
            val client = client()
            val error = failure { client.grid.getPage(pool, "nulldull-sdk-live-test-missing-page") }
            assertEquals(404, error.status)
            assertEquals("NOT_FOUND", error.code)
        }

        @Test
        fun `refuses the platform API for a public key`() {
            client()
            val error = failure { NullDullClient(env("NULLDULL_PUBLIC_KEY")!!, workspaceId = "w", baseUrl = baseUrl).memory.listScopes() }
            assertEquals("PRIVATE_KEY_REQUIRED", error.code)
        }
    }

    @Nested
    inner class Platform {
        private fun client(): NullDullClient {
            assumeTrue(env("NULLDULL_PRIVATE_KEY") != null && env("NULLDULL_WORKSPACE_ID") != null, "NULLDULL_PRIVATE_KEY and NULLDULL_WORKSPACE_ID not set")
            return NullDullClient(env("NULLDULL_PRIVATE_KEY")!!, workspaceId = env("NULLDULL_WORKSPACE_ID"), baseUrl = baseUrl, userAgent = "live-test")
        }

        /** A key without memory:read or locale:read gets 403: a configuration, not an SDK, failure. */
        private suspend fun <T> tolerateForbidden(block: suspend () -> T): T? = try {
            block()
        } catch (e: NullDullException) {
            if (e.code == "FORBIDDEN") null else throw e
        }

        @Test
        fun `lists scopes, documents, search and tags`() = runBlocking<Unit> {
            val client = client()
            val scopes = tolerateForbidden { client.memory.listScopes() } ?: return@runBlocking
            assertTrue(scopes.items.any { it.id == env("NULLDULL_WORKSPACE_ID") })
            val documents = client.memory.listDocuments()
            documents.items.firstOrNull()?.let { assertEquals(it.id, client.memory.getDocument(it.id).id) }
            client.memory.search("the")
            client.memory.iterateTags().take(5).toList()

        }

        @Test
        fun `lists Locale formats and exports`() = runBlocking<Unit> {
            val client = client()
            val formats = tolerateForbidden { client.locale.listFormats() } ?: return@runBlocking
            assertTrue(formats.items.any { it.id == "json" })
            val exported = tolerateForbidden { client.locale.export(env("NULLDULL_LOCALE_SCOPE_ID") ?: env("NULLDULL_WORKSPACE_ID")!!) }
            if (exported != null) assertEquals("json", exported.format)
        }
    }
}
