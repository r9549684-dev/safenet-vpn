import '../remote/api_client.dart';
import '../remote/endpoints.dart';

class SubscriptionRepository {
  final _api = ApiClient();

  Future<Map<String, dynamic>> getPricing() =>
      _api.get<Map<String, dynamic>>(Endpoints.pricing);

  Future<Map<String, dynamic>> purchase(String plan, {bool useCredits = false}) =>
      _api.post<Map<String, dynamic>>(
        Endpoints.purchase(plan),
        params: {'use_compute_credits': useCredits},
      );

  Future<Map<String, dynamic>> getStatus() =>
      _api.get<Map<String, dynamic>>(Endpoints.subStatus);
}
