package com.safenet.vpn

import android.content.Context
import android.os.ParcelFileDescriptor
import kotlinx.coroutines.*

class AmneziaEngine(private val context: Context) {

    private var tunnelHandle: Long = -1
    private var isConnected = false

    companion object {
        init {
            try {
                System.loadLibrary("amneziawg")
            } catch (e: UnsatisfiedLinkError) {
                android.util.Log.e("AmneziaEngine", "Native library not found: ${e.message}")
            }
        }

        @JvmStatic private external fun wgTurnOn(ifaceName: String, tunFd: Int, settings: String): Long
        @JvmStatic private external fun wgTurnOff(handle: Long)
        @JvmStatic private external fun wgGetConfig(handle: Long): String?
        @JvmStatic private external fun wgVersion(): String?
    }

    suspend fun connect(config: String, vpnInterface: ParcelFileDescriptor) {
        withContext(Dispatchers.IO) {
            validateConfig(config)
            tunnelHandle = wgTurnOn("awg0", vpnInterface.fd, config)
            if (tunnelHandle < 0) throw Exception("AmneziaWG tunnel failed: $tunnelHandle")
            isConnected = true
        }
    }

    fun disconnect() {
        if (tunnelHandle >= 0) { wgTurnOff(tunnelHandle); tunnelHandle = -1 }
        isConnected = false
    }

    fun isConnected() = isConnected

    fun getStats(): TunnelStats? {
        if (tunnelHandle < 0) return null
        val raw = wgGetConfig(tunnelHandle) ?: return null
        var rx = 0L; var tx = 0L; var hs = 0L
        raw.lines().forEach { line ->
            when {
                line.startsWith("rx_bytes=")                  -> rx = line.substringAfter("=").toLongOrNull() ?: 0
                line.startsWith("tx_bytes=")                  -> tx = line.substringAfter("=").toLongOrNull() ?: 0
                line.startsWith("last_handshake_time_sec=")   -> hs = line.substringAfter("=").toLongOrNull() ?: 0
            }
        }
        return TunnelStats(rx, tx, hs)
    }

    private fun validateConfig(config: String) {
        require(config.contains("PrivateKey")) { "Missing PrivateKey" }
        require(config.contains("PublicKey"))  { "Missing PublicKey" }
        require(config.contains("Endpoint"))   { "Missing Endpoint" }
    }

    data class TunnelStats(val rxBytes: Long, val txBytes: Long, val lastHandshakeTimeSec: Long)
}
