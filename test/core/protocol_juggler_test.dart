import 'package:flutter_test/flutter_test.dart';
import 'package:safenet_vpn/core/protocol_juggler.dart';
import 'package:safenet_vpn/core/health_checker.dart';

/// Mock для SingboxVpn.start()
class MockSingboxVpn {
  static bool shouldSucceed = true;
  static int startCallCount = 0;
  static int stopCallCount = 0;

  static Future<bool> start(String config) async {
    startCallCount++;
    return shouldSucceed;
  }

  static Future<void> stop() async {
    stopCallCount++;
  }

  static void reset() {
    shouldSucceed = true;
    startCallCount = 0;
    stopCallCount = 0;
  }
}

/// Mock для HealthChecker
class MockHealthChecker {
  static bool shouldPass = true;
  static int checkCallCount = 0;

  static Future<bool> checkHealth() async {
    checkCallCount++;
    return shouldPass;
  }

  static void reset() {
    shouldPass = true;
    checkCallCount = 0;
  }
}

/// Mock для readiness check (isPortOpen + isTunnelLive)
class MockReadiness {
  static bool portOpen = true;
  static bool tunnelLive = true;
  static int portCheckCount = 0;
  static int tunnelCheckCount = 0;

  static Future<bool> isPortOpen(String host, int port) async {
    portCheckCount++;
    return portOpen;
  }

  static Future<bool> isTunnelLive(String host, int port) async {
    tunnelCheckCount++;
    return tunnelLive;
  }

  static void reset() {
    portOpen = true;
    tunnelLive = true;
    portCheckCount = 0;
    tunnelCheckCount = 0;
  }
}

