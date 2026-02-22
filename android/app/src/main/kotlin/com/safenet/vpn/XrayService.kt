package com.safenet.vpn

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import java.io.File

/**
 * XrayService — фолбэк-режим VLESS+Reality через Xray.
 *
 * Стаб: конфиг сохраняется в файл, готов к интеграции с libxray.so/.aar.
 * Активируется в FallbackController как последний режим перед полной ошибкой.
 */
class XrayService : Service() {

    companion object {
        private const val TAG = "XrayService"
        const val EXTRA_VLESS_CONFIG = "vless_config_json"

        private var running = false

        fun isRunning(): Boolean = running
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val configJson = intent?.getStringExtra(EXTRA_VLESS_CONFIG)
        if (configJson == null) {
            Log.e(TAG, "No VLESS config provided, stopping")
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            // Сохранить конфиг в файл (готово к запуску через libxray.so или subprocess)
            val configFile = File(filesDir, "xray_config.json")
            configFile.writeText(configJson)
            Log.i(TAG, "VLESS config saved to ${configFile.absolutePath}")

            // TODO: запустить Xray через libxray.so или ProcessBuilder
            // Пример: XrayCore.start(configFile.absolutePath)
            running = true
            Log.i(TAG, "XrayService started (stub — awaiting libxray integration)")
        } catch (e: Exception) {
            Log.e(TAG, "XrayService start error: ${e.message}")
            running = false
            stopSelf()
            return START_NOT_STICKY
        }

        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        Log.i(TAG, "XrayService stopped")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
