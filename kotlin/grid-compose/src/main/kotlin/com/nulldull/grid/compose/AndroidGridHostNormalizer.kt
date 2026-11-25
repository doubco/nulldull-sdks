package com.nulldull.grid.compose

import android.icu.text.IDNA
import com.nulldull.grid.GridHostNormalizer

/** Installed by grid-compose for both document decoding and link rendering. */
internal class AndroidGridHostNormalizer : GridHostNormalizer {
    private val idna = IDNA.getUTS46Instance(IDNA.NONTRANSITIONAL_TO_ASCII or IDNA.CHECK_BIDI or IDNA.CHECK_CONTEXTJ)

    override fun toAscii(host: String): String? {
        val info = IDNA.Info()
        val ascii = idna.nameToASCII(host, StringBuilder(), info).toString()
        // Browser URL processing disables hyphen and DNS length checks.
        return ascii.takeUnless { info.errors.any { it !in nonStrictErrors } }
    }

    private val nonStrictErrors = setOf(
        IDNA.Error.LEADING_HYPHEN, IDNA.Error.TRAILING_HYPHEN, IDNA.Error.HYPHEN_3_4,
        IDNA.Error.EMPTY_LABEL, IDNA.Error.LABEL_TOO_LONG, IDNA.Error.DOMAIN_NAME_TOO_LONG,
    )
}
