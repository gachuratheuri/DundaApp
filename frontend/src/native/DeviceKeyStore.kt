package com.dunda.scanner

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature

/** Android Keystore-backed Ed25519 signer; private material never enters JS. */
class DeviceKeyStore(private val alias: String = "dunda-ticket-device-v2") {
    private val keyPair: KeyPair by lazy { loadOrCreate() }

    fun publicKey(): ByteArray = keyPair.public.encoded.takeLast(32).toByteArray()

    fun sign(payload: ByteArray): ByteArray = Signature.getInstance("Ed25519").run {
        initSign(keyPair.private)
        update(payload)
        sign()
    }

    private fun loadOrCreate(): KeyPair {
        val generator = KeyPairGenerator.getInstance("Ed25519", "AndroidKeyStore")
        return try {
            generator.initialize(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY).build())
            generator.generateKeyPair()
        } catch (_: Exception) {
            val store = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val entry = store.getEntry(alias, null) as? java.security.KeyStore.PrivateKeyEntry
            requireNotNull(entry) { "unable to provision device signing key" }.let { KeyPair(it.certificate.publicKey, it.privateKey) }
        }
    }
}
