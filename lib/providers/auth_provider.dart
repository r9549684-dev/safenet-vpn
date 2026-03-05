import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../data/repositories/auth_repo.dart';
import '../data/local/secure_storage.dart';
import '../domain/models/user.dart';

enum AuthState { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final _repo = AuthRepository();

  AuthState _state   = AuthState.initial;
  User?     _user;
  String    _language = 'en';
  String    _country  = 'IR';
  String?   _error;

  AuthState get state    => _state;
  User?     get user     => _user;
  String    get language => _language;
  String    get country  => _country;
  String?   get error    => _error;
  bool get isAuth        => _state == AuthState.authenticated;

  AuthProvider() { _init(); }

  Future<void> _init() async {
    _language = await SecureStorage.getLanguage() ?? 'en';
    final savedCountry = await SecureStorage.getCountry();
    if (savedCountry != null) {
      _country = savedCountry;
    }
    _user = await _repo.tryAutoLogin();
    _state = _user != null ? AuthState.authenticated : AuthState.unauthenticated;
    notifyListeners();
    // Детекция страны по IP (асинх, не блокирует авторизацию)
    if (savedCountry == null) {
      _country = await _detectCountry();
      await SecureStorage.saveCountry(_country);
      notifyListeners();
    }
  }

  static Future<String> _detectCountry() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
      ));
      final resp = await dio.get<Map<String, dynamic>>('https://ipapi.co/json/');
      if (resp.statusCode == 200 && resp.data != null) {
        final code = resp.data!['country_code'] as String?;
        if (code != null && code.length == 2) return code.toUpperCase();
      }
    } catch (_) {}
    return 'IR'; // fallback
  }

  Future<bool> register({required String country, String? referralCode}) async {
    _state = AuthState.loading;
    _error = null;
    notifyListeners();
    try {
      _user = await _repo.register(
        country: country,
        language: _language,
        referralCode: referralCode,
      );
      await SecureStorage.setOnboarded();
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _state = AuthState.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> setLanguage(String lang) async {
    _language = lang;
    await SecureStorage.saveLanguage(lang);
    notifyListeners();
  }

  Future<void> refreshUser() async {
    final user = await _repo.tryAutoLogin();
    if (user != null) {
      _user = user;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    _user  = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }
}
