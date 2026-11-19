package com.nulldull.sdk

import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.util.Base64

/** Runs every case in fixtures/manifest.json (SPEC.md section 11). */
class ConformanceTest {

    @TestFactory
    fun manifestCases(): List<DynamicTest> = manifest["cases"]!!.jsonArray.map { element ->
        val case = element.jsonObject
        DynamicTest.dynamicTest(case["id"]!!.jsonPrimitive.content) { run(case) }
    }

    private fun run(case: JsonObject) {
        val server = MockWebServer()
        server.start()
        try {
            val exchanges = case["exchanges"]!!.jsonArray.map { it.jsonObject }
            exchanges.forEach { server.enqueue(response(it["response"]!!.jsonObject)) }
            val key = if (case["key"]!!.jsonPrimitive.content == "public") PUBLIC_KEY else PRIVATE_KEY
            val harness = Harness(server, key)
            val call = case["call"]!!.jsonObject
            val expect = case["expect"]!!.jsonObject

            val outcome = runCatching { runBlocking { invoke(harness.client, call["method"]!!.jsonPrimitive.content, call["args"]!!.jsonArray) } }

            val attempts = expect["attempts"]?.jsonPrimitive?.int ?: exchanges.size
            assertEquals(attempts, server.requestCount, "attempts")
            for (exchange in exchanges.take(attempts)) {
                val expected = exchange["request"]!!.jsonObject
                val recorded = harness.take()
                assertEquals(expected["method"]!!.jsonPrimitive.content, recorded.method)
                assertEquals(expected["path"]!!.jsonPrimitive.content, recorded.requestUrl!!.encodedPath)
                val query = expected["query"]!!.jsonObject.mapValues { (_, v) -> v.jsonArray.map { it.jsonPrimitive.content }.sorted() }
                assertEquals(query, recorded.queryMap().mapValues { it.value.sorted() }, "query")
            }
            expect["sleeps"]?.let { sleeps -> assertEquals(sleeps.jsonArray.map { it.jsonPrimitive.long }, harness.sleeps, "sleeps") }

            when {
                "error" in expect -> {
                    val error = outcome.exceptionOrNull() as? NullDullException
                        ?: throw AssertionError("Expected a NullDullException, got $outcome", outcome.exceptionOrNull())
                    checkError(expect["error"]!!.jsonObject, error)
                }
                else -> {
                    val result = outcome.getOrThrow()
                    when {
                        "resultFile" in expect -> checkResult(expect, (result as JsonModel).json)
                        "itemCount" in expect -> {
                            val items = JsonArray((result as List<*>).map { (it as JsonModel).json })
                            assertEquals(expect["itemCount"]!!.jsonPrimitive.int, items.size, "itemCount")
                            checks(expect, items)
                        }
                        "download" in expect -> checkDownload(expect["download"]!!.jsonObject, result as Download)
                        else -> throw AssertionError("Unknown expectation in ${case["id"]}")
                    }
                }
            }
        } finally {
            server.shutdown()
        }
    }

    private fun response(spec: JsonObject): MockResponse {
        val response = MockResponse().setResponseCode(spec["status"]!!.jsonPrimitive.int)
        spec["headers"]?.jsonObject?.forEach { (name, value) ->
            if (!name.equals("content-length", ignoreCase = true)) response.setHeader(name, value.jsonPrimitive.content)
        }
        when {
            "bodyFile" in spec -> response.setBody(fixtureText(spec["bodyFile"]!!.jsonPrimitive.content))
            "body" in spec -> response.setBody(spec["body"]!!.jsonPrimitive.content)
            "bodyBase64" in spec -> response.setBody(Buffer().write(Base64.getDecoder().decode(spec["bodyBase64"]!!.jsonPrimitive.content)))
        }
        return response
    }

