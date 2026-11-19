package com.nulldull.sdk

/**
 * A downloaded file held in memory.
 *
 * @property bytes The whole response body.
 * @property contentType The `Content-Type` header. Memory downloads that are not previews are always
 *   `application/octet-stream`; the real media type is in [Asset.assetObject].
 * @property filename From `Content-Disposition` (RFC 5987 `filename*` preferred), or null. Resized
 *   previews have no file name.
 */
public class Download(
    public val bytes: ByteArray,
    public val contentType: String?,
    public val filename: String?,
) {
    /** The byte length of [bytes]. */
    public val size: Int get() = bytes.size

    override fun equals(other: Any?): Boolean =
        other is Download && bytes.contentEquals(other.bytes) && contentType == other.contentType && filename == other.filename

    override fun hashCode(): Int = (bytes.contentHashCode() * 31 + contentType.hashCode()) * 31 + filename.hashCode()

    override fun toString(): String = "Download(size=$size, contentType=$contentType, filename=$filename)"
}
