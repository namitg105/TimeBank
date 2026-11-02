import 'package:fpdart/fpdart.dart';

import 'exceptions.dart';
import 'failure.dart';

/// Runs a data-source call and turns whatever it throws into a [Failure].
///
/// Every repository needs exactly this translation, so it lives here once
/// instead of being copied into each one. Exceptions never get past the
/// data layer: the domain and presentation layers only see Either.
Future<Either<Failure, T>> guard<T>(Future<T> Function() call) async {
  try {
    return Right(await call());
  } on ServerException catch (e) {
    return Left(e.isBusinessRule
        ? RuleFailure(e.message, oracleCode: e.oracleCode)
        : ServerFailure(e.message));
  } on NetworkException catch (e) {
    return Left(NetworkFailure(e.message));
  } catch (_) {
    return const Left(ServerFailure('Something went wrong. Please try again.'));
  }
}
