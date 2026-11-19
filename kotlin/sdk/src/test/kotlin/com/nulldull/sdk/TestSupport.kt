package com.nulldull.sdk

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.fail
import java.io.File
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** The shared fixtures directory (`../fixtures`), passed in by Gradle. */
val fixturesDir: File = File(System.getProperty("nulldull.fixtures") ?: "../../fixtures")

fun fixtureText(path: String): String = File(fixturesDir, path).readText()

fun fixture(path: String): JsonElement = Json.parseToJsonElement(fixtureText(path))

val manifest: JsonObject by lazy { fixture("manifest.json").jsonObject }

private val config: JsonObject get() = manifest["config"]!!.jsonObject
val PUBLIC_KEY: String get() = config["publicKey"]!!.jsonPrimitive.content
val PRIVATE_KEY: String get() = config["privateKey"]!!.jsonPrimitive.content
val WORKSPACE_ID: String get() = config["workspaceId"]!!.jsonPrimitive.content
val MANIFEST_BASE_URL: String get() = config["baseUrl"]!!.jsonPrimitive.content

fun json(body: String, status: Int = 200, vararg headers: Pair<String, String>): MockResponse =
    MockResponse().setResponseCode(status).setHeader("Content-Type", "application/json").setBody(body).apply {
        headers.forEach { (name, value) -> setHeader(name, value) }
    }

fun jsonFixture(path: String, status: Int = 200, vararg headers: Pair<String, String>): MockResponse =
    json(fixtureText(path), status, *headers)

/**
 * Sends requests for [MANIFEST_BASE_URL]'s origin (https://nulldull.com) to [server] instead, so the
 * client keeps its real base URL (and asset URLs stay `https://nulldull.com/...`) while every
 * request still goes over HTTP to the mock server.
 */
fun rewritingClient(server: MockWebServer): OkHttpClient = OkHttpClient.Builder()
    .addInterceptor(Interceptor { chain ->
        val request = chain.request()
        if (request.url.host == "nulldull.com") {
            val url = request.url.newBuilder().scheme("http").host(server.hostName).port(server.port).build()
            chain.proceed(request.newBuilder().url(url).header("X-Original-Url", request.url.toString()).build())
        } else {
            chain.proceed(request)
        }
    })
    .build()

/** A client against the mock server, recording retry sleeps instead of waiting. */
class Harness(
    val server: MockWebServer,
    key: String,
    workspaceId: String? = WORKSPACE_ID,
    viaManifestBaseUrl: Boolean = true,
    timeout: Duration = 30.seconds,
    maxRetries: Int = 2,
    userAgent: String? = null,
    httpClient: OkHttpClient? = null,
) {
    val sleeps = mutableListOf<Long>()
    val client = NullDullClient(
        apiKey = key,
        workspaceId = workspaceId,
        baseUrl = if (viaManifestBaseUrl) MANIFEST_BASE_URL else server.url("/").toString(),
        timeout = timeout,
        maxRetries = maxRetries,
        httpClient = httpClient ?: if (viaManifestBaseUrl) rewritingClient(server) else null,
        userAgent = userAgent,
        sleep = { sleeps += it },
    )

    fun take(): RecordedRequest = server.takeRequest(5, java.util.concurrent.TimeUnit.SECONDS)
        ?: fail("Expected another request")
}

fun publicHarness(server: MockWebServer, maxRetries: Int = 2) = Harness(server, PUBLIC_KEY, maxRetries = maxRetries)
fun privateHarness(server: MockWebServer, maxRetries: Int = 2) = Harness(server, PRIVATE_KEY, maxRetries = maxRetries)

/** Runs [block] and returns the [NullDullException] it throws. */
fun failure(block: suspend () -> Any?): NullDullException = runBlocking {
    try {
        block()
    } catch (e: NullDullException) {
        return@runBlocking e
    }
    fail("Expected a NullDullException")
}

fun assertCode(code: String, error: NullDullException) = assertEquals(code, error.code, error.toString())

/** Decoded query parameters as a multimap. */
fun RecordedRequest.queryMap(): Map<String, List<String>> {
    val url = requestUrl!!
    return url.queryParameterNames.associateWith { name -> url.queryParameterValues(name).map { it ?: "" } }
}
