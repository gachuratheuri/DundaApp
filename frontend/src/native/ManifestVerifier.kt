package com.dunda.scanner

import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec

/** Verifies the venue manifest signature before any ticket data is trusted. */
object ManifestVerifier {
    private val ED25519_X509_PREFIX = byteArrayOf(0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00)

    fun verify(canonicalManifest: ByteArray, rawPublicKey: ByteArray, signature: ByteArray): Boolean = try {
        require(rawPublicKey.size == 32 && signature.size == 64)
        val key = KeyFactory.getInstance("Ed25519").generatePublic(X509EncodedKeySpec(ED25519_X509_PREFIX + rawPublicKey))
        Signature.getInstance("Ed25519").run {
            initVerify(key)
            update(canonicalManifest)
            verify(signature)
        }
    } catch (_: Exception) { false }
}
