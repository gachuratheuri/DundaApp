package com.dunda.scanner

import java.nio.charset.StandardCharsets
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs

/**
 * Protocol-v2 verifier used by the venue-local coordinator/scanner app.
 * Admission uniqueness is deliberately delegated to the coordinator; this
 * class only proves authenticity, freshness, and local replay absence.
 */
object TicketProofVerifier {
    private const val PERIOD_SECONDS = 30L
    private const val MAX_DRIFT_STEPS = 1L
    private val seenNonces = ConcurrentHashMap<String, Long>()

    data class Proof(
        val ticketId: String,
        val eventId: String,
        val timeStep: Long,
        val nonce: ByteArray,
        val credentialPublicKey: ByteArray,
        val signature: ByteArray,
    )

    enum class Decision { ADMIT, REPLAY, INVALID, CLOCK_DRIFT }

    fun verify(proof: Proof, nowSeconds: Long = System.currentTimeMillis() / 1000): Decision {
        if (proof.nonce.size !in 16..64 || proof.credentialPublicKey.size != 32 || proof.signature.size != 64) return Decision.INVALID
        val currentStep = nowSeconds / PERIOD_SECONDS
        if (abs(proof.timeStep - currentStep) > MAX_DRIFT_STEPS) return Decision.CLOCK_DRIFT
        val replayKey = "${proof.ticketId}:${b64(proof.nonce)}"
        if (seenNonces.putIfAbsent(replayKey, nowSeconds) != null) return Decision.REPLAY
        return if (verifyEd25519(proof.credentialPublicKey, canonical(proof), proof.signature)) Decision.ADMIT else {
            seenNonces.remove(replayKey)
            Decision.INVALID
        }
    }

    fun canonical(proof: Proof): ByteArray = listOf(
        "dunda-ticket-proof", "v=2", "ticket_id=${proof.ticketId}",
        "event_id=${proof.eventId}", "time_step=${proof.timeStep}",
        "nonce=${b64(proof.nonce)}", "credential_public_key=${b64(proof.credentialPublicKey)}"
    ).joinToString("\n").toByteArray(StandardCharsets.UTF_8)

    fun clearExpired(nowSeconds: Long = System.currentTimeMillis() / 1000) {
        seenNonces.entries.removeIf { nowSeconds - it.value > PERIOD_SECONDS * 4 }
    }

    private fun verifyEd25519(rawPublicKey: ByteArray, payload: ByteArray, signatureBytes: ByteArray): Boolean = try {
        val key = KeyFactory.getInstance("Ed25519").generatePublic(X509EncodedKeySpec(ED25519_X509_PREFIX + rawPublicKey))
        Signature.getInstance("Ed25519").run {
            initVerify(key)
            update(payload)
            verify(signatureBytes)
        }
    } catch (_: Exception) { false }

    private fun b64(value: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(value)
    private val ED25519_X509_PREFIX = byteArrayOf(0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00)
}
