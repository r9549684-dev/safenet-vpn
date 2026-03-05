import 'package:flutter/material.dart';
import '../data/repositories/subscription_repo.dart';

class PricingModel {
  final double monthly, yearly, lifetime;
  const PricingModel({required this.monthly, required this.yearly, required this.lifetime});
}

class SubscriptionProvider extends ChangeNotifier {
  final _repo = SubscriptionRepository();

  PricingModel? _pricing;
  bool _loading = false;
  String? _error;
  String? _invoiceUrl;

  PricingModel? get pricing    => _pricing;
  bool          get isLoading  => _loading;
  String?       get error      => _error;
  String?       get invoiceUrl => _invoiceUrl;

  Future<void> loadPricing() async {
    _loading = true;
    notifyListeners();
    try {
      final d = await _repo.getPricing();
      _pricing = PricingModel(
        monthly:  (d['monthly_price']  as num).toDouble(),
        yearly:   (d['yearly_price']   as num).toDouble(),
        lifetime: (d['lifetime_price'] as num).toDouble(),
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> createPurchase(String plan, {bool useCredits = false, String country = ''}) async {
    _loading = true;
    _error   = null;
    notifyListeners();
    try {
      final d = await _repo.purchase(plan, useCredits: useCredits, country: country);
      _invoiceUrl = d['invoice_url'];
      return _invoiceUrl;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