void main() {
  group('ProtocolJuggler', () {
    setUp(() {
      MockSingboxVpn.reset();
      MockHealthChecker.reset();
      MockReadiness.reset();
    });

    group('protocol priority for RU', () {
      test('Trojan is first priority (works through DPI)', () {
        expect(ProtocolJuggler.ruProtocolPriority[0], ProtocolType.trojan);
      });

      test('VLESS is second priority (may be blocked by DPI)', () {
        expect(ProtocolJuggler.ruProtocolPriority[1], ProtocolType.vless);
      });

      test('AWG is third priority (fallback, also blocked by DPI)', () {
        expect(ProtocolJuggler.ruProtocolPriority[2], ProtocolType.awg);
      });
    });

    group('readinessBudget', () {
      test('Trojan budget is 12 seconds (SOCKS + Trojan + TLS handshake + HTTP)', () {
        expect(ProtocolJuggler.readinessBudget(ProtocolType.trojan).inSeconds, 12);
      });

      test('VLESS budget is 15 seconds (Reality/uTLS slower + health check 10s)', () {
        expect(ProtocolJuggler.readinessBudget(ProtocolType.vless).inSeconds, 15);
      });

      test('AWG budget is 3 seconds', () {
        expect(ProtocolJuggler.readinessBudget(ProtocolType.awg).inSeconds, 3);
      });
    });

    group('connectWithFailover', () {
      test('connects with Trojan when readiness check passes', () async {
        MockSingboxVpn.shouldSucceed = true;
        MockReadiness.portOpen = true;
        MockReadiness.tunnelLive = true;

        final configs = {
          ProtocolType.trojan: '{"type":"trojan"}',
          ProtocolType.vless: '{"type":"vless"}',
        };

        final result = await ProtocolJuggler.connectWithFailover(
          configs: configs,
          startVpn: MockSingboxVpn.start,
          stopVpn: MockSingboxVpn.stop,
          checkHealth: MockHealthChecker.checkHealth,
          isPortOpenFn: MockReadiness.isPortOpen,
          isTunnelLiveFn: MockReadiness.isTunnelLive,
        );

        expect(result.connected, isTrue);
        expect(result.protocol, ProtocolType.trojan);
        expect(MockSingboxVpn.startCallCount, 1);
      });

      test('falls back to VLESS when Trojan readiness check fails', () async {
        MockSingboxVpn.shouldSucceed = true;
        MockReadiness.portOpen = true;

        final configs = {
          ProtocolType.trojan: '{"type":"trojan"}',
          ProtocolType.vless: '{"type":"vless"}',
        };

        // Trojan: туннель никогда не работает, VLESS: работает
        String currentProtocol = 'trojan';
        Future<bool> conditionalTunnelLive(String host, int port) async {
          return currentProtocol == 'vless';
        }

        // Переключаем протокол после первого failover
        int startCount = 0;
        Future<bool> trackingStart(String config) async {
          startCount++;
          if (config.contains('vless')) {
            currentProtocol = 'vless';
          }
          return true;
        }

        final result = await ProtocolJuggler.connectWithFailover(
          configs: configs,
          startVpn: trackingStart,
          stopVpn: MockSingboxVpn.stop,
          checkHealth: MockHealthChecker.checkHealth,
          isPortOpenFn: MockReadiness.isPortOpen,
          isTunnelLiveFn: conditionalTunnelLive,
          budgetOverride: const Duration(seconds: 1), // Ускорение теста
        );

        expect(result.connected, isTrue);
        expect(result.protocol, ProtocolType.vless);
        expect(startCount, 2); // Trojan + VLESS
      });

      test('skips protocol when start() returns false', () async {
        MockSingboxVpn.shouldSucceed = false;
        MockReadiness.tunnelLive = true;

        final configs = {
          ProtocolType.trojan: '{"type":"trojan"}',
          ProtocolType.vless: '{"type":"vless"}',
        };

        final result = await ProtocolJuggler.connectWithFailover(
          configs: configs,
          startVpn: MockSingboxVpn.start,
          stopVpn: MockSingboxVpn.stop,
          checkHealth: MockHealthChecker.checkHealth,
          isPortOpenFn: MockReadiness.isPortOpen,
          isTunnelLiveFn: MockReadiness.isTunnelLive,
        );

        expect(result.connected, isFalse);
        expect(MockSingboxVpn.startCallCount, 2);
      });

      test('returns failure when all protocols fail', () async {
        MockSingboxVpn.shouldSucceed = true;
        MockReadiness.portOpen = true;
        MockReadiness.tunnelLive = false;

        final configs = {
          ProtocolType.trojan: '{"type":"trojan"}',
          ProtocolType.vless: '{"type":"vless"}',
          ProtocolType.awg: '{"type":"awg"}',
        };

        final result = await ProtocolJuggler.connectWithFailover(
          configs: configs,
          startVpn: MockSingboxVpn.start,
          stopVpn: MockSingboxVpn.stop,
          checkHealth: MockHealthChecker.checkHealth,
          isPortOpenFn: MockReadiness.isPortOpen,
          isTunnelLiveFn: MockReadiness.isTunnelLive,
          budgetOverride: const Duration(seconds: 1), // Ускорение теста
        );

        expect(result.connected, isFalse);
        expect(result.protocol, null);
        expect(MockSingboxVpn.startCallCount, 3);
        expect(MockSingboxVpn.stopCallCount, 3);
      });

      test('skips missing protocol configs', () async {
        MockSingboxVpn.shouldSucceed = true;
        MockReadiness.portOpen = true;
        MockReadiness.tunnelLive = true;

        final configs = <ProtocolType, String>{
          ProtocolType.vless: '{"type":"vless"}',
        };

        final result = await ProtocolJuggler.connectWithFailover(
          configs: configs,
          startVpn: MockSingboxVpn.start,
          stopVpn: MockSingboxVpn.stop,
          checkHealth: MockHealthChecker.checkHealth,
          isPortOpenFn: MockReadiness.isPortOpen,
          isTunnelLiveFn: MockReadiness.isTunnelLive,
        );

        expect(result.connected, isTrue);
        expect(result.protocol, ProtocolType.vless);
        expect(MockSingboxVpn.startCallCount, 1);
      });

      test('handles empty configs map', () async {
        final configs = <ProtocolType, String>{};

        final result = await ProtocolJuggler.connectWithFailover(
          configs: configs,
          startVpn: MockSingboxVpn.start,
          stopVpn: MockSingboxVpn.stop,
          checkHealth: MockHealthChecker.checkHealth,
          isPortOpenFn: MockReadiness.isPortOpen,
          isTunnelLiveFn: MockReadiness.isTunnelLive,
        );

        expect(result.connected, isFalse);
        expect(result.protocol, null);
        expect(MockSingboxVpn.startCallCount, 0);
      });

      test('handles exception in start() gracefully', () async {
        MockReadiness.portOpen = true;
        MockReadiness.tunnelLive = true;

        final configs = {
          ProtocolType.trojan: '{"type":"trojan"}',
          ProtocolType.vless: '{"type":"vless"}',
        };

        Future<bool> throwingStart(String config) async {
          MockSingboxVpn.startCallCount++;
          if (config.contains('trojan')) {
            throw Exception('Trojan start failed');
          }
          return true;
        }

        final result = await ProtocolJuggler.connectWithFailover(
          configs: configs,
          startVpn: throwingStart,
          stopVpn: MockSingboxVpn.stop,
          checkHealth: MockHealthChecker.checkHealth,
          isPortOpenFn: MockReadiness.isPortOpen,
          isTunnelLiveFn: MockReadiness.isTunnelLive,
        );

        expect(result.connected, isTrue);
        expect(result.protocol, ProtocolType.vless);
        expect(MockSingboxVpn.startCallCount, 2);
      });
    });

    group('ProtocolJugglerResult', () {
      test('success result has correct properties', () {
        final result = ProtocolJugglerResult(
          connected: true,
          protocol: ProtocolType.trojan,
        );

        expect(result.connected, isTrue);
        expect(result.protocol, ProtocolType.trojan);
      });

      test('failure result has null protocol', () {
        final result = ProtocolJugglerResult(
          connected: false,
          protocol: null,
        );

        expect(result.connected, isFalse);
        expect(result.protocol, isNull);
      });
    });
  });

  group('HealthChecker constants', () {
    test('timeout is 4 seconds', () {
      expect(HealthChecker.timeout.inSeconds, 4);
    });

    test('maxRetries is 3', () {
      expect(HealthChecker.maxRetries, 3);
    });

    test('primaryHealthUrl is gstatic generate_204', () {
      expect(HealthChecker.primaryHealthUrl, 'https://www.gstatic.com/generate_204');
    });

    test('fallbackHealthUrl is Cloudflare', () {
      expect(HealthChecker.fallbackHealthUrl, 'https://cp.cloudflare.com/generate_204');
    });

    test('uses sing-box proxy 127.0.0.1:2080', () {
      expect(HealthChecker.proxyHost, '127.0.0.1');
      expect(HealthChecker.proxyPort, 2080);
    });
  });

  group('ProtocolJuggler maxFailoverCycles', () {
    test('maxFailoverCycles is 3', () {
      expect(ProtocolJuggler.maxFailoverCycles, 3);
    });
  });
}
