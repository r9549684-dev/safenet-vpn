enum FailureType { network, auth, server, unknown }

class AppException implements Exception {
  final String message;
  final FailureType type;
  final int? statusCode;

  const AppException(this.message, {
    this.type = FailureType.unknown,
    this.statusCode,
  });

  factory AppException.network()  => const AppException('No internet connection', type: FailureType.network);
  factory AppException.auth()     => const AppException('Session expired. Please re-login.', type: FailureType.auth);
  factory AppException.server()   => const AppException('Server error. Try again later.', type: FailureType.server);

  @override
  String toString() => message;
}
