import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:safenet_vpn/core/constants.dart';

/// Горячий запас конфигов.
///
/// Хранит очередь из [_maxSlots] конфигов на страну:
///   spare_config_<COUNTRY>_0  ← голова (используется первым)
///   spare_config_<COUNTRY>_1
///   spare_config_<COUNTRY>_2
///
/// [dequeue]  — взять голову и сдвинуть очередь
/// [enqueue]  — добавить в хвост (если есть место)
/// После каждого dequeue вызывать [consumeAndRefresh] для фонового пополнения.
class ConfigCacheService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _apiBase  = AppConstants.apiBaseUrl;
  static const _ttlHours = 24;
  static const _maxSlots = 3;

  // ── Ключи ──────────────────────────────────────────────────────────────────

  static String _slotKey(String country, int i) =>
      'spare_config_${country.toUpperCase()}_$i';
  static String _slotTsKey(String country, int i) =>
      'spare_config_ts_${country.toUpperCase()}_$i';
  static String _wgKey(String serverId) => 'wg_config_$serverId';
  static String _wgTsKey(String serverId) => 'wg_config_ts_$serverId';

  // ── ОЧЕРЕДЬ SINGBOX-КОНФИГОВ ───────────────────────────────────────────────

  /// Взять конфиг из головы очереди и сдвинуть остальные.
  /// Возвращает null если очередь пуста.
  static Future<Map<String, dynamic>?> dequeue(String country) async {
    Map<String, dynamic>? head;
    int headIdx = -1;

    // Найти первый живой слот
    for (int i = 0; i < _maxSlots; i++) {
      final entry = await _readSlot(country, i);
      if (entry != null) {
        head = entry;
        headIdx = i;
        break;
      }
    }
    if (headIdx < 0) return null;

    // Сдвинуть: каждый слот = следующий
    for (int i = headIdx; i < _maxSlots - 1; i++) {
      final next = await _readSlotRaw(country, i + 1);
      final nextTs = await _storage.read(key: _slotTsKey(country, i + 1));
      if (next != null && nextTs != null) {
        await _storage.write(key: _slotKey(country, i), value: next);
        await _storage.write(key: _slotTsKey(country, i), value: nextTs);
      } else {
        await _storage.delete(key: _slotKey(country, i));
        await _storage.delete(key: _slotTsKey(country, i));
      }
    }
    // Очистить последний (он теперь занят предыдущим)
    await _storage.delete(key: _slotKey(country, _maxSlots - 1));
    await _storage.delete(key: _slotTsKey(country, _maxSlots - 1));

    return head;
  }

  /// Добавить конфиг в конец очереди.
  /// Если очередь заполнена — перезаписать самый старый слот в конце.
  static Future<void> enqueue(String country, Map<String, dynamic> config) async {
    for (int i = 0; i < _maxSlots; i++) {
      final raw = await _storage.read(key: _slotKey(country, i));
      if (raw == null) {
        await _writeSlot(country, i, config);
        return;
      }
    }
    // Очередь полна — заменить последний слот
    await _writeSlot(country, _maxSlots - 1, config);
  }

  /// Количество живых (не устаревших) конфигов в очереди.
  static Future<int> queueLength(String country) async {
    int count = 0;
    for (int i = 0; i < _maxSlots; i++) {
      if (await _readSlot(country, i) != null) count++;
    }
    return count;
  }

  // ── WG-КЭШ (по serverId) ──────────────────────────────────────────────────

  static const _wgTtlHours = 48;

  /// Сохранить wg_config после успешного подключения.
  static Future<void> saveWgCache(String serverId, String wgConfig) async {
    await _storage.write(key: _wgKey(serverId), value: wgConfig);
    await _storage.write(
        key: _wgTsKey(serverId), value: DateTime.now().toIso8601String());
  }

  /// Прочитать закешированный wg_config. null если нет или устарел.
  static Future<String?> getWgCache(String serverId) async {
    final raw = await _storage.read(key: _wgKey(serverId));
    if (raw == null) return null;
    final tsStr = await _storage.read(key: _wgTsKey(serverId));
    if (tsStr != null) {
      final ts = DateTime.tryParse(tsStr);
      if (ts != null &&
          DateTime.now().difference(ts).inHours >= _wgTtlHours) {
        await _storage.delete(key: _wgKey(serverId));
        await _storage.delete(key: _wgTsKey(serverId));
        return null;
      }
    }
    return raw;
  }

  // ── ИСПОЛЬЗОВАНИЕ + ФОНОВОЕ ПОПОЛНЕНИЕ ────────────────────────────────────

  /// Вызвать после успешного подключения через очередной конфиг.
  /// 1. Уведомляет сервер (fire-and-forget).
  /// 2. Фоново загружает новый конфиг и кладёт в хвост очереди.
  static Future<void> consumeAndRefresh(
    String token,
    String country, {
    int? serverId,
  }) async {
    _consumeAndRefreshImpl(token, country, serverId: serverId);
  }

  static Future<void> _consumeAndRefreshImpl(
    String token,
    String country, {
    int? serverId,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    try {
      await dio.post(
        '$_apiBase/config/consume/$token',
        queryParameters: {'country': country},
      );
    } catch (_) {}

    await _fetchAndEnqueue(token, country, serverId: serverId);
  }

  /// Заранее заполнить очередь (вызывать при старте приложения).
  static Future<void> preload(
    String token,
    String country, {
    int? serverId,
  }) async {
    final len = await queueLength(country);
    // Добираем до maxSlots
    for (int i = len; i < _maxSlots; i++) {
      await _fetchAndEnqueue(token, country, serverId: serverId);
    }
  }

  static Future<void> _fetchAndEnqueue(
    String token,
    String country, {
    int? serverId,
  }) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
      ));
      final params = <String, dynamic>{'country': country};
      if (serverId != null) params['server_id'] = serverId;
      final resp = await dio.get(
        '$_apiBase/config/cached/$token',
        queryParameters: params,
      );
      if (resp.statusCode == 200 && resp.data is Map) {
        await enqueue(country, Map<String, dynamic>.from(resp.data as Map));
      }
    } catch (_) {}
  }

  // ── SINGBOX JSON (извлекает строку из конфига в очереди) ──────────────────

  /// Взять singbox JSON из головы очереди.
  /// Если очередь пуста — загрузить из сети напрямую.
  static Future<String?> dequeueSingboxJson(
    String token,
    String country,
  ) async {
    // 1. Из очереди
    final entry = await dequeue(country);
    if (entry != null) {
      if (entry['format'] == 'singbox') {
        final cfg = entry['config'];
        if (cfg is String) return cfg;
        if (cfg != null) return jsonEncode(cfg);
      }
      // Конфиг был, но не singbox-формата — попробуем ещё раз из сети
    }

    // 2. Сеть (резервный путь)
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ));
      final resp = await dio.get<String>(
        '$_apiBase/iran/subscribe/$token',
        queryParameters: {'fmt': 'singbox'},
        options: Options(responseType: ResponseType.plain),
      );
      if (resp.statusCode == 200 && resp.data != null) {
        return resp.data;
      }
    } catch (_) {}

    return null;
  }

  // ── СОВМЕСТИМЫЕ ОБЁРТКИ (старый API) ─────────────────────────────────────

  /// Устаревший метод — читает слот 0 без его удаления.
  static Future<Map<String, dynamic>?> getCached(String country) =>
      _readSlot(country, 0);

  /// Устаревший метод — кладёт в слот 0 (enqueue в хвост).
  static Future<void> saveCache(
          String country, Map<String, dynamic> config) =>
      enqueue(country, config);

  static Future<void> clearCache(String country) async {
    for (int i = 0; i < _maxSlots; i++) {
      await _storage.delete(key: _slotKey(country, i));
      await _storage.delete(key: _slotTsKey(country, i));
    }
  }

  static Future<bool> hasValidCache(String country) async =>
      (await queueLength(country)) > 0;

  // ── ПРИВАТНЫЕ ХЕЛПЕРЫ ─────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _readSlot(
      String country, int i) async {
    final raw = await _readSlotRaw(country, i);
    if (raw == null) return null;
    final tsStr = await _storage.read(key: _slotTsKey(country, i));
    if (tsStr != null) {
      final ts = DateTime.tryParse(tsStr);
      if (ts != null &&
          DateTime.now().difference(ts).inHours >= _ttlHours) {
        await _storage.delete(key: _slotKey(country, i));
        await _storage.delete(key: _slotTsKey(country, i));
        return null;
      }
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _readSlotRaw(String country, int i) =>
      _storage.read(key: _slotKey(country, i));

  static Future<void> _writeSlot(
      String country, int i, Map<String, dynamic> config) async {
    await _storage.write(
        key: _slotKey(country, i), value: jsonEncode(config));
    await _storage.write(
        key: _slotTsKey(country, i),
        value: DateTime.now().toIso8601String());
  }
}
