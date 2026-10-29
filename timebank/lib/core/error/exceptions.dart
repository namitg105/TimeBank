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

  /// True when the API said this was a broken business rule rather than a
  /// fault -- the controller returns 409 CONFLICT for those.
  bool get isBusinessRule => statusCode == 409;

  @override
  String toString() => 'ServerException($statusCode): $message';
}

class NetworkException implements Exception {
  final String message;
  const NetworkException([this.message = 'No connection to the server.']);
}
