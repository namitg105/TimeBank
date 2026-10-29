import 'package:fpdart/fpdart.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/audit.dart';
import '../../domain/entities/ledger_entry.dart';
import '../../domain/repositories/ledger_repository.dart';
import '../datasources/ledger_remote_datasource.dart';

class LedgerRepositoryImpl implements LedgerRepository {
  final LedgerRemoteDataSource remote;
  const LedgerRepositoryImpl(this.remote);

  @override
  Future<Either<Failure, List<LedgerEntry>>> passbook(int studentId) =>
      _guard(() => remote.passbook(studentId));

  @override
  Future<Either<Failure, Audit>> audit() => _guard(() => remote.audit());

  @override
  Future<Either<Failure, int>> postAdjustment({
    required int studentId,
    required String type,
    required double amount,
    required String remarks,
  }) =>
      _guard(() => remote.postAdjustment({
            'studentId': studentId,
            'type': type,
            'amount': amount,
            'remarks': remarks,
          }));

  @override
  Future<Either<Failure, List<String>>> leaderboard() =>
      _guard(() => remote.leaderboard());

  @override
  Future<Either<Failure, List<String>>> collusionReport() =>
      _guard(() => remote.collusion());

  Future<Either<Failure, T>> _guard<T>(Future<T> Function() call) async {
    try {
      return Right(await call());
    } on ServerException catch (e) {
      return Left(e.isBusinessRule
          ? RuleFailure(e.message, oracleCode: e.oracleCode)
          : ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Unexpected error: $e'));
    }
  }
}
