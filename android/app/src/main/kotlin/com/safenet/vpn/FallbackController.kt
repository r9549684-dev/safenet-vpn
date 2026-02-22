package com.safenet.vpn

import android.util.Log

/**
 * FallbackController — управляет логикой переключения режимов VPN.
 *
 * Цепочка fallback:
 *   STEALTH → OBFS → BYEDPI → null (ошибка)
 *
 * Профили по странам:
 *   TR (Турция)     → STEALTH  (split, pos=2, fake=true)
 *   EG (Египет)     → OBFS     (AmneziaWG + ByeDPI)
 *   AE (ОАЭ)        → OBFS     (AmneziaWG + ByeDPI)
 *   SA (Саудовская) → OBFS     (AmneziaWG + ByeDPI)
 *   PK (Пакистан)   → BYEDPI   (disorder, pos=3)
 *   ID (Индонезия)  → BYEDPI   (split, pos=2)
 *   VE (Венесуэла)  → STEALTH  (fake, pos=1)
 *   DEFAULT         → STEALTH  (split, pos=2)
 */
class FallbackController {

    companion object {
        private const val TAG = "FallbackController"

        // Максимальное количество попыток fallback
        private const val MAX_RETRIES = 3
    }

    // ─── Типы ────────────────────────────────────────────────────────────────

    enum class FailedMode { STEALTH, OBFS, BYEDPI, VLESS }

    /**
     * Профиль страны: первичный режим + параметры ByeDPI.
     */
    data class CountryProfile(
        val countryCode   : String,
        val primaryMode   : StealthVPNService.VPNMode,
        val desyncMethod  : String  = "split",
        val splitPosition : Int     = 2,
        val useFakePacket : Boolean = false,
        val description   : String  = ""
    )

    // ─── Состояние ───────────────────────────────────────────────────────────

    private var retryCount : Int = 0

    // ─── Профили стран ───────────────────────────────────────────────────────

    private val countryProfiles: Map<String, CountryProfile> = mapOf(

        // Турция: жёсткий DPI, эффективен split с fake
        "TR" to CountryProfile(
            countryCode   = "TR",
            primaryMode   = StealthVPNService.VPNMode.STEALTH,
            desyncMethod  = "split",
            splitPosition = 2,
            useFakePacket = true,
            description   = "Turkey — split+fake DPI bypass"
        ),

        // Египет: глубокая инспекция, нужен обфусцированный туннель
        "EG" to CountryProfile(
            countryCode   = "EG",
            primaryMode   = StealthVPNService.VPNMode.OBFS,
            desyncMethod  = "disorder",
            splitPosition = 3,
            useFakePacket = false,
            description   = "Egypt — AmneziaWG obfuscated tunnel"
        ),

        // ОАЭ: блокировка VoIP и VPN, нужен OBFS
        "AE" to CountryProfile(
            countryCode   = "AE",
            primaryMode   = StealthVPNService.VPNMode.OBFS,
            desyncMethod  = "fake",
            splitPosition = 2,
            useFakePacket = true,
            description   = "UAE — obfuscated + fake packet"
        ),

        // Саудовская Аравия: аналогично ОАЭ
        "SA" to CountryProfile(
            countryCode   = "SA",
            primaryMode   = StealthVPNService.VPNMode.OBFS,
            desyncMethod  = "fake",
            splitPosition = 2,
            useFakePacket = true,
            description   = "Saudi Arabia — obfuscated + fake packet"
        ),

        // Пакистан: умеренный DPI, disorder эффективен
        "PK" to CountryProfile(
            countryCode   = "PK",
            primaryMode   = StealthVPNService.VPNMode.BYEDPI,
            desyncMethod  = "disorder",
            splitPosition = 3,
            useFakePacket = false,
            description   = "Pakistan — disorder desync"
        ),

        // Индонезия: базовый DPI, split достаточен
        "ID" to CountryProfile(
            countryCode   = "ID",
            primaryMode   = StealthVPNService.VPNMode.BYEDPI,
            desyncMethod  = "split",
            splitPosition = 2,
            useFakePacket = false,
            description   = "Indonesia — basic split"
        ),

        // Венесуэла: нестабильная сеть, fake помогает
        "VE" to CountryProfile(
            countryCode   = "VE",
            primaryMode   = StealthVPNService.VPNMode.STEALTH,
            desyncMethod  = "fake",
            splitPosition = 1,
            useFakePacket = true,
            description   = "Venezuela — fake packet desync"
        ),

        // Россия: disorder + fake
        "RU" to CountryProfile(
            countryCode   = "RU",
            primaryMode   = StealthVPNService.VPNMode.STEALTH,
            desyncMethod  = "disorder",
            splitPosition = 2,
            useFakePacket = true,
            description   = "Russia — disorder+fake"
        ),

        // Иран: максимальная обфускация
        "IR" to CountryProfile(
            countryCode   = "IR",
            primaryMode   = StealthVPNService.VPNMode.OBFS,
            desyncMethod  = "fake",
            splitPosition = 1,
            useFakePacket = true,
            description   = "Iran — full obfuscation"
        ),

        // Китай: только OBFS (GFW)
        "CN" to CountryProfile(
            countryCode   = "CN",
            primaryMode   = StealthVPNService.VPNMode.OBFS,
            desyncMethod  = "split",
            splitPosition = 2,
            useFakePacket = false,
            description   = "China — GFW bypass via AmneziaWG"
        )
    )

