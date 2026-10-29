import 'package:fpdart/fpdart.dart';
import '../error/failure.dart';

/// Every use case implements this, so they are all invoked the same way.
///
/// A use case is one action the application can perform. Keeping each in
/// its own class is the single-responsibility principle applied: when
/// booking rules change, exactly one file changes.
abstract interface class UseCase<SuccessType, Params> {
  Future<Either<Failure, SuccessType>> call(Params params);
}

/// For use cases that take no arguments.
final class NoParams {
  const NoParams();
}
