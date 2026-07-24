package com.dunda.scanner

import java.time.Instant
import android.util.Base64
import org.json.JSONObject

/**
 * Manifest-gated scanner state. A proof is never treated as an admission
 * decision until the signed, time-bounded event manifest contains the ticket
 * key and does not list the ticket as revoked.
 */
class GateScannerSession(private val trustedManifestPublicKey: ByteArray) {
    data class TicketKey(val ticketId: String, val eventId: String, val publicKey: ByteArray, val epoch: Int)
    data class Revocation(val ticketId: String, val epoch: Int)

    enum class Decision { ADMIT, HOLD_MANIFEST, REVOKED, REPLAY, INVALID, CLOCK_DRIFT }

    private var eventId: String? = null
    private var manifestVersion: Int = 0
    private var validFrom: Long = 0
    private var validUntil: Long = 0
    private var keys: Map<String, TicketKey> = emptyMap()
    private var revocations: Map<String, Int> = emptyMap()

    fun installManifest(
        canonicalPayload: ByteArray,
        signature: ByteArray,
        nowSeconds: Long = Instant.now().epochSecond,
    ): Boolean {
        if (!ManifestVerifier.verify(canonicalPayload, trustedManifestPublicKey, signature)) return false
        val document = try {
            JSONObject(canonicalPayload.toString(Charsets.UTF_8))
        } catch (_: Exception) {
            return false
        }
        if (document.optString("protocol") != "dunda-scanner-manifest" || document.optInt("protocol_version") != 2) return false

        val payload = document.optJSONObject("payload") ?: return false
        val eventId = document.opt("event_id")?.toString() ?: return false
        val version = document.optInt("version", 0)
        if (version <= 0 || (this.eventId == eventId && version < manifestVersion)) return false
        if (payload.opt("event_id")?.toString() != eventId) return false
        val validFrom = parseInstant(document.optString("valid_from")) ?: return false
        val validUntil = parseInstant(document.optString("valid_until")) ?: return false
        if (validUntil <= validFrom || nowSeconds < validFrom || nowSeconds >= validUntil) return false

        val ticketKeys = try {
            val rows = payload.getJSONArray("tickets")
            (0 until rows.length()).map { index ->
                val row = rows.getJSONObject(index)
                TicketKey(
                    row.getString("ticket_id"),
                    eventId,
                    decode(row.getString("credential_public_key")),
                    row.getInt("credential_epoch"),
                )
            }
        } catch (_: Exception) {
            return false
        }

        val ticketRevocations = try {
            val rows = payload.getJSONArray("revocations")
            (0 until rows.length()).map { index ->
                val row = rows.getJSONObject(index)
                Revocation(row.getString("ticket_id"), row.getInt("credential_epoch"))
            }
        } catch (_: Exception) {
            return false
        }

        this.eventId = eventId
        this.manifestVersion = version
        this.validFrom = validFrom
        this.validUntil = validUntil
        this.keys = ticketKeys.associateBy { it.ticketId }
        this.revocations = ticketRevocations.associate { it.ticketId to it.epoch }
        return true
    }

    private fun parseInstant(value: String): Long? = try {
        Instant.parse(value).epochSecond
    } catch (_: Exception) {
        null
    }

    private fun decode(value: String): ByteArray =
        Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)

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
