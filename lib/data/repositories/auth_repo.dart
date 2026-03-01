import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../local/secure_storage.dart';
import '../remote/api_client.dart';
import '../remote/endpoints.dart';
import '../../domain/models/user.dart';

class AuthRepository {
  final _api = ApiClient();

  Future<String> getOrCreateDeviceId() async {
    var id = await SecureStorage.getDeviceId();
    if (id != null) return id;

    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      id = (await info.androidInfo).androidId ?? DateTime.now().millisecondsSinceEpoch.toString();
    } else {
      id = (await info.iosInfo).identifierForVendor ?? DateTime.now().millisecondsSinceEpoch.toString();
    }
    await SecureStorage.saveDeviceId(id);
    return id;
  }

  Future<User> register({
    required String country,
    required String language,
    String? referralCode,
  }) async {
    final deviceId = await getOrCreateDeviceId();
    final data = await _api.post<Map<String, dynamic>>(
      Endpoints.register,
      data: {
        'device_id':        deviceId,
        'country':          country,
        'language':         language,
        'referred_by_code': referralCode,
      },
    );
    await SecureStorage.saveToken(data['access_token']);
    await SecureStorage.saveCountry(country);
    await SecureStorage.saveLanguage(language);
    return User.fromJson(data['user']);
  }

  Future<User?> tryAutoLogin() async {
    final token = await SecureStorage.getToken();
    if (token == null) return null;
    try {
      final data = await _api.get<Map<String, dynamic>>(Endpoints.me);
      return User.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() => SecureStorage.clearAll();
}
