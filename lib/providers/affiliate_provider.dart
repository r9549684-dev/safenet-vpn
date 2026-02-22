import 'package:flutter/material.dart';
import '../data/remote/api_client.dart';

class AffiliateProvider extends ChangeNotifier {
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> withdrawals = [];
  List<Map<String, dynamic>> transactions = [];
  bool isLoading = false;
  String? error;

  final _api = ApiClient();

  Future<void> loadProfile() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      profile = await _api.get<Map<String, dynamic>>('/affiliate/profile');
      final wList = await _api.get<List<dynamic>>('/affiliate/withdrawals');
      withdrawals = List<Map<String, dynamic>>.from(wList);
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateWallet(String wallet) async {
    try {
      await _api.post('/affiliate/wallet', data: {'ton_wallet': wallet});
      await loadProfile();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> applyPartner(String wallet) async {
    try {
      await _api.post('/affiliate/apply-partner', data: {'ton_wallet': wallet});
      await loadProfile();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestWithdrawal(double amount) async {
    try {
      await _api.post('/affiliate/withdraw', data: {'amount_ton': amount});
      await loadProfile();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }
}
