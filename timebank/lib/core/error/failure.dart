import 'package:equatable/equatable.dart';

/// What the domain layer knows about things going wrong.
///
/// The domain never sees a DioException, a SocketException or an Oracle
/// error code — those are details of how data happens to be fetched
/// today. It sees one of these, and can decide what the user should be
/// told without knowing anything about HTTP.
sealed class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

/// The server answered, but refused: a business rule was broken.
///
/// These carry a message written for a human, because it originated in a
/// database trigger raising RAISE_APPLICATION_ERROR -- for example
/// "Overdraft limit reached" or "That slot is already booked".
/// Show it to the user as-is.
final class RuleFailure extends Failure {
  final int oracleCode;
  const RuleFailure(super.message, {this.oracleCode = 0});

  @override
  List<Object?> get props => [message, oracleCode];
}

/// The request never reached the server, or it timed out.
final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Cannot reach the server.']);
}

/// The server broke, or returned something unreadable.
final class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Something went wrong on the server.']);
}

/// The input was rejected before it ever left the app.
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}
