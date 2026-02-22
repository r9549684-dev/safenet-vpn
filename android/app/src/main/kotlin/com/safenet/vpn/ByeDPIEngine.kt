package com.safenet.vpn

import android.util.Log
import kotlinx.coroutines.*
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer

/**
 * ByeDPIEngine — движок обхода DPI для SafeNet VPN.
 *
 * Поддерживаемые методы десинхронизации:
 *   - split    : разбивает TLS ClientHello на два фрагмента
 *   - disorder : отправляет фрагменты в обратном порядке
 *   - fake     : отправляет фейковый пакет с TTL=1 перед реальным
 *   - oob      : out-of-band данные (для HTTP)
 *
 * Использование:
 *   engine.configure(desyncMethod = "split", splitPosition = 2, useFakePacket = true)
 *   engine.start(inputStream, outputStream)
 *   engine.stop()
 */
class ByeDPIEngine {

    companion object {
        private const val TAG = "ByeDPIEngine"
        private const val BUFFER_SIZE = 32767

        // TLS record type
        private const val TLS_HANDSHAKE: Byte = 0x16
        // HTTP methods prefix
        private val HTTP_METHODS = listOf("GET ", "POST", "HEAD", "PUT ", "DELE", "OPTI", "PATC")
    }

    // ─── Конфигурация ────────────────────────────────────────────────────────

    private var desyncMethod  : String  = "split"
    private var splitPosition : Int     = 2
    private var useFakePacket : Boolean = true

    private var isRunning     : Boolean = false
    private var engineJob     : Job?    = null
    private val engineScope   = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // ─── Статистика ──────────────────────────────────────────────────────────

    var packetsProcessed : Long = 0L
        private set
    var bytesSent        : Long = 0L
        private set
    var tlsPacketsDesync : Long = 0L
        private set

    // ─── Публичный API ───────────────────────────────────────────────────────

    /**
     * Настройка параметров движка.
     * Должна вызываться до [start].
     */
    fun configure(
        desyncMethod  : String  = "split",
        splitPosition : Int     = 2,
        useFakePacket : Boolean = true
    ) {
        this.desyncMethod  = desyncMethod
        this.splitPosition = splitPosition
        this.useFakePacket = useFakePacket
        Log.d(TAG, "Configured: method=$desyncMethod split=$splitPosition fake=$useFakePacket")
    }

