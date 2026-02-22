package com.safenet.vpn

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import java.io.*
import java.net.*
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class ByeDPIService : Service() {

    companion object {
        const val TAG = "ByeDPIService"
        const val PROXY_PORT = 1080
        private var instance: ByeDPIService? = null

        fun isRunning() = instance != null
    }

    private val isRunning = AtomicBoolean(false)
    private val executor = Executors.newCachedThreadPool()
    private var serverSocket: ServerSocket? = null

    // DPI bypass config
    data class ByeDPIConfig(
        val splitPosition: Int = 2,        // байт для split
        val fakeTTL: Int = 8,              // TTL для fake-пакета
        val desyncMode: String = "fake",   // fake | disorder | split
        val fakeHttps: Boolean = true,
        val wrongChecksum: Boolean = false,
        val wrongSeq: Boolean = false
    )

    private var config = ByeDPIConfig()

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val splitPos = intent?.getIntExtra("split_position", 2) ?: 2
        val desync = intent?.getStringExtra("desync_mode") ?: "fake"
        val fakeTTL = intent?.getIntExtra("fake_ttl", 8) ?: 8

        config = ByeDPIConfig(
            splitPosition = splitPos,
            fakeTTL = fakeTTL,
            desyncMode = desync
        )

        startProxy()
        return START_STICKY
    }

    private fun startProxy() {
        if (isRunning.getAndSet(true)) return

        executor.submit {
            try {
                serverSocket = ServerSocket(PROXY_PORT, 50, InetAddress.getByName("127.0.0.1"))
                Log.i(TAG, "ByeDPI SOCKS5 proxy started on port $PROXY_PORT")

                while (isRunning.get()) {
                    try {
                        val client = serverSocket!!.accept()
                        executor.submit { handleClient(client) }
                    } catch (e: SocketException) {
                        if (isRunning.get()) Log.e(TAG, "Accept error: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Proxy start failed: ${e.message}")
                isRunning.set(false)
            }
        }
    }

    private fun handleClient(client: Socket) {
        try {
            client.soTimeout = 10_000
            val input = client.getInputStream()
            val output = client.getOutputStream()

            // SOCKS5 handshake
            val version = input.read()
            if (version != 5) { client.close(); return }

            val nMethods = input.read()
            val methods = ByteArray(nMethods)
            input.read(methods)

            // No auth required
            output.write(byteArrayOf(5, 0))
            output.flush()

            // Read SOCKS5 request
            val req = ByteArray(4)
            input.read(req)
            if (req[1].toInt() != 1) { client.close(); return } // Only CONNECT

            val targetHost: String
            val targetPort: Int

            when (req[3].toInt()) {
                1 -> { // IPv4
                    val addr = ByteArray(4)
                    input.read(addr)
                    targetHost = InetAddress.getByAddress(addr).hostAddress ?: "0.0.0.0"
                }
                3 -> { // Domain
                    val len = input.read()
                    val domain = ByteArray(len)
                    input.read(domain)
                    targetHost = String(domain)
                }
                4 -> { // IPv6
                    val addr = ByteArray(16)
                    input.read(addr)
                    targetHost = InetAddress.getByAddress(addr).hostAddress ?: "::0"
                }
                else -> { client.close(); return }
            }

            val portBytes = ByteArray(2)
            input.read(portBytes)
            targetPort = ((portBytes[0].toInt() and 0xFF) shl 8) or (portBytes[1].toInt() and 0xFF)

            // Connect to target (через AmneziaWG туннель)
            val target = Socket()
            target.connect(InetSocketAddress(targetHost, targetPort), 5_000)

            // SOCKS5 success response
            output.write(byteArrayOf(5, 0, 0, 1, 0, 0, 0, 0, 0, 0))
            output.flush()

            // Relay with DPI bypass
            relayWithBypass(client, target, input, output)

        } catch (e: Exception) {
            Log.d(TAG, "Client handler error: ${e.message}")
        } finally {
            runCatching { client.close() }
        }
    }

    private fun relayWithBypass(
        client: Socket,
        target: Socket,
        clientIn: InputStream,
        clientOut: OutputStream
    ) {
        val targetIn = target.getInputStream()
        val targetOut = target.getOutputStream()

        var firstPacket = true

        // Client → Target (с DPI bypass)
        val toTarget = executor.submit {
            try {
                val buf = ByteArray(65536)
                var n: Int
                while (clientIn.read(buf).also { n = it } != -1) {
                    if (firstPacket && n > 0) {
                        firstPacket = false
                        writeWithBypass(targetOut, buf, n)
                    } else {
                        targetOut.write(buf, 0, n)
                        targetOut.flush()
                    }
                }
            } catch (_: Exception) {}
            runCatching { target.close() }
        }

        // Target → Client (без изменений)
        try {
            val buf = ByteArray(65536)
            var n: Int
            while (targetIn.read(buf).also { n = it } != -1) {
                clientOut.write(buf, 0, n)
                clientOut.flush()
            }
        } catch (_: Exception) {}

        toTarget.cancel(true)
        runCatching { client.close() }
        runCatching { target.close() }
    }

    /**
     * Запись первого пакета с DPI-обходом:
     * - split: разбиваем на 2 части (ломает SNI-детектор)
     * - fake: отправляем мусорный пакет перед реальным (fake TTL)
     */
    private fun writeWithBypass(out: OutputStream, data: ByteArray, len: Int) {
        when (config.desyncMode) {
            "split" -> {
                val pos = minOf(config.splitPosition, len - 1)
                out.write(data, 0, pos)
                out.flush()
                Thread.sleep(1) // микро-задержка между фрагментами
                out.write(data, pos, len - pos)
                out.flush()
            }
            "fake" -> {
                // Отправляем fake-данные (будут отброшены DPI из-за TTL)
                // В реальной реализации нужен raw socket с TTL=fakeTTL
                // Здесь — упрощённый split как fallback
                val pos = minOf(config.splitPosition, len - 1)
                out.write(data, 0, pos)
                out.flush()
                out.write(data, pos, len - pos)
                out.flush()
            }
            "disorder" -> {
                // Отправляем второй фрагмент первым, потом первый
                val pos = minOf(config.splitPosition, len - 1)
                out.write(data, pos, len - pos)
                out.flush()
                out.write(data, 0, pos)
                out.flush()
            }
            else -> {
                out.write(data, 0, len)
                out.flush()
            }
        }
    }

    fun stop() {
        isRunning.set(false)
        runCatching { serverSocket?.close() }
        executor.shutdownNow()
        instance = null
    }

    override fun onDestroy() {
        stop()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
