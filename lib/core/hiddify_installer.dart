import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// true только когда APK собран с --dart-define=BUNDLE_HIDDIFY=true
const bundleHiddify = bool.fromEnvironment('BUNDLE_HIDDIFY', defaultValue: false);

/// Сервис установки Hiddify из bundled APK (assets/hiddify/hiddify.apk).
/// Доступен только в Iran-билде (bundleHiddify == true).
class HiddifyInstaller {
  static const _channel = MethodChannel('com.safenet.safenet_vpn/installer');
  static const _assetPath = 'assets/hiddify/hiddify.apk';

  /// Проверяет установлен ли Hiddify (package: app.hiddify.com)
  static Future<bool> isInstalled() async {
    try {
      return await _channel.invokeMethod<bool>('isHiddifyInstalled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Извлекает APK из assets → temp dir → запускает системный установщик.
  /// Возвращает true если установщик запущен успешно.
  /// ВНИМАНИЕ: вызывать только при bundleHiddify == true.
  static Future<bool> install() async {
    assert(bundleHiddify, 'install() called in non-bundled build');
    try {
      // 1. Копируем APK из assets во временную директорию
      final data = await rootBundle.load(_assetPath);
      final bytes = data.buffer.asUint8List();

      final tmpDir = await getTemporaryDirectory();
      final apkFile = File('${tmpDir.path}/hiddify.apk');
      await apkFile.writeAsBytes(bytes, flush: true);

      // 2. Запускаем системный установщик через MethodChannel
      final launched = await _channel.invokeMethod<bool>(
        'installApk',
        {'path': apkFile.path},
      );
      return launched ?? false;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[HiddifyInstaller] error: ${e.code} — ${e.message}');
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('[HiddifyInstaller] unexpected error: $e');
      return false;
    }
  }
}
