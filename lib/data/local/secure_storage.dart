import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Token
  static Future<void>    saveToken(String t)  => _storage.write(key: AppConstants.keyAccessToken, value: t);
  static Future<String?> getToken()           => _storage.read(key: AppConstants.keyAccessToken);
  static Future<void>    deleteToken()        => _storage.delete(key: AppConstants.keyAccessToken);

  // Device ID
  static Future<void>    saveDeviceId(String id) => _storage.write(key: AppConstants.keyDeviceId, value: id);
  static Future<String?> getDeviceId()           => _storage.read(key: AppConstants.keyDeviceId);

  // Language & Country
  static Future<void>    saveLanguage(String l) => _storage.write(key: AppConstants.keyLanguage, value: l);
  static Future<String?> getLanguage()          => _storage.read(key: AppConstants.keyLanguage);
  static Future<void>    saveCountry(String c)  => _storage.write(key: AppConstants.keyCountry, value: c);
  static Future<String?> getCountry()           => _storage.read(key: AppConstants.keyCountry);

  // Onboarding flag
  static Future<void> setOnboarded()    => _storage.write(key: AppConstants.keyOnboarded, value: 'true');
  static Future<bool> isOnboarded()    async {
    final v = await _storage.read(key: AppConstants.keyOnboarded);
    return v == 'true';
  }

  // Kill Switch
  static Future<void> saveKillSwitch(bool v)  => _storage.write(key: 'kill_switch',  value: v ? '1' : '0');
  static Future<bool> getKillSwitch()  async  => (await _storage.read(key: 'kill_switch'))  == '1';

  // Auto-connect
  static Future<void> saveAutoConnect(bool v) => _storage.write(key: 'auto_connect', value: v ? '1' : '0');
  static Future<bool> getAutoConnect() async  => (await _storage.read(key: 'auto_connect')) == '1';

  static Future<void> clearAll() => _storage.deleteAll();
}
