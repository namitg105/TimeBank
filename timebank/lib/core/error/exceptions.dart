/// Thrown by data sources. Repositories catch these and convert them
/// into a [Failure], so exceptions never escape the data layer.
///
/// Keeping the two separate is what lets the domain layer stay unaware
/// of HTTP entirely.
class ServerException implements Exception {
  final String message;
  final int statusCode;
  final int oracleCode;

  const ServerException(this.message, {this.statusCode = 0, this.oracleCode = 0});

  /// True when the request was refused for something the user can fix:
  /// a broken rule (409), a bad or missing value (400), something that
  /// does not exist (404) or a wrong sign-in (401, 403). Only 5xx is a
  /// fault on the server's side.
  bool get isBusinessRule => statusCode >= 400 && statusCode < 500;

  /// Just the sentence, so `'$e'` on a screen never shows a class name.
  @override
  String toString() => message;
}

class NetworkException implements Exception {
  final String message;
  const NetworkException([
    this.message = 'Cannot reach the TimeBank server. Check that it is running, then try again.',
  ]);

  @override
  String toString() => message;
}