    private fun checkResult(expect: JsonObject, actual: JsonElement) {
        val except = expect["except"]?.jsonArray?.map { it.jsonPrimitive.content } ?: emptyList()
        var expected = fixture(expect["resultFile"]!!.jsonPrimitive.content)
        var got = actual
        for (path in except) {
            expected = remove(expected, path.split('.'))
            got = remove(got, path.split('.'))
        }
        assertEquals(expected, got, "result")
        checks(expect, actual)
    }

    private fun checks(expect: JsonObject, actual: JsonElement) {
        expect["checks"]?.jsonArray?.forEach { check ->
            val path = check.jsonObject["path"]!!.jsonPrimitive.content
            assertEquals(check.jsonObject["equals"], at(actual, path.split('.')), path)
        }
    }

    private fun checkError(expected: JsonObject, error: NullDullException) {
        for ((field, value) in expected) {
            when (field) {
                "status" -> assertEquals(value.jsonPrimitive.int, error.status, "status")
                "code" -> assertEquals(value.jsonPrimitive.content, error.code, "code")
                "message" -> assertEquals(value.jsonPrimitive.content, error.message, "message")
                "detail" -> assertEquals(value.stringOrNull(), error.detail, "detail")
                "requestId" -> assertEquals(value.stringOrNull(), error.requestId, "requestId")
                "retryAfter" -> assertEquals((value as? JsonPrimitive)?.takeIf { it !is JsonNull }?.long, error.retryAfter, "retryAfter")
                "body" -> {
                    val body = error.body ?: throw AssertionError("Expected an error body")
                    for ((k, v) in value.jsonObject) assertEquals(v, body[k], "body.$k")
                }
                else -> throw AssertionError("Unknown error field $field")
            }
        }
    }

    private fun checkDownload(expected: JsonObject, download: Download) {
        assertEquals(expected["contentType"]!!.stringOrNull(), download.contentType, "contentType")
        assertEquals(expected["filename"]!!.stringOrNull(), download.filename, "filename")
        assertEquals(expected["size"]!!.jsonPrimitive.int, download.size, "size")
        assertArrayEquals(Base64.getDecoder().decode(expected["bytesBase64"]!!.jsonPrimitive.content), download.bytes)
    }

    private fun JsonElement.stringOrNull(): String? = if (this is JsonNull) null else jsonPrimitive.content

    private fun at(element: JsonElement, path: List<String>): JsonElement = path.fold(element) { node, segment ->
        when (node) {
            is JsonArray -> node[segment.toInt()]
            is JsonObject -> node[segment] ?: throw AssertionError("Missing $segment in $path")
            else -> throw AssertionError("Cannot index $segment in $path")
        }
    }

    private fun remove(element: JsonElement, path: List<String>): JsonElement {
        val head = path.first()
        val rest = path.drop(1)
        return when (element) {
            is JsonObject -> JsonObject(
                if (rest.isEmpty()) element - head else element.mapValues { (k, v) -> if (k == head) remove(v, rest) else v },
            )
            is JsonArray -> JsonArray(
                element.mapIndexedNotNull { i, v ->
                    if (i == head.toInt()) (if (rest.isEmpty()) null else remove(v, rest)) else v
                },
            )
            else -> element
        }
    }

    // --- Mapping canonical calls onto the Kotlin API ---------------------------------------------

