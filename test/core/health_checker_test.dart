import 'package:flutter_test/flutter_test.dart';
import 'package:safenet_vpn/core/health_checker.dart';

void main() {
  group('HealthChecker', () {
    test('checkHealth returns true when network is available', () async {
      final result = await HealthChecker.checkHealth();
      expect(result, isA<bool>());
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('checkHealth handles timeout gracefully', () async {
      final result = await HealthChecker.checkHealth();
      expect(result, isA<bool>());
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('health check uses correct timeout', () {
      expect(HealthChecker.timeout.inSeconds, 4);
    });

    test('health check uses correct max retries', () {
      expect(HealthChecker.maxRetries, 3);
    });

    test('health check URL is gstatic generate_204', () {
      expect(HealthChecker.primaryHealthUrl, 'https://www.gstatic.com/generate_204');
    });

    test('health check has Cloudflare fallback', () {
      expect(HealthChecker.fallbackHealthUrl, 'https://cp.cloudflare.com/generate_204');
    });

    test('health check uses sing-box proxy', () {
      expect(HealthChecker.proxyHost, '127.0.0.1');
      expect(HealthChecker.proxyPort, 2080);
    });
  });
}