    // Профиль по умолчанию
    private val defaultProfile = CountryProfile(
        countryCode   = "XX",
        primaryMode   = StealthVPNService.VPNMode.STEALTH,
        desyncMethod  = "split",
        splitPosition = 2,
        useFakePacket = false,
        description   = "Default — basic split"
    )

    // ─── Цепочка fallback ────────────────────────────────────────────────────

    /**
     * Возвращает следующий режим после неудачи [failedMode].
     * Возвращает null если все режимы исчерпаны.
     */
    fun getNextMode(failedMode: FailedMode): StealthVPNService.VPNMode? {
        retryCount++

        if (retryCount > MAX_RETRIES) {
            Log.w(TAG, "Max retries ($MAX_RETRIES) exceeded")
            return null
        }

        val next = when (failedMode) {
            FailedMode.STEALTH -> StealthVPNService.VPNMode.OBFS
            FailedMode.OBFS    -> StealthVPNService.VPNMode.BYEDPI
            FailedMode.BYEDPI  -> StealthVPNService.VPNMode.VLESS
            FailedMode.VLESS   -> null
        }

        Log.i(TAG, "Fallback: $failedMode → $next (attempt $retryCount/$MAX_RETRIES)")
        return next
    }

    /**
     * Сбрасывает счётчик попыток (вызывать при успешном подключении).
     */
    fun resetRetries() {
        retryCount = 0
        Log.d(TAG, "Retry counter reset")
    }

    // ─── Профили стран ───────────────────────────────────────────────────────

    /**
     * Возвращает профиль для страны [countryCode].
     * Если страна не найдена — возвращает [defaultProfile].
     */
    fun getProfileForCountry(countryCode: String): CountryProfile {
        val profile = countryProfiles[countryCode.uppercase()] ?: defaultProfile
        Log.d(TAG, "Profile for $countryCode: ${profile.description}")
        return profile
    }

    /**
     * Возвращает список всех поддерживаемых стран.
     */
    fun getSupportedCountries(): List<String> = countryProfiles.keys.toList()

    /**
     * Проверяет, поддерживается ли страна явно (не через default).
     */
    fun isCountrySupported(countryCode: String): Boolean =
        countryProfiles.containsKey(countryCode.uppercase())

    // ─── Диагностика ─────────────────────────────────────────────────────────

    /**
     * Возвращает текущее состояние контроллера для отладки.
     */
    fun getDiagnostics(): Map<String, Any> = mapOf(
        "retry_count"         to retryCount,
        "max_retries"         to MAX_RETRIES,
        "supported_countries" to getSupportedCountries(),
        "fallback_chain"      to listOf("STEALTH", "OBFS", "BYEDPI", "VLESS")
    )

    /**
     * Логирует полный профиль страны (для отладки).
     */
    fun logProfileForCountry(countryCode: String) {
        val profile = getProfileForCountry(countryCode)
        Log.d(TAG, """
            Country Profile [$countryCode]:
              Mode:          ${profile.primaryMode}
              Desync method: ${profile.desyncMethod}
              Split pos:     ${profile.splitPosition}
              Fake packet:   ${profile.useFakePacket}
              Description:   ${profile.description}
        """.trimIndent())
    }
}