    private suspend fun invoke(client: NullDullClient, method: String, args: JsonArray): Any {
        val o = Options(args)
        return when (method) {
            "grid.listPages" -> client.grid.listPages(
                o.str(0), locale = o.opt(1, "locale") ?: DEFAULT_LOCALE, q = o.opt(1, "q"), folderId = o.opt(1, "folderId"),
                limit = o.int(1, "limit"), after = o.opt(1, "after"),
            )
            "grid.iteratePages" -> client.grid.iteratePages(
                o.str(0), locale = o.opt(1, "locale") ?: DEFAULT_LOCALE, q = o.opt(1, "q"), folderId = o.opt(1, "folderId"),
                limit = o.int(1, "limit"), after = o.opt(1, "after"),
            ).toList()
            "grid.getPage" -> client.grid.getPage(o.str(0), o.str(1), locale = o.opt(2, "locale") ?: DEFAULT_LOCALE)
            "memory.listScopes" -> client.memory.listScopes(after = o.opt(0, "after"))
            "memory.listFolders" -> client.memory.listFolders(o.opt(0, "scopeId"), o.folder(0, "parentId"), o.opt(0, "after"))
            "memory.getFolder" -> client.memory.getFolder(o.str(0))
            "memory.listDocuments" -> client.memory.listDocuments(
                o.opt(0, "scopeId"), o.folder(0, "folderId"), o.list(0, "tags"), o.opt(0, "kind"), o.opt(0, "lifecycle"), o.opt(0, "after"),
            )
            "memory.iterateDocuments" -> client.memory.iterateDocuments(
                o.opt(0, "scopeId"), o.folder(0, "folderId"), o.list(0, "tags"), o.opt(0, "kind"), o.opt(0, "lifecycle"), o.opt(0, "after"),
            ).toList()
            "memory.getDocument" -> client.memory.getDocument(o.str(0))
            "memory.resolveLink" -> client.memory.resolveLink(o.str(0), o.str(1))
            "memory.search" -> client.memory.search(
                o.str(0), o.opt(1, "scopeId"), o.list(1, "tags"), o.opt(1, "kind"), o.opt(1, "lifecycle"), o.opt(1, "after"),
            )
            "memory.iterateTags" -> client.memory.iterateTags(o.opt(0, "scopeId"), o.opt(0, "q"), o.opt(0, "after")).toList()
            "memory.listTags" -> client.memory.listTags(o.opt(0, "scopeId"), o.opt(0, "q"), o.opt(0, "after"))
            "memory.listAssets" -> client.memory.listAssets(
                o.opt(0, "scopeId"), o.folder(0, "folderId"), o.opt(0, "q"), o.list(0, "tags"), o.opt(0, "after"),
            )
            "memory.getAsset" -> client.memory.getAsset(o.str(0), o.opt(1, "revisionId"))
            "memory.listAssetVersions" -> client.memory.listAssetVersions(o.str(0), o.opt(1, "after"))
            "memory.downloadAsset" -> client.memory.downloadAsset(
                o.str(0), o.opt(1, "revisionId"), o.bool(1, "preview"), o.int(1, "width"),
            )
            "locale.listFormats" -> client.locale.listFormats()
            "locale.export" -> client.locale.export(
                o.str(0), o.opt(1, "format") ?: LocaleFormatId.JSON, o.list(1, "languages"), o.list(1, "status"), o.opt(1, "basename"),
            )
            else -> throw AssertionError("Unmapped method $method")
        }
    }

    private class Options(private val args: JsonArray) {
        private fun obj(i: Int) = args.getOrNull(i) as? JsonObject ?: JsonObject(emptyMap())
        fun str(i: Int) = args[i].jsonPrimitive.content
        fun opt(i: Int, name: String) = (obj(i)[name] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
        fun int(i: Int, name: String) = (obj(i)[name] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.int
        fun bool(i: Int, name: String) = (obj(i)[name] as? JsonPrimitive)?.content == "true"
        fun list(i: Int, name: String) = (obj(i)[name] as? JsonArray)?.map { it.jsonPrimitive.content }

        /** Canonical folder filters: absent = no filter, null = root, a string = that folder. */
        fun folder(i: Int, name: String): FolderFilter? {
            val o = obj(i)
            if (name !in o) return null
            val value = o[name]
            return if (value is JsonNull) FolderFilter.Root else FolderFilter.Id(value!!.jsonPrimitive.content)
        }
    }

    init {
        assertTrue(fixturesDir.isDirectory, "Fixtures not found at $fixturesDir")
    }
}
