import '../remote/api_client.dart';
import '../remote/endpoints.dart';

class ReferralRepository {
  final _api = ApiClient();

  Future<Map<String, dynamic>> getStats() =>
      _api.get<Map<String, dynamic>>(Endpoints.referralStats);

  Future<List> getRewards() =>
      _api.get<List>(Endpoints.referralRewards);

  Future<Map<String, dynamic>> requestPayout(int telegramUserId) =>
      _api.post<Map<String, dynamic>>(
        Endpoints.requestPayout,
        params: {'telegram_user_id': telegramUserId},
      );
}
