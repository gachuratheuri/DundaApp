package com.dunda.scanner

import android.content.Context
import android.content.pm.PackageManager
import android.util.Base64

/**
 * Loads the manifest verification key pinned into the signed application
 * package. It is never accepted from the manifest response itself.
 */
object ManifestTrustStore {
    private const val META_DATA_KEY = "com.dunda.SCANNER_MANIFEST_PUBLIC_KEY"

    fun loadPinnedKey(context: Context): ByteArray {
        val info = context.packageManager.getApplicationInfo(
            context.packageName,
            PackageManager.GET_META_DATA,
        )
        val encoded = requireNotNull(info.metaData?.getString(META_DATA_KEY)) {
            "scanner manifest trust anchor is not configured"
        }
        val key = Base64.decode(encoded, Base64.DEFAULT)
        require(key.size == 32) { "scanner manifest trust anchor must be 32 bytes" }
        return key
    }
}
