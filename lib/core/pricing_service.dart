import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safenet_vpn/core/constants.dart';

/// Загружает и кэширует цены по стране с сервера.
///
/// Fallback: если API недоступен — используются цены из [AppConstants.pricing].
///
/// Пример использования:
///   final prices = await PricingService.getPlans('AE');
///   // prices = [{plan: 'weekly', usd: 4.99, local: 18, ...}, ...]
class PricingService {
  static const _apiBase  = AppConstants.apiBaseUrl;
  static const _cacheKey = 'pricing_cache';       // в SharedPreferences
  static const _cacheTsKey = 'pricing_cache_ts';
  static const _ttlMinutes = 60;

  // ── Публичный API ──────────────────────────────────────────────────────────

  /// Возвращает список тарифов для страны.
  /// Сначала пытается взять из кэша, потом из API, потом fallback.
  static Future<List<Map<String, dynamic>>> getPlans(String country) async {
    final cached = await _loadCache(country);
    if (cached != null) return cached;

    final fetched = await _fetchFromApi(country);
    if (fetched != null) {
      await _saveCache(country, fetched);
      return fetched;
    }

    return _fallback(country);
  }

  /// Цена конкретного тарифа в USD.
  static Future<double> getPriceUsd(String country, String plan) async {
    final plans = await getPlans(country);
    final p = plans.firstWhere(
      (e) => e['plan'] == plan,
      orElse: () => {},
    );
    return (p['usd'] as num?)?.toDouble()
        ?? AppConstants.pricing[country]?[plan]
        ?? 0.0;
  }

  /// Инвалидирует кэш (при смене страны или принудительном обновлении).
  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTsKey);
  }

  // ── Внутреннее ────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> _loadCache(String country) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getString('${_cacheTsKey}_${country.toUpperCase()}');
      if (ts != null) {
        final saved = DateTime.tryParse(ts);
        if (saved != null) {
          final age = DateTime.now().difference(saved);
          if (age.inMinutes < _ttlMinutes) {
            final raw = prefs.getString('${_cacheKey}_${country.toUpperCase()}');
            if (raw != null) {
              final decoded = jsonDecode(raw) as List;
              return decoded.cast<Map<String, dynamic>>();
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _saveCache(String country, List<Map<String, dynamic>> plans) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = country.toUpperCase();
      await prefs.setString('${_cacheKey}_$key', jsonEncode(plans));
      await prefs.setString('${_cacheTsKey}_$key', DateTime.now().toIso8601String());
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>?> _fetchFromApi(String country) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final qp = <String, dynamic>{};
      if (country.isNotEmpty) qp['country'] = country;
      final resp = await dio.get('$_apiBase/subscriptions/pricing', queryParameters: qp);
      if (resp.statusCode != 200 || resp.data is! Map) return null;
      final d = resp.data as Map<String, dynamic>;
      // Бэкенд возвращает flat keys: monthly_price, yearly_price, ...
      if (d.containsKey('monthly_price')) {
        final fb = _fallback(country);
        double fb0(String planId) =>
            (fb.firstWhere((e) => e['plan'] == planId, orElse: () => <String, dynamic>{})['usd'] as num?)?.toDouble() ?? 5.99;
        return [
          {'plan': 'weekly',    'usd': (d['weekly_price']    as num?)?.toDouble() ?? fb0('weekly')},
          {'plan': 'monthly',   'usd': (d['monthly_price']   as num).toDouble()},
          {'plan': 'quarterly', 'usd': (d['quarterly_price'] as num?)?.toDouble() ?? fb0('quarterly')},
          {'plan': 'yearly',    'usd': (d['yearly_price']    as num).toDouble()},
        ];
      }
      // Также поддерживаем формат массива
      if (d['plans'] is List) return (d['plans'] as List).cast<Map<String, dynamic>>();
    } catch (_) {}
    return null;
  }

  /// Fallback — цены из constants.dart если API недоступен.
  static List<Map<String, dynamic>> _fallback(String country) {
    final c = country.toUpperCase();
    final local = AppConstants.pricing[c] ?? {};
    return [
      {'plan': 'weekly',    'label': '1 Week',     'duration_days': 7,   'usd': local['weekly']    ?? 2.99},
      {'plan': 'monthly',   'label': '1 Month',    'duration_days': 30,  'usd': local['monthly']   ?? 5.99},
      {'plan': 'quarterly', 'label': '3 Months',   'duration_days': 90,  'usd': local['quarterly'] ?? 14.99},
      {'plan': 'yearly',    'label': '12 Months',  'duration_days': 365, 'usd': local['yearly']    ?? 29.99},
    ];
  }
}
