import 'dart:io';
import 'dart:async';

/// Health Checker для проверки реального трафика через VPN туннель.
/// Использует HTTP GET через SOCKS5 прокси sing-box для проверки сквозного соединения.
class HealthChecker {
  static const String primaryHealthUrl = 'https://www.gstatic.com/generate_204';
  static const String fallbackHealthUrl = 'https://cp.cloudflare.com/generate_204';
  static const Duration timeout = Duration(seconds: 4);
  static const int maxRetries = 3;
  static const String proxyHost = '127.0.0.1';
  static const int proxyPort = 2080;

  /// Проверяет, что трафик реально идёт через VPN туннель.
  /// Использует прокси sing-box (127.0.0.1:2080) для гарантии прохождения через туннель.
  /// Возвращает true если health check пройден успешно.
  static Future<bool> checkHealth() async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final client = HttpClient();
        client.connectionTimeout = timeout;
        client.findProxy = (uri) => 'PROXY $proxyHost:$proxyPort';

        final request = await client.getUrl(Uri.parse(primaryHealthUrl));
        final response = await request.close().timeout(timeout);

        client.close(force: true);

        if (response.statusCode == 204 || response.statusCode == 200) {
          print('[HEALTH] ✅ Check passed via proxy (attempt $attempt, status ${response.statusCode})');
          return true;
        }
        print('[HEALTH] ⚠️ Unexpected status ${response.statusCode} (attempt $attempt)');
      } on TimeoutException {
        print('[HEALTH] ⏱️ Timeout (attempt $attempt/$maxRetries)');
      } on SocketException catch (e) {
        print('[HEALTH] 🔌 Socket error: ${e.message} (attempt $attempt/$maxRetries)');
      } catch (e) {
        print('[HEALTH] ❌ Error: $e (attempt $attempt/$maxRetries)');
      }

      if (attempt < maxRetries) {
        await Future.delayed(Duration(milliseconds: 500));
      }
    }

    // Fallback endpoint
    print('[HEALTH] 🔄 Trying fallback endpoint...');
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final client = HttpClient();
        client.connectionTimeout = timeout;
        client.findProxy = (uri) => 'PROXY $proxyHost:$proxyPort';

        final request = await client.getUrl(Uri.parse(fallbackHealthUrl));
        final response = await request.close().timeout(timeout);

        client.close(force: true);

        if (response.statusCode == 204 || response.statusCode == 200) {
          print('[HEALTH] ✅ Fallback check passed (attempt $attempt, status ${response.statusCode})');
          return true;
        }
        print('[HEALTH] ⚠️ Fallback unexpected status ${response.statusCode} (attempt $attempt)');
      } on TimeoutException {
        print('[HEALTH] ⏱️ Fallback timeout (attempt $attempt/$maxRetries)');
      } on SocketException catch (e) {
        print('[HEALTH] 🔌 Fallback socket error: ${e.message} (attempt $attempt/$maxRetries)');
      } catch (e) {
        print('[HEALTH] ❌ Fallback error: $e (attempt $attempt/$maxRetries)');
      }

      if (attempt < maxRetries) {
        await Future.delayed(Duration(milliseconds: 500));
      }
    }

    print('[HEALTH] ❌ All attempts failed (primary + fallback)');
    return false;
  }

  /// Периодический re-check во время сессии.
  /// Вызывает callback onFailed если health check не пройден.
  static void startPeriodicCheck({
    required Duration interval,
    required Future<void> Function() onFailed,
  }) {
    Timer.periodic(interval, (timer) async {
      final healthy = await checkHealth();
      if (!healthy) {
        print('[HEALTH] 🚨 Periodic check failed — triggering failover');
        await onFailed();
        timer.cancel();
      }
    });
  }
}