    /**
     * Запуск обработки пакетов.
     * Читает из [inputStream] (VPN tun), обрабатывает, пишет в [outputStream].
     */
    fun start(inputStream: FileInputStream, outputStream: FileOutputStream) {
        if (isRunning) {
            Log.w(TAG, "Engine already running")
            return
        }
        isRunning = true
        packetsProcessed = 0L
        bytesSent = 0L
        tlsPacketsDesync = 0L

        engineJob = engineScope.launch {
            Log.i(TAG, "ByeDPI engine started (method=$desyncMethod)")
            val buffer = ByteBuffer.allocate(BUFFER_SIZE)

            try {
                while (isRunning && isActive) {
                    buffer.clear()
                    val length = inputStream.read(buffer.array())

                    if (length <= 0) {
                        delay(1)
                        continue
                    }

                    buffer.limit(length)
                    packetsProcessed++

                    processPacket(buffer, outputStream)
                }
            } catch (e: CancellationException) {
                Log.d(TAG, "Engine coroutine cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "Engine error: ${e.message}")
            } finally {
                Log.i(TAG, "ByeDPI engine stopped. Processed: $packetsProcessed pkts, $bytesSent bytes")
            }
        }
    }

    /**
     * Остановка движка.
     */
    fun stop() {
        isRunning = false
        engineJob?.cancel()
        engineJob = null
        Log.i(TAG, "ByeDPI engine stop requested")
    }

    // ─── Обработка пакетов ───────────────────────────────────────────────────

    private fun processPacket(packet: ByteBuffer, output: FileOutputStream) {
        val data   = packet.array()
        val length = packet.limit()

        when {
            isTLSClientHello(data, length) -> {
                tlsPacketsDesync++
                Log.v(TAG, "TLS ClientHello detected, applying $desyncMethod")
                applyDesync(data, length, output)
            }
            isHTTPRequest(data, length) -> {
                Log.v(TAG, "HTTP request detected, applying split")
                applySplit(data, length, output, minOf(splitPosition, length / 2))
            }
            else -> {
                // Пропускаем без изменений
                writeBytes(output, data, 0, length)
            }
        }
    }

    // ─── Методы десинхронизации ──────────────────────────────────────────────

    private fun applyDesync(data: ByteArray, length: Int, output: FileOutputStream) {
        when (desyncMethod) {
            "split"    -> applySplit(data, length, output, splitPosition)
            "disorder" -> applyDisorder(data, length, output, splitPosition)
            "fake"     -> applyFake(data, length, output)
            "oob"      -> applyOOB(data, length, output)
            else       -> writeBytes(output, data, 0, length)
        }
    }

    /**
     * SPLIT: разбивает пакет на два фрагмента по [pos].
     * DPI видит неполный ClientHello и не может идентифицировать SNI.
     */
    private fun applySplit(data: ByteArray, length: Int, output: FileOutputStream, pos: Int) {
        val splitAt = pos.coerceIn(1, length - 1)

        writeBytes(output, data, 0, splitAt)
        output.flush()
        Thread.sleep(1)
        writeBytes(output, data, splitAt, length - splitAt)
        output.flush()

        bytesSent += length
    }

    /**
     * DISORDER: отправляет второй фрагмент раньше первого.
     * Некоторые DPI-системы не умеют собирать пакеты в обратном порядке.
     */
    private fun applyDisorder(data: ByteArray, length: Int, output: FileOutputStream, pos: Int) {
        val splitAt = pos.coerceIn(1, length - 1)

        // Второй фрагмент первым
        writeBytes(output, data, splitAt, length - splitAt)
        output.flush()
        Thread.sleep(1)

        // Первый фрагмент вторым
        writeBytes(output, data, 0, splitAt)
        output.flush()

        bytesSent += length
    }

    /**
     * FAKE: отправляет фейковый пакет с TTL=1 (будет дропнут на первом хопе),
     * затем реальный пакет. DPI видит «мусор» и сбрасывает состояние.
     */
    private fun applyFake(data: ByteArray, length: Int, output: FileOutputStream) {
        if (useFakePacket) {
            val fake = buildFakePacket(data, length)
            writeBytes(output, fake, 0, fake.size)
            output.flush()
            Thread.sleep(1)
        }

        writeBytes(output, data, 0, length)
        output.flush()

        bytesSent += length
    }

    /**
     * OOB: вставляет 1 байт OOB-данных между фрагментами.
     * Эффективно против некоторых российских и турецких DPI.
     */
    private fun applyOOB(data: ByteArray, length: Int, output: FileOutputStream) {
        val splitAt = splitPosition.coerceIn(1, length - 1)

        writeBytes(output, data, 0, splitAt)
        // OOB-байт (0x00) — сигнализирует о срочных данных
        output.write(byteArrayOf(0x00))
        output.flush()
        Thread.sleep(1)

        writeBytes(output, data, splitAt, length - splitAt)
        output.flush()

        bytesSent += length
    }

    // ─── Построение фейкового пакета ─────────────────────────────────────────

    /**
     * Создаёт копию пакета с TTL=1.
     * Такой пакет будет дропнут первым маршрутизатором,
     * но DPI-система на уровне провайдера его «увидит».
     */
    private fun buildFakePacket(original: ByteArray, length: Int): ByteArray {
        val fake = original.copyOf(length)
        // IP-заголовок: TTL находится по смещению 8
        if (fake.size > 8) {
            fake[8] = 1 // TTL = 1
            // Пересчитываем контрольную сумму IP-заголовка
            recalculateIPChecksum(fake)
        }
        return fake
    }

    private fun recalculateIPChecksum(packet: ByteArray) {
        if (packet.size < 20) return
        val ihl = (packet[0].toInt() and 0x0F) * 4
        if (packet.size < ihl) return

        // Обнуляем поле контрольной суммы
        packet[10] = 0
        packet[11] = 0

        var sum = 0
        var i = 0
        while (i < ihl - 1) {
            sum += ((packet[i].toInt() and 0xFF) shl 8) or (packet[i + 1].toInt() and 0xFF)
            i += 2
        }
        while (sum shr 16 != 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        val checksum = sum.inv() and 0xFFFF
        packet[10] = (checksum shr 8).toByte()
        packet[11] = (checksum and 0xFF).toByte()
    }

    // ─── Детекторы протоколов ────────────────────────────────────────────────

    /**
     * Определяет TLS ClientHello (тип записи 0x16, версия >= TLS 1.0).
     * Проверяет IP-заголовок → TCP → TLS record.
     */
    private fun isTLSClientHello(data: ByteArray, length: Int): Boolean {
        if (length < 40) return false

        // Проверяем IP-протокол (TCP = 6)
        val protocol = data[9].toInt() and 0xFF
        if (protocol != 6) return false

        val ipHeaderLen = (data[0].toInt() and 0x0F) * 4
        if (length <= ipHeaderLen + 13) return false

        val tcpHeaderLen = ((data[ipHeaderLen + 12].toInt() and 0xF0) shr 4) * 4
        val payloadStart = ipHeaderLen + tcpHeaderLen

        if (length <= payloadStart + 5) return false

        val contentType = data[payloadStart].toInt() and 0xFF
        val versionMajor = data[payloadStart + 1].toInt() and 0xFF
        val versionMinor = data[payloadStart + 2].toInt() and 0xFF

        // TLS Handshake (0x16) + версия >= 3.1 (TLS 1.0)
        return contentType == 0x16 && versionMajor == 0x03 && versionMinor >= 0x01
    }

    /**
     * Определяет HTTP-запрос по первым 4 байтам.
     */
    private fun isHTTPRequest(data: ByteArray, length: Int): Boolean {
        if (length < 20) return false

        val ipHeaderLen = (data[0].toInt() and 0x0F) * 4
        val tcpHeaderLen = ((data[ipHeaderLen + 12].toInt() and 0xF0) shr 4) * 4
        val payloadStart = ipHeaderLen + tcpHeaderLen

        if (length <= payloadStart + 4) return false

        val prefix = String(data, payloadStart, 4, Charsets.US_ASCII)
        return HTTP_METHODS.any { prefix.startsWith(it.take(4)) }
    }

    // ─── Утилиты ─────────────────────────────────────────────────────────────

    private fun writeBytes(output: FileOutputStream, data: ByteArray, offset: Int, length: Int) {
        try {
            output.write(data, offset, length)
        } catch (e: Exception) {
            Log.w(TAG, "Write error: ${e.message}")
        }
    }

    /**
     * Возвращает текущую статистику движка.
     */
    fun getStats(): Map<String, Long> = mapOf(
        "packets_processed" to packetsProcessed,
        "bytes_sent"        to bytesSent,
        "tls_desync"        to tlsPacketsDesync
    )
}
