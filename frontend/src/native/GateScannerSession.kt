package com.dunda.scanner

import java.time.Instant

/**
 * Manifest-gated scanner state. A proof is never treated as an admission
 * decision until the signed, time-bounded event manifest contains the ticket
 * key and does not list the ticket as revoked.
 */
class GateScannerSession {
    data class TicketKey(val ticketId: String, val eventId: String, val publicKey: ByteArray, val epoch: Int)
    data class Revocation(val ticketId: String, val epoch: Int)

    enum class Decision { ADMIT, HOLD_MANIFEST, REVOKED, REPLAY, INVALID, CLOCK_DRIFT }

    private var eventId: String? = null
    private var validFrom: Long = 0
    private var validUntil: Long = 0
    private var keys: Map<String, TicketKey> = emptyMap()
    private var revocations: Map<String, Int> = emptyMap()

    fun installManifest(
        eventId: String,
        canonicalPayload: ByteArray,
        signature: ByteArray,
        manifestPublicKey: ByteArray,
        validFrom: Long,
        validUntil: Long,
        ticketKeys: List<TicketKey>,
        ticketRevocations: List<Revocation>,
        nowSeconds: Long = Instant.now().epochSecond,
    ): Boolean {
        if (!ManifestVerifier.verify(canonicalPayload, manifestPublicKey, signature)) return false
        if (validUntil <= validFrom || nowSeconds < validFrom || nowSeconds >= validUntil) return false
        this.eventId = eventId
        this.validFrom = validFrom
        this.validUntil = validUntil
        this.keys = ticketKeys.associateBy { it.ticketId }
        this.revocations = ticketRevocations.associate { it.ticketId to it.epoch }
        return true
    }

    fun verify(proof: TicketProofVerifier.Proof, nowSeconds: Long = Instant.now().epochSecond): Decision {
        val currentEvent = eventId ?: return Decision.HOLD_MANIFEST
        if (nowSeconds < validFrom || nowSeconds >= validUntil || currentEvent != proof.eventId) return Decision.HOLD_MANIFEST
        val key = keys[proof.ticketId] ?: return Decision.HOLD_MANIFEST
        val revokedEpoch = revocations[proof.ticketId]
        if (revokedEpoch != null && revokedEpoch >= key.epoch) return Decision.REVOKED
        if (!key.publicKey.contentEquals(proof.credentialPublicKey)) return Decision.INVALID
        return when (TicketProofVerifier.verify(proof, nowSeconds)) {
            TicketProofVerifier.Decision.ADMIT -> Decision.ADMIT
            TicketProofVerifier.Decision.REPLAY -> Decision.REPLAY
            TicketProofVerifier.Decision.CLOCK_DRIFT -> Decision.CLOCK_DRIFT
            TicketProofVerifier.Decision.INVALID -> Decision.INVALID
        }
    }
}
