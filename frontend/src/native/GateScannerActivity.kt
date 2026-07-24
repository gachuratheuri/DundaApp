package com.dunda.scanner

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import android.widget.Toast
import android.util.Base64
import org.json.JSONObject

/**
 * Dedicated scanner entry point. DeviceDataWedge integration is intentionally
 * isolated from the protocol verifier so hardware replacement cannot weaken
 * cryptographic or replay guarantees.
 */
class GateScannerActivity : AppCompatActivity() {
    private lateinit var session: GateScannerSession

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        session = GateScannerSession(ManifestTrustStore.loadPinnedKey(this))
        // setContentView(R.layout.activity_gate_scanner)

        initializeScannerHardware()
    }

    private fun initializeScannerHardware() {
        Toast.makeText(this, "Dunda Gate Scanner ready (coordinator mode)", Toast.LENGTH_SHORT).show()
    }

    /** Called by the authenticated coordinator client after ManifestVerifier succeeds. */
    fun installManifest(
        canonicalPayload: ByteArray,
        signature: ByteArray,
    ): Boolean = session.installManifest(canonicalPayload, signature)

    fun onBarcodeScanned(payload: String) {
        val decision = try {
            val proof = JSONObject(payload)
            val rawNonce = Base64.decode(proof.getString("nonce"), Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            val rawKey = Base64.decode(proof.getString("credential_public_key"), Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            val signature = Base64.decode(proof.getString("signature"), Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            session.verify(TicketProofVerifier.Proof(proof.getString("ticket_id"), proof.getString("event_id"), proof.getLong("time_step"), rawNonce, rawKey, signature))
        } catch (_: Exception) {
            GateScannerSession.Decision.INVALID
        }
        when (decision) {
            GateScannerSession.Decision.ADMIT -> Toast.makeText(this, "ADMIT — coordinator confirmation required", Toast.LENGTH_SHORT).show()
            GateScannerSession.Decision.REPLAY -> Toast.makeText(this, "REJECT — replayed proof", Toast.LENGTH_SHORT).show()
            GateScannerSession.Decision.CLOCK_DRIFT -> Toast.makeText(this, "HOLD — scanner clock drift", Toast.LENGTH_SHORT).show()
            GateScannerSession.Decision.HOLD_MANIFEST -> Toast.makeText(this, "HOLD — signed event manifest required", Toast.LENGTH_SHORT).show()
            GateScannerSession.Decision.REVOKED -> Toast.makeText(this, "REJECT — revoked credential", Toast.LENGTH_SHORT).show()
            GateScannerSession.Decision.INVALID -> Toast.makeText(this, "REJECT — invalid credential", Toast.LENGTH_SHORT).show()
        }
    }
}
