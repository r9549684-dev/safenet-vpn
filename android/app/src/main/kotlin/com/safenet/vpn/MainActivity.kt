package com.safenet.vpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.safenet.vpn/methods"
    private val VPN_PERMISSION_CODE = 1001
    private val TAG = "MainActivity"

    // Сохраняем pending-запрос пока ждём разрешения VPN
    private var pendingResult: MethodChannel.Result? = null
    private var pendingOp: String? = null
    private var pendingConfig: String? = null
    private var pendingCountry: String? = null
    private var pendingByeDPI: Map<String, Any>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startHybrid" -> {
                        val config = call.argument<String>("config") ?: ""
                        val byeDPI = mapOf(
                            "split" to (call.argument<Int>("split") ?: 2),
                            "desync" to (call.argument<String>("desync") ?: "fake"),
                            "fake_ttl" to (call.argument<Int>("fake_ttl") ?: 8)
                        )
                        val desyncMode = byeDPI["desync"] as? String ?: "fake"
                        Log.i(TAG, "[USER MODE] Hybrid selected — WG + ByeDPI desync=$desyncMode")
                        startVpnWithPermission("hybrid", config, "XX", byeDPI, result)
                    }

                    "startAmnezia" -> {
                        val config = call.argument<String>("config") ?: ""
                        Log.i(TAG, "[USER MODE] AmneziaWG selected — pure WireGuard only")
                        startVpnWithPermission("amnezia", config, "XX", emptyMap(), result)
                    }

                    "startAuto" -> {
                        val config = call.argument<String>("config") ?: ""
                        val country = call.argument<String>("country") ?: "XX"
                        val byeDPI = mapOf(
                            "split" to (call.argument<Int>("split") ?: 2),
                            "desync" to (call.argument<String>("desync") ?: "fake"),
                            "fake_ttl" to (call.argument<Int>("fake_ttl") ?: 8)
                        )
                        Log.i(TAG, "[USER MODE] Stealth/Auto selected — country=$country")
                        startVpnWithPermission("auto", config, country, byeDPI, result)
                    }

                    "stop" -> {
                        StealthVPNService.stop(this)
                        result.success(mapOf("status" to "disconnected"))
                    }

                    "getStatus" -> {
                        val (rx, tx) = StealthVPNService.getTunnelStats()
                        result.success(mapOf(
                            "mode"          to StealthVPNService.getCurrentMode().name,
                            "proxy"         to StealthVPNService.getProxyAddress(),
                            "byedpi_running" to ByeDPIService.isRunning(),
                            "rx_bytes"      to rx,
                            "tx_bytes"      to tx
                        ))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Проверяем разрешение VPN. Если уже выдано — подключаем сразу.
     * Если нет — показываем системный диалог, ждём onActivityResult.
     */
    private fun startVpnWithPermission(
        op: String,
        config: String,
        country: String,
        byeDPI: Map<String, Any>,
        result: MethodChannel.Result
    ) {
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent != null) {
            Log.i(TAG, "VPN permission required, showing dialog")
            pendingResult  = result
            pendingOp      = op
            pendingConfig  = config
            pendingCountry = country
            pendingByeDPI  = byeDPI
            startActivityForResult(prepareIntent, VPN_PERMISSION_CODE)
        } else {
            Log.i(TAG, "VPN permission already granted, connecting...")
            launchVpnConnection(op, config, country, byeDPI, result)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_CODE) {
            val res = pendingResult ?: return
            if (resultCode == Activity.RESULT_OK) {
                Log.i(TAG, "VPN permission granted")
                launchVpnConnection(
                    pendingOp ?: "auto",
                    pendingConfig ?: "",
                    pendingCountry ?: "XX",
                    pendingByeDPI ?: emptyMap(),
                    res
                )
            } else {
                Log.w(TAG, "VPN permission denied by user")
                res.error("VPN_PERMISSION_DENIED", "User denied VPN permission", null)
            }
            clearPending()
        }
    }

    /**
     * Запускает подключение в корутине IO (GoBackend.setState блокирует до установки туннеля).
     * result.success/error вызываются на Main-потоке после завершения.
     */
    private fun launchVpnConnection(
        op: String,
        config: String,
        country: String,
        byeDPI: Map<String, Any>,
        result: MethodChannel.Result
    ) {
        CoroutineScope(Dispatchers.Main).launch {
            try {
                withContext(Dispatchers.IO) {
                    when (op) {
                        "hybrid"  -> StealthVPNService.startHybrid(applicationContext, config, byeDPI)
                        "amnezia" -> StealthVPNService.startAmneziaOnly(applicationContext, config)
                        else      -> StealthVPNService.startAuto(applicationContext, country, config, byeDPI)
                    }
                }
                result.success(mapOf(
                    "status" to "connected",
                    "mode"   to StealthVPNService.getCurrentMode().name,
                    "proxy"  to StealthVPNService.getProxyAddress()
                ))
            } catch (e: Exception) {
                Log.e(TAG, "VPN connection failed: ${e.message}", e)
                result.error("VPN_ERROR", e.message ?: "Unknown error", null)
            }
        }
    }

    private fun clearPending() {
        pendingResult  = null
        pendingOp      = null
        pendingConfig  = null
        pendingCountry = null
        pendingByeDPI  = null
    }
}
